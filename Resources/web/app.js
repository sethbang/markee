// Markee renderer — runs inside WKWebView.
// Receives source from Swift via window.markee.render({source, fileName, docBase}).
// Posts outline + errors back via webkit.messageHandlers.markee.

(function () {
    "use strict";

    const post = (kind, payload = {}) => {
        try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.markee) {
                window.webkit.messageHandlers.markee.postMessage(Object.assign({ kind }, payload));
            }
        } catch (_) { /* ignore */ }
    };

    const showToast = (msg) => {
        const t = document.getElementById("toast");
        if (!t) return;
        t.textContent = msg;
        t.hidden = false;
        clearTimeout(showToast._t);
        showToast._t = setTimeout(() => { t.hidden = true; }, 4500);
    };

    // ---- markdown-it setup -------------------------------------------------
    let md = null;
    function buildRenderer() {
        if (typeof markdownit === "undefined") {
            return null;
        }
        const m = markdownit({
            html: true,
            linkify: true,
            typographer: true,
            breaks: false,
            highlight: function (str, lang) {
                if (lang === "mermaid") {
                    return `<pre class="mermaid">${escapeHtml(str)}</pre>`;
                }
                if (lang && window.hljs && window.hljs.getLanguage(lang)) {
                    try {
                        return '<pre class="hljs"><code class="language-' + lang + '">' +
                            window.hljs.highlight(str, { language: lang, ignoreIllegals: true }).value +
                            "</code></pre>";
                    } catch (_) { /* fall through */ }
                }
                if (window.hljs) {
                    try {
                        return '<pre class="hljs"><code>' + window.hljs.highlightAuto(str).value + "</code></pre>";
                    } catch (_) { /* fall through */ }
                }
                return '<pre class="hljs"><code>' + escapeHtml(str) + "</code></pre>";
            }
        });
        const plugin = (names, ...args) => {
            for (const n of names) {
                if (window[n]) { try { m.use(window[n], ...args); } catch (_) {} return; }
            }
        };
        plugin(["markdownitFootnote", "markdownItFootnote"]);
        plugin(["markdownitDeflist", "markdownItDeflist"]);
        plugin(["markdownItAttrs", "markdownitAttrs"]);
        plugin(["markdownitTaskLists", "markdownItTaskLists"], { enabled: true, label: true });
        return m;
    }

    function escapeHtml(s) {
        return String(s)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#39;");
    }

    // ---- slugify -----------------------------------------------------------
    const slugCount = new Map();
    function slugify(text) {
        const base = String(text)
            .toLowerCase()
            .replace(/[^\w\s-]/g, "")
            .trim()
            .replace(/\s+/g, "-");
        let slug = base || "section";
        let n = slugCount.get(slug) || 0;
        if (n > 0) slug = `${slug}-${n}`;
        slugCount.set(base || "section", n + 1);
        return slug;
    }

    // ---- task list mapping --------------------------------------------------
    // Scan raw source for task-list lines, skipping YAML front-matter and
    // fenced code blocks. Returns 0-based line indices.
    function collectTaskLineNumbers(source) {
        const result = [];
        const lines = source.replace(/^﻿/, "").split("\n");
        let i = 0;

        // Skip YAML front matter
        if (lines[0] === "---") {
            for (let j = 1; j < lines.length; j++) {
                if (lines[j] === "---" || lines[j] === "...") { i = j + 1; break; }
            }
        }

        let fence = null; // "`" or "~" when inside a fenced block
        for (; i < lines.length; i++) {
            const stripped = lines[i].replace(/\r$/, "");
            const fenceOpen = stripped.match(/^\s{0,3}(```+|~~~+)/);
            if (fenceOpen) {
                const marker = fenceOpen[1][0];
                if (fence === null) { fence = marker; continue; }
                if (fence === marker) { fence = null; continue; }
                continue;
            }
            if (fence !== null) continue;
            if (/^\s*(?:[-+*]|\d+\.)\s+\[[ xX]\](?:\s|$)/.test(stripped)) {
                result.push(i);
            }
        }
        return result;
    }

    function onTaskToggle(ev) {
        const cb = ev.currentTarget;
        const li = cb.closest("li.task-list-item");
        if (!li || !li.dataset.line) return;
        const line = parseInt(li.dataset.line, 10);
        if (Number.isNaN(line)) return;
        post("taskToggle", { line, checked: !!cb.checked });
    }

    // ---- render -------------------------------------------------------------
    function render(payload) {
        const article = document.getElementById("content");
        if (!article) return;
        if (!md) md = buildRenderer();
        if (!md) {
            showToast("Renderer not loaded. Run 'make fetch-vendor' to install vendored libs.");
            article.innerHTML = `<pre style="white-space:pre-wrap">${escapeHtml(payload.source || "")}</pre>`;
            post("outline", { items: [] });
            return;
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

        // Reset slug counter per render
        slugCount.clear();

        let html;
        try {
            // Strip YAML front matter (`---\n...\n---\n`) before rendering
            let src = String(payload.source || "");
            src = src.replace(/^﻿/, "");
            src = src.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, "");
            html = md.render(src);
        } catch (err) {
            const msg = "Markdown render error: " + (err && err.message ? err.message : String(err));
            post("error", { message: msg });
            showToast(msg);
            return;
        }

        article.innerHTML = html;

        // Assign ids to headings + build outline
        const items = [];
        article.querySelectorAll("h1, h2, h3, h4, h5, h6").forEach((h) => {
            const level = parseInt(h.tagName.substring(1), 10);
            const title = h.textContent || "";
            const id = h.id || slugify(title);
            h.id = id;
            items.push({ id, level, title });
        });
        post("outline", { items });

        // Tag task-list items with their source line, attach click handler.
        // Source-line indices are computed against the ORIGINAL source so they
        // match what's on disk (Swift reads the file fresh before toggling).
        const taskLines = collectTaskLineNumbers(String(payload.source || ""));
        const taskItems = article.querySelectorAll("li.task-list-item");
        taskItems.forEach((li, i) => {
            if (i >= taskLines.length) return;
            li.dataset.line = String(taskLines[i]);
            const cb = li.querySelector('input[type="checkbox"]');
            if (cb) {
                cb.disabled = false;
                cb.addEventListener("click", onTaskToggle);
            }
        });

        // KaTeX
        if (window.renderMathInElement) {
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
            } catch (e) { /* non-fatal */ }
        }

        // Mermaid
        if (window.mermaid) {
            try {
                // Reset processed flag on existing diagrams so re-render works
                article.querySelectorAll("pre.mermaid").forEach((el) => {
                    el.removeAttribute("data-processed");
                });
                window.mermaid.run({ querySelector: "#content pre.mermaid" }).catch(() => {});
            } catch (e) { /* non-fatal */ }
        }

        // Restore scroll
        const newHeight = document.documentElement.scrollHeight;
        const ratio = prevHeight > 0 ? prevScroll / prevHeight : 0;
        const targetY = Math.min(prevScroll, Math.max(0, newHeight - window.innerHeight));
        // If layout changed substantially, fall back to proportional scroll
        if (Math.abs(newHeight - prevHeight) / Math.max(prevHeight, 1) > 0.5) {
            window.scrollTo(0, ratio * newHeight);
        } else {
            window.scrollTo(0, targetY);
        }
    }

    function scrollToHeading(id) {
        const el = document.getElementById(id);
        if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    // ---- export standalone HTML --------------------------------------------
    async function exportStandalone() {
        const article = document.getElementById("content");
        if (!article) return "";
        const clone = article.cloneNode(true);

        // Inline images as data URIs
        const imgs = Array.from(clone.querySelectorAll("img"));
        await Promise.all(imgs.map(async (img) => {
            const src = img.getAttribute("src");
            if (!src) return;
            try {
                const resp = await fetch(src);
                const blob = await resp.blob();
                const dataUrl = await new Promise((resolve, reject) => {
                    const r = new FileReader();
                    r.onerror = reject;
                    r.onload = () => resolve(r.result);
                    r.readAsDataURL(blob);
                });
                img.setAttribute("src", dataUrl);
            } catch (_) { /* leave src as-is */ }
        }));

        // Gather stylesheets
        const sheets = Array.from(document.querySelectorAll('link[rel="stylesheet"], style'));
        const cssParts = [];
        for (const s of sheets) {
            if (s.tagName === "STYLE") { cssParts.push(s.textContent); continue; }
            const href = s.getAttribute("href"); if (!href) continue;
            try {
                const r = await fetch(href);
                cssParts.push(await r.text());
            } catch (_) { /* skip */ }
        }

        // Build standalone HTML
        const head = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(document.title || "Markee export")}</title>
<style>
${cssParts.join("\n\n")}
</style>
</head>
<body>
`;
        const foot = "\n</body>\n</html>\n";
        return head + clone.outerHTML + foot;
    }

    // ---- expose API ---------------------------------------------------------
    window.markee = {
        render,
        scrollToHeading,
        exportStandalone
    };

    // Mermaid is loaded as a module; the inline initializer (or load failure)
    // dispatches markee:mermaid-ready. Trigger an outline-only refresh if
    // mermaid finishes after the first render.
    window.addEventListener("markee:mermaid-ready", () => {
        if (window.mermaid && typeof window.mermaid.initialize === "function") {
            try {
                window.mermaid.initialize({
                    startOnLoad: false,
                    theme: matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "default"
                });
            } catch (_) { /* ignore */ }
        }
    });

    // Tell Swift we're ready to receive render() calls
    post("ready");
})();
