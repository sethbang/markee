// render-core.js — the markdown-it pipeline, shared by the in-browser renderer
// (app.js) and Node snapshot tests. UMD: exposes window.markeeRenderCore in the
// browser, module.exports in Node. Construction-only: heading ids and DOM
// post-passes stay in app.js; source-line stamping happens here.

(function (root, factory) {
    if (typeof module !== "undefined" && module.exports) {
        module.exports = factory();
    } else {
        root.markeeRenderCore = factory();
    }
})(typeof self !== "undefined" ? self : (typeof globalThis !== "undefined" ? globalThis : this), function () {
    "use strict";

    function escapeHtml(s) {
        return String(s)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#39;");
    }

    // YAML front matter: an opening `---` line through a closing `---` or `...`
    // line. CRLF-tolerant; the closer may end the file. The single definition
    // shared by rendering, task/heading line numbers and reflow — they must
    // agree on where the body starts or task write-back targets the wrong line.
    const FRONT_MATTER = /^---[ \t]*\r?\n(?:[\s\S]*?\r?\n)?(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/;

    // Split `source` into a leading BOM, the verbatim front-matter block, and the
    // body. `lineCount` is the number of source lines before the body, so body
    // line N is source line N + lineCount.
    function splitFrontMatter(source) {
        let src = String(source == null ? "" : source);
        const bom = src.charCodeAt(0) === 0xFEFF ? "\uFEFF" : "";
        if (bom) src = src.slice(1);
        const m = src.match(FRONT_MATTER);
        const frontMatter = m ? m[0] : "";
        return {
            bom: bom,
            frontMatter: frontMatter,
            body: src.slice(frontMatter.length),
            lineCount: (frontMatter.match(/\n/g) || []).length
        };
    }

    function stripFrontMatter(source) {
        const parts = splitFrontMatter(source);
        return { body: parts.body, lineCount: parts.lineCount };
    }

    const RANGE_TOKENS = new Set([
        "paragraph_open", "heading_open", "list_item_open", "bullet_list_open", "ordered_list_open", "blockquote_open", "table_open",
        "hr", "dl_open", "dt_open", "dd_open"
    ]);

    const VOID_ELEMENTS = new Set([
        "area", "base", "br", "col", "embed", "frame", "hr", "img", "input", "keygen", "link", "meta", "param",
        "source", "track", "wbr"
    ]);
    const HTML_TOKEN = /<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<![^>]*>|<(\/?)([A-Za-z][A-Za-z0-9:-]*)((?:"[^"]*"|'[^']*'|[^<>"'])*)>/g;

    const MAX_HTML_BLOCK = 100000;

    // Calls visit(tag, closing, isVoid) for each tag in `html`, lower-cased;
    // stops early when visit returns false (and then returns false). A
    // trailing `/` only self-closes void elements and svg/math content; on any
    // other tag HTML parsers ignore it, so `<div/>` is an open tag.
    function scanTags(html, visit) {
        const re = new RegExp(HTML_TOKEN.source, "g");
        let m;
        let foreign = 0;
        while ((m = re.exec(html)) !== null) {
            if (!m[2]) continue;
            const tag = m[2].toLowerCase();
            const closing = !!m[1];
            const slash = /\/\s*$/.test(m[3]);
            const root = tag === "svg" || tag === "math";
            const isVoid = !closing && (VOID_ELEMENTS.has(tag) || (slash && (root || foreign > 0)));
            if (root) foreign = closing ? Math.max(0, foreign - 1) : (isVoid ? foreign : foreign + 1);
            if (visit(tag, closing, isVoid) === false) return false;
        }
        return true;
    }

    // True when every tag in `html` closes inside it and something visible is
    // targetable, so a wrapper around the block never splits a construct.
    function isSelfContainedHtml(html) {
        html = String(html);
        if (html.length > MAX_HTML_BLOCK) return false;
        const stack = [];
        let tags = 0;
        const balanced = scanTags(html, function (tag, closing, isVoid) {
            tags++;
            if (closing) return stack.pop() === tag;
            if (!isVoid) stack.push(tag);
        });
        return balanced && tags > 0 && stack.length === 0;
    }

    function isBlankAtDepth(line, depth) {
        for (let i = 0; i < depth; i++) line = line.replace(/^[ \t]*>[ \t]?/, "");
        return line.trim() === "";
    }

    function trackOpenTags(openTags, html, level) {
        scanTags(html, function (tag, closing, isVoid) {
            if (closing) {
                for (let i = openTags.length - 1; i >= 0; i--) {
                    if (openTags[i].tag === tag) { openTags.length = i; break; }
                }
            } else if (!isVoid) {
                openTags.push({ tag: tag, level: level });
            }
        });
    }

    // A rendered block's stamp attributes. `env.stampKey` (a per-render random
    // value from app.js) marks the stamps render-core emitted; app.js drops
    // data-line / data-line-end from anything without it, so raw HTML can't
    // forge a source range. No key (Node tests): no marker.
    function stampAttrs(t, env) {
        const offset = (env && env.lineOffset) || 0;
        const key = env && env.stampKey;
        return ' data-line="' + (t.map[0] + offset) + '" data-line-end="' + (t.map[1] + offset) + '"' +
            (key ? ' data-markee-stamp="' + escapeHtml(key) + '"' : "");
    }

    // Stamp `data-line` / `data-line-end` (0-based, end exclusive, in the ORIGINAL
    // file: env.lineOffset is the front-matter line count) onto each visible
    // RANGE_TOKENS block, the <pre> of fenced/indented code, and wrapped raw HTML,
    // straight from the parser's token maps. Inside footnotes only task items and
    // headings are stamped. Positional pairing of a hand-rolled
    // line scan with the DOM drifted on blockquotes, fences in list items, HTML
    // blocks and front matter, so a checkbox click could rewrite the wrong line.
    function sourceLinePlugin(md) {
        md.core.ruler.push("markee_source_lines", function (state) {
            const offset = (state.env && state.env.lineOffset) || 0;
            const key = state.env && state.env.stampKey;
            const lines = state.src.split("\n");
            let inFootnote = false;
            // Tags left open by earlier partial html_blocks, across the whole
            // document. A wrapper <div> inside one (<p>, <details>, <table>,
            // <ul>) would close or restructure it, so nothing wraps until the
            // context closes. Optional end tags make this overstate: safe.
            // Levels never decrease bottom to top, so popping from the top suffices.
            const openTags = [];
            let unknown = false;
            let quoteDepth = 0;
            for (const t of state.tokens) {
                if (t.nesting === -1) {
                    while (openTags.length && openTags[openTags.length - 1].level > t.level) openTags.pop();
                }
                if (t.type === "html_block") {
                    const contained = !unknown && isSelfContainedHtml(t.content);
                    t.meta = { wrap: contained && !inFootnote && !!t.map && openTags.length === 0 };
                    if (!contained && t.content.length > MAX_HTML_BLOCK) unknown = true;
                    else if (!contained) trackOpenTags(openTags, t.content, t.level);
                }
                if (t.type === "footnote_open") inFootnote = true;
                else if (t.type === "footnote_close") inFootnote = false;
                else if (t.type === "blockquote_open") quoteDepth++;
                else if (t.type === "blockquote_close") quoteDepth--;
                if (!t.map || t.hidden || !RANGE_TOKENS.has(t.type)) continue;
                // Task items and headings keep their stamp inside footnotes so
                // checkbox write-back and the outline behave as before.
                const isTask = t.type === "list_item_open" && /\btask-list-item\b/.test(t.attrGet("class") || "");
                if (inFootnote && !isTask && t.type !== "heading_open") continue;
                // markdown-it-deflist gives <dt> an empty map [n, n].
                let end = Math.max(t.map[1], t.map[0] + 1);
                // A list's (and a loose item's) map swallows the blank lines
                // before the next block; inside a blockquote those read ">".
                // Only the list's own quote markers make a line blank: a
                // trailing ">" of a quote nested in the item is content.
                if (t.type === "bullet_list_open" || t.type === "ordered_list_open" || t.type === "list_item_open") {
                    while (end - t.map[0] > 1 && isBlankAtDepth(lines[end - 1] || "", quoteDepth)) end--;
                }
                t.attrSet("data-line", String(t.map[0] + offset));
                t.attrSet("data-line-end", String(end + offset));
                if (key) t.attrSet("data-markee-stamp", key);
            }
        });
        const innerHtmlBlock = md.renderer.rules.html_block || function (tokens, idx) { return tokens[idx].content; };
        md.renderer.rules.html_block = function (tokens, idx, options, env, slf) {
            const html = innerHtmlBlock(tokens, idx, options, env, slf);
            const t = tokens[idx];
            if (!t.meta || !t.meta.wrap) return html;
            return '<div class="markee-html-block"' + stampAttrs(t, env) + ">" + html + "</div>";
        };
        // The default fence/code_block rules drop token attrs when highlight returns
        // a `<pre`, or put them on <code>; inject on the outer <pre> instead.
        ["fence", "code_block"].forEach(function (rule) {
            const inner = md.renderer.rules[rule];
            md.renderer.rules[rule] = function (tokens, idx, options, env, slf) {
                const html = inner(tokens, idx, options, env, slf);
                const t = tokens[idx];
                if (!t.map || html.indexOf("<pre") !== 0) return html;
                return "<pre" + stampAttrs(t, env) + html.slice(4);
            };
        });
    }

    // Local slug for [[Note#Heading]] fragments. Mirrors util.js slugify's base
    // branch; kept inline so render-core stays Node-requirable without util.js.
    function wikiSlug(s) {
        return String(s).toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, "").trim().replace(/\s+/g, "-") || "section";
    }

    // markdown-it inline rule for [[target]], [[target#heading]], [[target|alias]].
    // Resolves `target` (case-insensitive) against state.env.wikiIndex
    // (a {stem → markee-doc:// url} map). Unresolved links render as a
    // non-navigating broken span. With no index (Quick Look) everything is broken.
    function wikiLinkPlugin(md) {
        md.inline.ruler.before("link", "wikilink", function (state, silent) {
            const src = state.src, start = state.pos;
            if (src.charCodeAt(start) !== 0x5B || src.charCodeAt(start + 1) !== 0x5B) return false;
            const end = src.indexOf("]]", start + 2);
            if (end < 0) return false;
            const inner = src.slice(start + 2, end);
            if (inner.indexOf("[") >= 0 || inner.indexOf("]") >= 0) return false;
            if (!silent) {
                let rawTarget = inner, alias = null;
                const pipe = inner.indexOf("|");
                if (pipe >= 0) { alias = inner.slice(pipe + 1).trim(); rawTarget = inner.slice(0, pipe); }
                let target = rawTarget, heading = null;
                const hash = rawTarget.indexOf("#");
                if (hash >= 0) { heading = rawTarget.slice(hash + 1).trim(); target = rawTarget.slice(0, hash); }
                target = target.trim();
                const label = alias || rawTarget.trim() || inner;

                const index = (state.env && state.env.wikiIndex) || {};
                // Own keys only: `[[constructor]]` must not resolve to Object.prototype.
                const key = target.toLowerCase();
                const href = target && Object.prototype.hasOwnProperty.call(index, key)
                    && typeof index[key] === "string" ? index[key] : null;
                if (href) {
                    const full = heading ? href + "#" + wikiSlug(heading) : href;
                    const open = state.push("link_open", "a", 1);
                    open.attrSet("href", full);
                    open.attrSet("class", "markee-wikilink");
                    state.push("text", "", 0).content = label;
                    state.push("link_close", "a", -1);
                } else {
                    const open = state.push("wikilink_broken_open", "span", 1);
                    open.attrSet("class", "markee-wikilink-broken");
                    open.attrSet("title", "Unresolved link: " + inner);
                    state.push("text", "", 0).content = label;
                    state.push("wikilink_broken_close", "span", -1);
                }
            }
            state.pos = end + 2;
            return true;
        });
        md.renderer.rules.wikilink_broken_open = function (t, i, o, e, self) { return self.renderToken(t, i, o); };
        md.renderer.rules.wikilink_broken_close = function (t, i, o, e, self) { return self.renderToken(t, i, o); };
    }

    // GFM-style autolinks. linkify-it's "fuzzy" mode links any bare domain —
    // including file names, since .md (Moldova) and .py are real TLDs, so
    // "see notes.md" became a link to http://notes.md. Fuzzy matching stays on
    // (v6 turned it off, which also dropped www.example.com), and this rule
    // demotes every fuzzy match that isn't www.-prefixed back to plain text.
    // Scheme-qualified URLs and email addresses are untouched.
    function gfmAutolinkPlugin(md) {
        if (md.linkify && typeof md.linkify.set === "function") md.linkify.set({ fuzzyLink: true });
        const KEEP = /^(?:[a-z][a-z0-9+.-]*:|www\.)/i;
        md.core.ruler.push("markee_gfm_autolinks", function (state) {
            for (const block of state.tokens) {
                if (block.type !== "inline" || !block.children) continue;
                const out = [];
                const kids = block.children;
                for (let i = 0; i < kids.length; i++) {
                    const t = kids[i];
                    const text = kids[i + 1], close = kids[i + 2];
                    if (t.type === "link_open" && t.markup === "linkify" && text && text.type === "text"
                        && close && close.type === "link_close" && !KEEP.test(text.content)
                        && !/^mailto:/i.test(t.attrGet("href") || "")) {
                        out.push(text);
                        i += 2;
                        continue;
                    }
                    out.push(t);
                }
                block.children = out;
            }
        });
    }

    // Build a configured markdown-it instance. `deps.markdownit` is required;
    // `deps.hljs` enables syntax highlighting (omitted in Node → escaped code).
    // Plugin deps are optional and skipped when absent.
    function createRenderer(deps) {
        deps = deps || {};
        const markdownit = deps.markdownit;
        const hljs = deps.hljs;
        if (typeof markdownit !== "function") return null;

        const m = markdownit({
            html: true,
            linkify: true,
            typographer: true,
            breaks: false,
            highlight: function (str, lang) {
                if (lang === "mermaid") {
                    return '<pre class="mermaid">' + escapeHtml(str) + "</pre>";
                }
                if (lang && hljs && hljs.getLanguage(lang)) {
                    try {
                        return '<pre class="hljs"><code class="language-' + lang + '">' +
                            hljs.highlight(str, { language: lang, ignoreIllegals: true }).value +
                            "</code></pre>";
                    } catch (_) { /* fall through */ }
                }
                if (hljs) {
                    try {
                        return '<pre class="hljs"><code>' + hljs.highlightAuto(str).value + "</code></pre>";
                    } catch (_) { /* fall through */ }
                }
                return '<pre class="hljs"><code>' + escapeHtml(str) + "</code></pre>";
            }
        });

        const use = (plugin, opts) => {
            if (plugin) { try { m.use(plugin, opts); } catch (_) { /* ignore */ } }
        };
        use(deps.footnote);
        use(deps.deflist);
        // Allowlist: unrestricted, `{onmouseover="…"}` emits event-handler
        // attributes — script injection independent of `html: true`. The
        // source-range stamps are render-core's alone.
        use(deps.attrs, { allowedAttributes: ["id", "class", /^data-(?!line$|line-end$|markee-stamp$)/, "width", "height", "lang", "title", "dir"] });
        use(deps.taskLists, { enabled: true, label: true });
        m.use(gfmAutolinkPlugin);
        m.use(wikiLinkPlugin);
        m.use(sourceLinePlugin);
        return m;
    }

    return {
        createRenderer: createRenderer,
        escapeHtml: escapeHtml,
        isSelfContainedHtml: isSelfContainedHtml,
        splitFrontMatter: splitFrontMatter,
        stripFrontMatter: stripFrontMatter
    };
});
