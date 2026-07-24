// reflow.js — collapse soft-wrapped newlines *inside* paragraph blocks to single
// spaces, leaving every non-paragraph line (headings, code, tables, list
// structure, blank lines, front matter) byte-for-byte intact. UMD:
// window.markeeReflow in the browser, module.exports in Node (Tests/reflow.test.js).
//
// reflow(source, md): `md` is a configured markdown-it instance (the same one the
// renderer uses), dependency-injected so reflow sees the identical block grammar
// the user sees rendered. It is only PARSED (md.parse) — never rendered.

(function (root, factory) {
    if (typeof module !== "undefined" && module.exports) {
        module.exports = factory();
    } else {
        root.markeeReflow = factory();
    }
})(typeof self !== "undefined" ? self : (typeof globalThis !== "undefined" ? globalThis : this), function () {
    "use strict";

    const FRONT_MATTER = /^---\r?\n[\s\S]*?\r?\n---\r?\n/;
    // An explicit hard break (two+ trailing spaces or trailing backslash before a
    // newline) is author-intended; such a paragraph is left verbatim.
    const HARD_BREAK = /( {2,}\n)|(\\\n)/;

    // Turn a blockquote/list continuation line into bare content: strip leading
    // whitespace, then `>`+optional-space × depth, then any remaining whitespace.
    function stripContinuation(line, bqDepth) {
        let s = line.replace(/^\s+/, "");
        for (let d = 0; d < bqDepth; d++) s = s.replace(/^>\s?/, "");
        return s.replace(/^\s+/, "");
    }

    function reflow(source, md) {
        const src = String(source == null ? "" : source);
        if (!md || typeof md.parse !== "function") return src;

        const bom = src.charCodeAt(0) === 0xFEFF ? "\\uFEFF" : "";
        let rest = bom ? src.slice(1) : src;

        let frontMatter = "";
        const fm = rest.match(FRONT_MATTER);
        if (fm) { frontMatter = fm[0]; rest = rest.slice(fm[0].length); }

        const lines = rest.split(/\r\n|\r|\n/);
        let tokens;
        try { tokens = md.parse(rest, {}); }
        catch (_) { return src; }  // never mangle on parser failure

        // start-line -> { end, merged } for each reflowable paragraph span.
        const spans = {};
        let bqDepth = 0;
        for (let i = 0; i < tokens.length; i++) {
            const t = tokens[i];
            if (t.type === "blockquote_open") { bqDepth++; continue; }
            if (t.type === "blockquote_close") { bqDepth--; continue; }
            if (t.type !== "paragraph_open" || !t.map) continue;
            const inline = tokens[i + 1];
            const content = inline && inline.type === "inline" ? inline.content : "";
            if (HARD_BREAK.test(content)) continue;   // verbatim
            const s = t.map[0], e = t.map[1];
            if (e - s <= 1) continue;                 // single line: nothing to merge
            let merged = lines[s];                    // first line verbatim (keeps marker/>/indent)
            for (let j = s + 1; j < e; j++) {
                merged = merged.replace(/\s+$/, "") + " " + stripContinuation(lines[j], bqDepth);
            }
            spans[s] = { end: e, merged: merged };
        }

        const out = [];
        for (let i = 0; i < lines.length; ) {
            if (spans[i]) { out.push(spans[i].merged); i = spans[i].end; }
            else { out.push(lines[i]); i++; }
        }
        return bom + frontMatter + out.join("\n");
    }

    return { reflow: reflow };
});
