// render-core.js — the markdown-it pipeline, shared by the in-browser renderer
// (app.js) and Node snapshot tests. UMD: exposes window.markeeRenderCore in the
// browser, module.exports in Node. Construction-only: heading ids, task-line
// mapping, and DOM post-passes stay in app.js.

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

    // Strip a leading BOM and YAML front matter (`---\n…\n---\n`). Returns the
    // body plus the number of newlines removed, so callers can keep source-line
    // numbers accurate against the on-disk file.
    function stripFrontMatter(source) {
        let src = String(source || "").replace(/^﻿/, "");
        let lineCount = 0;
        const m = src.match(/^---\r?\n[\s\S]*?\r?\n---\r?\n/);
        if (m) {
            lineCount = (m[0].match(/\n/g) || []).length;
            src = src.slice(m[0].length);
        }
        return { body: src, lineCount: lineCount };
    }

    // Local slug for [[Note#Heading]] fragments. Mirrors util.js slugify's base
    // branch; kept inline so render-core stays Node-requirable without util.js.
    function wikiSlug(s) {
        return String(s).toLowerCase().replace(/[^\w\s-]/g, "").trim().replace(/\s+/g, "-") || "section";
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
                const href = target ? index[target.toLowerCase()] : null;
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
        use(deps.attrs);
        use(deps.taskLists, { enabled: true, label: true });
        m.use(wikiLinkPlugin);
        return m;
    }

    return { createRenderer: createRenderer, escapeHtml: escapeHtml, stripFrontMatter: stripFrontMatter };
});
