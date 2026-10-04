// Markee renderer — runs inside WKWebView.
// Receives render({source, fileName, docBase, readOnly, wikiIndex, navigated, scrollTo})
// from Swift. Posts back (kind) ready/outline/error/findResult/scrollSection/
// docStats/copyText/taskToggle/navigate via webkit.messageHandlers.markee.

(function () {
    "use strict";

    const post = (kind, payload = {}) => {
        try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.markee) {
                window.webkit.messageHandlers.markee.postMessage(Object.assign({ kind }, payload));
            }
        } catch (_) { /* ignore */ }
    };

    const errMsg = (e) => (e && e.message) ? e.message : String(e);

    let isReadOnly = false;        // set per-render; gates navigation + chrome
    let currentFileName = "";      // set per-render; the export's <title>

    const showToast = (msg) => {
        const t = document.getElementById("toast");
        if (!t) return;
        t.textContent = msg;
        t.hidden = false;
        clearTimeout(showToast._t);
        showToast._t = setTimeout(() => { t.hidden = true; }, 4500);
    };

    // ---- markdown-it setup -------------------------------------------------
    // The pipeline itself lives in render-core.js (shared with Node tests).
    const core = window.markeeRenderCore;
    const escapeHtml = core.escapeHtml;
    let md = null;
    function buildRenderer() {
        const pick = (...names) => {
            for (const n of names) { if (window[n]) return window[n]; }
            return undefined;
        };
        return core.createRenderer({
            markdownit: window.markdownit,
            footnote: pick("markdownitFootnote", "markdownItFootnote"),
            deflist: pick("markdownitDeflist", "markdownItDeflist"),
            attrs: pick("markdownItAttrs", "markdownitAttrs"),
            taskLists: pick("markdownitTaskLists", "markdownItTaskLists"),
            hljs: window.hljs
        });
    }

    // ---- active-heading scroll-spy -----------------------------------------
    let headingObserver = null;
    let lastActiveID = null;
    let currentHeadings = [];
    let scrollRAF = null;

    function rebuildHeadingObserver(headings) {
        if (headingObserver) {
            headingObserver.disconnect();
            headingObserver = null;
        }
        lastActiveID = null;
        currentHeadings = headings || [];
        if (!headings || headings.length === 0 || !("IntersectionObserver" in window)) return;

        // Fire when a heading is anywhere in the top 20% strip of the viewport.
        // rootMargin "0px 0px -80% 0px" shrinks the bottom of the observation
        // box to leave only the top 20% — any heading crossing in/out of that
        // band triggers a re-pick.
        headingObserver = new IntersectionObserver(() => {
            recomputeActiveHeading(headings);
        }, { rootMargin: "0px 0px -80% 0px", threshold: 0 });

        headings.forEach((h) => headingObserver.observe(h));

        // Initial pick
        recomputeActiveHeading(headings);
    }

    function scrollHandler() {
        if (scrollRAF) return;
        scrollRAF = requestAnimationFrame(() => {
            scrollRAF = null;
            recomputeActiveHeading(currentHeadings);
        });
    }

    function recomputeActiveHeading(headings) {
        const positions = headings.map((h) => ({ id: h.id, top: h.getBoundingClientRect().top }));
        const id = pickActiveHeading(positions, window.innerHeight);
        if (id !== lastActiveID) {
            lastActiveID = id;
            post("scrollSection", { id });
        }
    }

    // Pure helpers (slugify, pickActiveHeading) live in util.js so they're
    // testable from Node. util.js exposes them via window.markeeUtil.
    const { slugify, pickActiveHeading } = window.markeeUtil;

    function onTaskToggle(ev) {
        const cb = ev.currentTarget;
        const li = cb.closest("li.task-list-item");
        if (!li || !li.dataset.line) return;
        const line = parseInt(li.dataset.line, 10);
        if (Number.isNaN(line)) return;
        post("taskToggle", { line, checked: !!cb.checked });
    }

    // Post-render DOM pass for screen-only affordances (copy buttons, language
    // badges, heading anchors). Every injected element carries `markee-chrome`
    // so it is stripped from Export HTML and hidden in Print/PDF. Skipped in
    // read-only contexts (Quick Look preview/thumbnail) where there is no
    // pasteboard/menu to back the affordances.
    function decorateContent(article, payload) {
        if (!article || payload.readOnly) return;
        decorateCodeBlocks(article);
        decorateHeadings(article, payload.fileName);
    }

    // Add a language badge (when labeled) + hover copy button to each
    // highlighted code block. Skips mermaid blocks (replaced by SVG).
    function decorateCodeBlocks(article) {
        const { codeLanguageFromClass } = window.markeeUtil;
        article.querySelectorAll("pre.hljs").forEach((pre) => {
            if (pre.querySelector(":scope > .markee-code-toolbar")) return;
            const code = pre.querySelector("code");
            const toolbar = document.createElement("div");
            toolbar.className = "markee-chrome markee-code-toolbar";

            const lang = code ? codeLanguageFromClass(code.className) : null;
            if (lang) {
                const badge = document.createElement("span");
                badge.className = "markee-code-lang";
                badge.textContent = lang;
                toolbar.appendChild(badge);
            }

            const btn = document.createElement("button");
            btn.type = "button";
            btn.className = "markee-code-copy";
            btn.textContent = "Copy";
            btn.setAttribute("aria-label", "Copy code");
            btn.addEventListener("click", () => {
                const text = code ? code.textContent : "";
                post("copyText", { text: text, note: "Code copied" });
            });
            toolbar.appendChild(btn);

            pre.appendChild(toolbar);
        });
    }

    // Add a hover "copy link to heading" affordance. The visible glyph is a CSS
    // ::after on the button (never a text node), and this runs after outline
    // building, so heading textContent / the outline stay clean.
    function decorateHeadings(article, fileName) {
        const { headingLinkMarkdown } = window.markeeUtil;
        article.querySelectorAll("h1, h2, h3, h4, h5, h6").forEach((h) => {
            if (!h.id) return;
            if (h.querySelector(":scope > .markee-heading-anchor")) return;
            const btn = document.createElement("button");
            btn.type = "button";
            btn.className = "markee-chrome markee-heading-anchor";
            btn.setAttribute("aria-label", "Copy link to this heading");
            btn.title = "Copy link to heading";
            btn.addEventListener("click", () => {
                const text = headingLinkMarkdown(h.textContent, fileName || "", h.id);
                post("copyText", { text: text, note: "Heading link copied" });
            });
            h.appendChild(btn);
        });
    }

    // ---- currency masking ---------------------------------------------------
    // Swap money dollars for a private-use sentinel so KaTeX's auto-render
    // can't pair them as inline-math delimiters, then put them back. The tag
    // list mirrors auto-render's own default ignoredTags, so text KaTeX never
    // looks at is never touched.
    const CURRENCY_MASK = "\uE000";
    const MATH_SKIP = "script, noscript, style, textarea, pre, code, option";

    function eachMathTextNode(root, fn) {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode(node) {
                const p = node.parentElement;
                if (!p || p.closest(MATH_SKIP)) return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
            }
        });
        let n;
        while ((n = walker.nextNode())) fn(n);
    }

    function maskCurrencyDollarsIn(root) {
        const { maskCurrencyDollars } = window.markeeUtil;
        let touched = false;
        eachMathTextNode(root, (n) => {
            const masked = maskCurrencyDollars(n.nodeValue, CURRENCY_MASK);
            if (masked !== n.nodeValue) { n.nodeValue = masked; touched = true; }
        });
        return function unmask() {
            if (!touched) return;
            eachMathTextNode(root, (n) => {
                if (n.nodeValue.indexOf(CURRENCY_MASK) !== -1) {
                    n.nodeValue = n.nodeValue.split(CURRENCY_MASK).join("$");
                }
            });
        };
    }

    // ---- render -------------------------------------------------------------
    // Returns true once the document is in the DOM, false if it couldn't be
    // rendered (Quick Look then falls back to the system preview/icon).
    function render(payload) {
        const article = document.getElementById("content");
        if (!article) return false;
        isReadOnly = !!payload.readOnly;
        const isNav = !!payload.navigated;   // true on cross-file navigation
        // Re-render invalidates find ranges; reset the Swift counter to the
        // neutral "unknown" state (total -1) rather than a false "0 of 0".
        clearFind();
        post("findResult", { current: 0, total: -1 });
        if (!md) md = buildRenderer();
        if (!md) {
            showToast("Renderer not loaded. Run 'just fetch-vendor' to install vendored libs.");
            article.innerHTML = `<pre style="white-space:pre-wrap">${escapeHtml(payload.source || "")}</pre>`;
            post("outline", { items: [] });
            return false;
        }

        // Update <base> so relative URLs in the source resolve against the doc dir
        let base = document.querySelector("base");
        if (!base) {
            base = document.createElement("base");
            document.head.appendChild(base);
        }
        if (payload.docBase) base.setAttribute("href", payload.docBase);

        // Preserve scroll position
        const prevScroll = window.scrollY;
        const prevHeight = document.documentElement.scrollHeight;

        currentFileName = payload.fileName || "";

        // Per-render slug counter for heading-id de-duplication
        const slugCount = new Map();

        const fm = core.stripFrontMatter(payload.source || "");
        const src = fm.body;
        const frontMatterLines = fm.lineCount;

        // Parse → tokens (with line maps) → render, instead of md.render(),
        // so we can pull heading source-line numbers off the tokens.
        let tokens;
        let html;
        try {
            const env = { wikiIndex: payload.wikiIndex || {}, lineOffset: frontMatterLines };
            tokens = md.parse(src, env);
            html = md.renderer.render(tokens, md.options, env);
        } catch (err) {
            const msg = "Markdown render error: " + (err && err.message ? err.message : String(err));
            post("error", { message: msg });
            showToast(msg);
            return false;
        }

        article.innerHTML = html;

        // Document stats for the native word-count pill — computed here, before
        // decorateContent injects chrome text ("Copy", language badges) and
        // before KaTeX/Mermaid run, so the count reflects only document prose.
        {
            const { wordCount, readingMinutes } = window.markeeUtil;
            const words = wordCount(article.textContent || "");
            post("docStats", { words: words, minutes: readingMinutes(words) });
        }

        // Assign ids to headings + build outline
        const items = [];
        const headingEls = Array.from(article.querySelectorAll("h1, h2, h3, h4, h5, h6"));
        // The page's own ids (#content, #toast, …) are reserved: a "## Toast"
        // heading taking id="toast" picked up the toast's fixed-position CSS
        // and was overwritten by the next toast. Explicit document ids that
        // collide are dropped; the rest are taken before slugging so generated
        // slugs never duplicate them.
        const pageIds = new Set();
        document.querySelectorAll("[id]").forEach((el) => {
            if (el === article || !article.contains(el)) pageIds.add(el.id);
        });
        article.querySelectorAll("[id]").forEach((el) => {
            if (pageIds.has(el.id)) el.removeAttribute("id");
            else slugCount.set(el.id, 1);
        });
        pageIds.forEach((id) => slugCount.set(id, 1));
        // Markdown headings carry data-line from render-core; raw-HTML <hN>
        // tags have no source map, so their outline entry has no line.
        headingEls.forEach((h) => {
            const level = parseInt(h.tagName.substring(1), 10);
            const title = h.textContent || "";
            const id = h.id || slugify(title, slugCount);
            h.id = id;
            const item = { id, level, title };
            if (h.dataset.line !== undefined) item.line = Number(h.dataset.line);
            items.push(item);
        });
        post("outline", { items });

        // Re-wire the active-heading observer to the new heading set.
        // Disconnect happens inside rebuildHeadingObserver — calling it
        // here (rather than at the end of render) prevents the old
        // observer from briefly observing detached nodes.
        rebuildHeadingObserver(headingEls);

        // Task items arrive with data-line (their line in the ORIGINAL file,
        // front matter included) stamped by render-core from the token maps.
        // readOnly (Quick Look) renders checkboxes non-interactive — a click
        // there cannot write back to the file, so don't pretend it can.
        const readOnly = !!payload.readOnly;
        const taskItems = article.querySelectorAll("li.task-list-item[data-line]");
        taskItems.forEach((li) => {
            const cb = li.querySelector('input[type="checkbox"]');
            if (cb) {
                if (readOnly) {
                    cb.disabled = true;
                } else {
                    cb.addEventListener("click", onTaskToggle);
                }
            }
        });

        // Screen-only affordances (copy/lang badges, heading anchors). After
        // outline + task wiring so it can't perturb heading textContent.
        decorateContent(article, payload);

        // KaTeX. Currency dollars are masked out first so prose holding two
        // amounts ("~$127k … ~$350M") isn't paired into one inline-math run;
        // the mask is restored either way, including when KaTeX throws.
        if (window.renderMathInElement) {
            const unmask = maskCurrencyDollarsIn(article);
            try {
                window.renderMathInElement(article, {
                    delimiters: [
                        { left: "$$", right: "$$", display: true },
                        { left: "\\(", right: "\\)", display: false },
                        { left: "\\[", right: "\\]", display: true },
                        { left: "$", right: "$", display: false }
                    ],
                    throwOnError: false
                });
            } catch (e) {
                post("error", { message: "Math rendering failed: " + errMsg(e) });
            } finally {
                unmask();
            }
        }

        // Mermaid — the 2.5 MB bundle is loaded on demand only when the
        // document actually contains a diagram. Diagram-free renders never
        // pay the parse cost (matters most for fresh Quick Look processes).
        if (article.querySelector("pre.mermaid")) {
            ensureMermaid(() => runMermaid(article));
        }

        // Restore scroll — but a navigation lands at the top of the new doc
        // (then jumps to a fragment if the link had one). Same-file re-renders
        // keep the reader's position.
        if (isNav) {
            window.scrollTo(0, 0);
            if (payload.scrollTo) scrollToHeading(payload.scrollTo);
        } else {
            const newHeight = document.documentElement.scrollHeight;
            const ratio = prevHeight > 0 ? prevScroll / prevHeight : 0;
            const targetY = Math.min(prevScroll, Math.max(0, newHeight - window.innerHeight));
            if (Math.abs(newHeight - prevHeight) / Math.max(prevHeight, 1) > 0.5) {
                window.scrollTo(0, ratio * newHeight);
            } else {
                window.scrollTo(0, targetY);
            }
        }
        return true;
    }

    // decodeURIComponent throws on stray `%` (e.g. `#50%-off`); fall back raw.
    function safeDecode(s) {
        try { return decodeURIComponent(s); } catch (_) { return s; }
    }

    function scrollToHeading(id) {
        const el = document.getElementById(id);
        if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    // ---- lazy Mermaid -------------------------------------------------------
    // "unloaded" | "loading" | "ready"
    let mermaidState = "unloaded";
    let mermaidWaiters = [];

    // Load mermaid.min.js (UMD bundle — not the ESM split build) once. On load,
    // dispatch markee:mermaid-ready (the existing listener runs mermaid.initialize
    // synchronously during dispatch), THEN invoke each queued `then`. On failure
    // the queue is dropped — diagrams stay as code — and a later render retries.
    function ensureMermaid(then) {
        if (mermaidLib()) { then(); return; }
        mermaidWaiters.push(then);
        if (mermaidState === "loading") return;
        mermaidState = "loading";
        const s = document.createElement("script");
        s.src = "markee-app://app/vendor/mermaid/mermaid.min.js";
        s.onload = () => {
            mermaidState = "ready";
            window.dispatchEvent(new Event("markee:mermaid-ready"));
            const waiters = mermaidWaiters;
            mermaidWaiters = [];
            waiters.forEach((fn) => fn());
        };
        s.onerror = () => {
            mermaidState = "unloaded";
            mermaidWaiters = [];
            post("error", { message: "Mermaid failed to load; diagrams are shown as code." });
        };
        document.head.appendChild(s);
    }

    // Effective theme: the Preferences override (data-theme) wins over the OS.
    function mermaidTheme() {
        const forced = document.documentElement.getAttribute("data-theme");
        const dark = forced ? forced === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
        return dark ? "dark" : "default";
    }

    // The loaded library, or null. Never test `window.mermaid` for truthiness:
    // a heading slugged "mermaid" (`## Mermaid`) makes it the <h2> element via
    // named window access until the script loads.
    function mermaidLib() {
        const m = window.mermaid;
        return mermaidState === "ready" && m && typeof m.run === "function" ? m : null;
    }

    // The theme Mermaid was last initialized with; a redraw happens only when
    // the effective theme moves away from it.
    let mermaidThemeInUse = null;

    function initMermaid() {
        try {
            mermaidThemeInUse = mermaidTheme();
            // look/layout pinned explicitly: Mermaid 12 changes both defaults
            // (re-laying out and recolouring existing diagrams), so a future
            // bump keeps today's appearance unless we opt in.
            mermaidLib().initialize({
                startOnLoad: false, theme: mermaidThemeInUse, look: "classic", layout: "dagre"
            });
        } catch (_) { /* ignore */ }
    }

    // mermaid.run calls are chained, never concurrent: two overlapping runs
    // over the same <pre> fight over its contents ("x.firstChild is null").
    let mermaidQueue = Promise.resolve();

    function runMermaid(article) {
        const mermaid = mermaidLib();
        if (!mermaid) return;
        mermaidQueue = mermaidQueue.then(() => {
            // The theme may have changed while no diagram was on screen.
            if (mermaidTheme() !== mermaidThemeInUse) initMermaid();
            article.querySelectorAll("pre.mermaid").forEach((el) => {
                // Mermaid replaces the source with its SVG; keep the source so
                // a theme change can redraw the diagram.
                if (!el.hasAttribute("data-processed")) el.dataset.mermaidSource = el.textContent;
                else if (el.dataset.mermaidSource !== undefined) el.textContent = el.dataset.mermaidSource;
                el.removeAttribute("data-processed");
            });
            return mermaid.run({ querySelector: "#content pre.mermaid" });
        }).catch((e) => {
            post("error", { message: "Diagram rendering failed: " + errMsg(e) });
        });
    }

    // ---- find ---------------------------------------------------------------
    // JS-owned find. Primary path uses the CSS Custom Highlight API (Range-keyed,
    // no DOM mutation, never leaks into Export/Print). When unavailable, falls
    // back to window.find (current match only; total reported as -1 = unknown).
    let findState = { query: "", ranges: [], current: -1 };

    // The two Highlight objects are registered once and mutated in place.
    // Swapping a fresh Highlight in under the same registry key makes WebKit
    // repaint only the *incoming* ranges' text nodes, so a text node that
    // matched the old query but not the new one keeps its stale paint — typing
    // "f" then "freeze" left stray "f"s highlighted in every text node with no
    // "freeze" in it (inline markup splits a paragraph into many such nodes).
    // Removing each range from the registered Highlight invalidates it.
    let hlAll = null, hlCurrent = null;

    function highlightSupported() {
        return !!(window.CSS && CSS.highlights && typeof window.Highlight === "function");
    }

    function ensureHighlights() {
        if (!hlAll) { hlAll = new Highlight(); CSS.highlights.set("markee-find", hlAll); }
        if (!hlCurrent) { hlCurrent = new Highlight(); CSS.highlights.set("markee-find-current", hlCurrent); }
    }

    // Per-range delete rather than clear(): each removal invalidates its own
    // text node, which is exactly the repaint that was going missing.
    function emptyHighlight(hl) {
        if (!hl) return;
        for (const r of Array.from(hl)) hl.delete(r);
    }

    function clearFind() {
        findState = { query: "", ranges: [], current: -1 };
        if (highlightSupported()) {
            ensureHighlights();
            emptyHighlight(hlAll);
            emptyHighlight(hlCurrent);
        }
    }

    function buildFindRanges(root, query) {
        const { findMatchOffsets } = window.markeeUtil;
        const ranges = [];
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode(node) {
                if (!node.nodeValue) return NodeFilter.FILTER_REJECT;
                const p = node.parentElement;
                // .katex-mathml is KaTeX's visually-hidden MathML twin: matches
                // there would be counted and stepped to but never visible.
                if (!p || p.closest(".markee-chrome, .katex-mathml, script, style")) return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
            }
        });
        let node;
        while ((node = walker.nextNode())) {
            const offsets = findMatchOffsets(node.nodeValue, query);
            for (const off of offsets) {
                const r = document.createRange();
                r.setStart(node, off);
                r.setEnd(node, off + query.length);
                ranges.push(r);
            }
        }
        return ranges;
    }

    function applyFindHighlights() {
        if (!highlightSupported()) return;
        ensureHighlights();
        emptyHighlight(hlAll);
        for (const r of findState.ranges) hlAll.add(r);
        emptyHighlight(hlCurrent);
        if (findState.current >= 0 && findState.ranges[findState.current]) {
            hlCurrent.add(findState.ranges[findState.current]);
        }
    }

    function scrollRangeIntoView(range) {
        const rect = range.getBoundingClientRect();
        if (rect.top < 0 || rect.bottom > window.innerHeight) {
            window.scrollTo({ top: window.scrollY + rect.top - window.innerHeight * 0.3, behavior: "smooth" });
        }
    }

    function find(query, opts) {
        opts = opts || {};
        const article = document.getElementById("content");
        const q = String(query || "");
        if (!article || !q) { clearFind(); post("findResult", { current: 0, total: 0 }); return; }

        if (!highlightSupported()) {
            const found = typeof window.find === "function"
                ? window.find(q, false, !!opts.backwards, true, false, false, false)
                : false;
            post("findResult", { current: found ? 1 : 0, total: found ? -1 : 0 });
            return;
        }

        if (q !== findState.query) {
            findState.query = q;
            findState.ranges = buildFindRanges(article, q);
            findState.current = -1;
        }
        const total = findState.ranges.length;
        if (total === 0) { applyFindHighlights(); post("findResult", { current: 0, total: 0 }); return; }
        findState.current = opts.backwards
            ? (findState.current - 1 + total) % total
            : (findState.current + 1) % total;
        applyFindHighlights();
        scrollRangeIntoView(findState.ranges[findState.current]);
        post("findResult", { current: findState.current + 1, total: total });
    }

    // ---- export standalone HTML --------------------------------------------
    async function fetchAsDataURL(url) {
        const blob = await (await fetch(url)).blob();
        return await new Promise((resolve, reject) => {
            const r = new FileReader();
            r.onerror = reject;
            r.onload = () => resolve(r.result);
            r.readAsDataURL(blob);
        });
    }

    // Replace each relative woff2 url() in `css` with a data URI. The woff/ttf
    // fallbacks in the same src list aren't vendored and are left to fail.
    async function inlineFontURLs(css, sheetHref) {
        const urls = Array.from(new Set(css.match(/url\((?!data:)[^)]+\.woff2\)/g) || []));
        for (const u of urls) {
            const rel = u.slice(4, -1).replace(/^["']|["']$/g, "");
            try {
                const data = await fetchAsDataURL(new URL(rel, sheetHref).href);
                css = css.split(u).join(`url(${data})`);
            } catch (_) { /* leave it */ }
        }
        return css;
    }

    async function exportStandalone() {
        const article = document.getElementById("content");
        if (!article) return "";
        const clone = article.cloneNode(true);
        // Screen-only chrome (copy buttons, badges, heading anchors) never
        // ships in canonical exports.
        clone.querySelectorAll(".markee-chrome").forEach((e) => e.remove());
        // Source-line stamps only mean something next to the file on disk.
        clone.querySelectorAll("[data-line]").forEach((e) => e.removeAttribute("data-line"));
        clone.querySelectorAll("[data-mermaid-source]").forEach((e) => e.removeAttribute("data-mermaid-source"));

        // Inline images as data URIs
        const imgs = Array.from(clone.querySelectorAll("img"));
        await Promise.all(imgs.map(async (img) => {
            const src = img.getAttribute("src");
            if (!src) return;
            try {
                img.setAttribute("src", await fetchAsDataURL(src));
            } catch (_) { /* leave src as-is */ }
        }));

        // Gather stylesheets. Skip the screen-scoped user-css block and the
        // dark highlight sheet: exported HTML ships canonical (default, light)
        // look, like Print/PDF — the recipient shouldn't inherit the author's
        // theme, accent, font or custom CSS. Any other sheet keeps its media
        // scope, which inlining would otherwise drop.
        const hasMath = !!clone.querySelector(".katex");
        const sheets = Array.from(document.querySelectorAll('link[rel="stylesheet"], style'));
        const cssParts = [];
        for (const s of sheets) {
            if (s.id === "markee-user-css" || s.id === "hljs-dark") continue;
            let css;
            if (s.tagName === "STYLE") {
                css = s.textContent;
            } else {
                const href = s.getAttribute("href"); if (!href) continue;
                try {
                    css = await (await fetch(href)).text();
                    // KaTeX's @font-face urls are relative to its sheet and
                    // wouldn't resolve beside the exported file: inline them.
                    if (hasMath && /katex/i.test(href)) css = await inlineFontURLs(css, href);
                } catch (_) { continue; }
            }
            const media = s.getAttribute("media");
            cssParts.push(media && media !== "all" ? `@media ${media} {\n${css}\n}` : css);
        }

        // Build standalone HTML
        const head = `<!doctype html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(currentFileName || "Markee export")}</title>
<style>
${cssParts.join("\n\n")}
</style>
</head>
<body>
`;
        const foot = "\n</body>\n</html>\n";
        return head + clone.outerHTML + foot;
    }

    // Flowing plain text of the rendered content: syntax stripped, paragraphs
    // flow. Mirrors exportStandalone's clone-and-strip. innerText (not
    // textContent) so block boundaries become newlines and soft wraps collapse.
    function renderedText() {
        const article = document.getElementById("content");
        if (!article) return "";
        const clone = article.cloneNode(true);
        // Screen-only chrome + KaTeX's hidden MathML tree would pollute/duplicate
        // the text; drop them (same markee-chrome contract exportStandalone uses).
        clone.querySelectorAll(".markee-chrome, .katex-mathml").forEach((e) => e.remove());
        // innerText needs a laid-out element; a detached clone degrades to
        // textContent (no block breaks). Attach off-screen to force layout.
        clone.style.position = "absolute";
        clone.style.left = "-99999px";
        clone.style.top = "0";
        clone.setAttribute("aria-hidden", "true");
        document.body.appendChild(clone);
        let text = "";
        try { text = clone.innerText || ""; } finally { clone.remove(); }
        return text.replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
    }

    // Unwrapped Markdown (syntax kept). Delegates to reflow.js, reusing the
    // renderer's md instance so it sees the same block grammar; lazily builds it
    // in case reflow is invoked before the first render().
    function reflowMarkdown(source) {
        if (!md) md = buildRenderer();
        if (!window.markeeReflow || !md) return String(source == null ? "" : source);
        return window.markeeReflow.reflow(source, md);
    }

    // ---- zoom ---------------------------------------------------------------
    // Swift drives zoom by calling window.markee.setZoom(factor). CSS `zoom`
    // on <html> reflows text and scales code blocks, images, KaTeX, and
    // Mermaid output uniformly. Invalid/non-positive factors reset to 1.
    function setZoom(factor) {
        const f = Number(factor);
        document.documentElement.style.zoom =
            (Number.isFinite(f) && f > 0) ? String(f) : "1";
    }

    // ---- settings / theming -------------------------------------------------
    // Swift calls window.markee.applySettings(payload) on ready and on every
    // settings change. Everything here is delivered through the screen-scoped
    // <style id="markee-user-css"> block or the data-theme attribute, so none of
    // it reaches the print stylesheet — PDFs/print stay canonical by construction.
    function applySettings(s) {
        s = s || {};
        const root = document.documentElement;

        // Theme override: system clears the attribute (OS governs); light/dark
        // force it. The dark highlight.js sheet is OS-gated by default; retarget
        // its media query so syntax colors follow the forced theme.
        const theme = s.theme === "light" || s.theme === "dark" ? s.theme : "system";
        if (theme === "system") {
            root.removeAttribute("data-theme");
        } else {
            root.setAttribute("data-theme", theme);
        }
        const darkSheet = document.getElementById("hljs-dark");
        if (darkSheet) {
            // "screen" (not "all"): the .hljs dark background/foreground come from
            // this sheet directly and outrank theme.css's pre/code rules, so an
            // "all" media would leak the dark code background into Print/PDF/Export.
            // Keep it screen-only so the print path stays canonical (light).
            if (theme === "dark") darkSheet.media = "screen";
            else if (theme === "light") darkSheet.media = "not all";
            else darkSheet.media = "screen and (prefers-color-scheme: dark)";
        }
        redrawMermaidIfThemeChanged();

        // Accent + base font as :root variable overrides, then the user's CSS,
        // all inside the one screen-scoped block.
        const styleEl = document.getElementById("markee-user-css");
        if (styleEl) {
            const vars = [];
            const accent = typeof s.accent === "string" && /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(s.accent)
                ? s.accent : "";
            // !important so a user override beats the theme token blocks, which
            // are higher specificity (e.g. :root[data-theme="dark"] is (0,2,0))
            // and set --accent themselves. Safe for print: this whole block is
            // media="screen", so it's inert in PDF/Print regardless of !important.
            if (accent) {
                vars.push(`--accent:${accent} !important`);
                vars.push(`--accent-bg-soft:color-mix(in srgb, ${accent} 7%, transparent) !important`);
            }
            const bf = Number(s.baseFont);
            if (Number.isFinite(bf) && bf > 0) vars.push(`--base-font:${bf}px !important`);
            const rootRule = vars.length ? `:root{${vars.join(";")}}` : "";
            const userCSS = typeof s.userCSS === "string" ? s.userCSS : "";
            styleEl.textContent = rootRule + (userCSS ? "\n" + userCSS : "");
        }
    }

    // ---- expose API ---------------------------------------------------------
    window.markee = {
        render,
        scrollToHeading,
        exportStandalone,
        reflow: reflowMarkdown,
        renderedText,
        setZoom,
        applySettings,
        toast: showToast,
        find,
        clearFind
    };

    // Mermaid loads as a classic UMD <script> on demand (ensureMermaid). Its
    // onload dispatches markee:mermaid-ready; this listener initializes mermaid
    // with the current OS color scheme. Actual diagram rendering is driven by
    // the onload waiter callback queued in render(), not from here.
    window.addEventListener("markee:mermaid-ready", () => {
        if (mermaidLib()) initMermaid();
    });

    // Diagrams are drawn in the theme current at render time; redraw them when
    // the effective theme changes (Preferences override or OS appearance).
    function redrawMermaidIfThemeChanged() {
        if (mermaidThemeInUse === null || mermaidTheme() === mermaidThemeInUse) return;
        const article = document.getElementById("content");
        if (!mermaidLib() || !article || !article.querySelector("pre.mermaid")) return;
        initMermaid();
        runMermaid(article);
    }
    matchMedia("(prefers-color-scheme: dark)").addEventListener("change", redrawMermaidIfThemeChanged);

    window.addEventListener("scroll", scrollHandler, { passive: true });
    window.addEventListener("resize", scrollHandler, { passive: true });

    // Intercept clicks on markee-doc:// links ending in .md — navigate in-window
    // (or open a new window on ⌘/ctrl/middle-click). Capture phase so it beats
    // the default anchor handling. Other link schemes keep their existing path.
    function interceptLinkClick(ev, forceNewWindow) {
        const a = ev.target && ev.target.closest && ev.target.closest("a[href]");
        if (!a) return;
        let url;
        try { url = new URL(a.href); } catch (_) { return; }
        if (url.protocol !== "markee-doc:") return;
        const fragment = url.hash ? safeDecode(url.hash.slice(1)) : "";
        // `#id` links (footnotes, TOCs) resolve against <base href> — the doc's
        // directory — so they'd otherwise navigate the main frame away.
        const base = document.querySelector("base");
        const basePath = base ? new URL(base.href).pathname : "";
        if (url.hash && url.pathname === basePath && url.search === "") {
            ev.preventDefault();
            scrollToHeading(fragment);
            return;
        }
        if (isReadOnly) return;
        if (!/\.(md|markdown)$/i.test(url.pathname)) return;
        ev.preventDefault();
        post("navigate", {
            path: url.pathname,
            fragment: fragment,
            newWindow: forceNewWindow || ev.metaKey || ev.ctrlKey
        });
    }
    document.addEventListener("click", (ev) => interceptLinkClick(ev, false), true);

    // markdown-it-task-lists wraps each task item's text in a <label>, so a
    // click anywhere in the item activates the checkbox. That made checklist
    // text impossible to select: releasing a selection drag fired a click on
    // the label, which flipped the box (writing to the file) and collapsed the
    // selection. Cancel the label's activation for clicks that end a selection;
    // a deliberate click still toggles. Capture phase, no stopPropagation, so
    // the link interceptor above keeps seeing its clicks.
    let taskPointerDown = { x: 0, y: 0 };
    document.addEventListener("mousedown", (ev) => {
        taskPointerDown = { x: ev.clientX, y: ev.clientY };
    }, true);
    document.addEventListener("click", (ev) => {
        const t = ev.target;
        if (!t || !t.closest || !t.closest("li.task-list-item")) return;
        const sel = window.getSelection();
        const suppress = window.markeeUtil.shouldSuppressTaskToggle({
            onCheckbox: !!(t.matches && t.matches('input[type="checkbox"]')),
            hasSelection: !!sel && !sel.isCollapsed,
            dx: ev.clientX - taskPointerDown.x,
            dy: ev.clientY - taskPointerDown.y
        });
        if (suppress) ev.preventDefault();
    }, true);
    document.addEventListener("auxclick", (ev) => {
        if (ev.button === 1) interceptLinkClick(ev, true);   // middle-click
    }, true);

    // Tell Swift we're ready to receive render() calls
    post("ready");
})();
