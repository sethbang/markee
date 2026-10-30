// Pure helpers behind Quick Edit: greying Markdown syntax, mapping a rendered
// selection back to source offsets, and per-block labels. No DOM.
// UMD-ish: exposes `window.markeeQuickEditCore` in the browser, `module.exports` in Node.

(function (root, factory) {
    if (typeof module !== "undefined" && module.exports) {
        module.exports = factory();
    } else {
        root.markeeQuickEditCore = factory();
    }
})(typeof self !== "undefined" ? self : (typeof globalThis !== "undefined" ? globalThis : this), function () {
    "use strict";

    const QUOTE_PREFIX = /^ {0,3}((?:> ?)+)/;
    const HEADING = /^ {0,3}(#{1,6}(?: +|$))/;
    const LIST_MARKER = /^\s*((?:[-*+]|\d{1,9}[.)])(?: +|$))/;
    const TASK = /^(\[[ xX]\])(?= |$)/;
    const TABLE_DELIMITER = /^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)*\|?\s*$/;
    const REF_DEFINITION = /^ {0,3}\[[^\]^][^\]]*\]:/;
    const AUTOLINK = /<(?:[A-Za-z][A-Za-z0-9+.-]{1,31}:[^\s<>]*|[^\s<>@]+@[^\s<>@]+)>/y;
    const REF_LABEL = /\[[^\][\n]*\]/y;

    // Caps each tail scan so a line of "](" can't make greying quadratic.
    const MAX_TAIL = 2000;

    // Length of an inline-link tail "(dest "title")" starting at line[i] === "(",
    // allowing balanced parentheses in the destination; 0 when it isn't one.
    function inlineTailLength(line, i) {
        let j = i + 1;
        let depth = 0;
        const limit = Math.min(line.length, i + MAX_TAIL);
        while (j < limit && !/\s/.test(line[j])) {
            if (line[j] === "(") depth++;
            else if (line[j] === ")") {
                if (depth === 0) return j + 1 - i;
                depth--;
            }
            j++;
        }
        if (depth !== 0 || j >= limit) return 0;
        const t = /\s+"[^"]*"\)/y;
        t.lastIndex = j;
        const m = t.exec(line);
        return m ? j + m[0].length - i : 0;
    }

    function lineSyntaxIds(line) {
        const ids = new Array(line.length).fill(0);
        let next = 1;
        const mark = (from, to) => {
            const id = next++;
            for (let i = from; i < to; i++) ids[i] = id;
        };

        let pos = 0;
        let m = QUOTE_PREFIX.exec(line);
        if (m) {
            mark(m.index + m[0].length - m[1].length, m[0].length);
            pos = m[0].length;
        }

        const rest = line.slice(pos);
        if (REF_DEFINITION.test(rest)) {
            mark(pos, line.length);
            return ids;
        }
        if (/^\s*\|/.test(rest)) {
            if (TABLE_DELIMITER.test(rest) && rest.includes("|")) {
                const lead = rest.length - rest.trimStart().length;
                mark(pos + lead, pos + rest.trimEnd().length);
                return ids;
            }
            for (let i = pos; i < line.length; i++) {
                if (line[i] === "|" && line[i - 1] !== "\\") mark(i, i + 1);
            }
        } else if ((m = HEADING.exec(rest))) {
            mark(pos + m.index + m[0].length - m[1].length, pos + m[0].length);
            pos += m[0].length;
        } else if ((m = LIST_MARKER.exec(rest))) {
            const start = pos + m[0].length - m[1].length;
            mark(start, pos + m[0].length);
            pos += m[0].length;
            const t = TASK.exec(line.slice(pos));
            if (t) {
                mark(pos, pos + t[1].length);
                pos += t[1].length;
            }
        }

        // `scannable[i]` is false for code content, link URLs and already-marked chars.
        const scannable = ids.map((id, i) => id === 0 && i >= pos);
        const lock = (from, to) => { for (let i = from; i < to; i++) scannable[i] = false; };

        for (let i = pos; i < line.length; i++) {
            if (line[i] === "\\") { scannable[i] = false; if (i + 1 < line.length) scannable[i + 1] = false; i++; }
        }

        for (let i = pos; i < line.length;) {
            if (line[i] !== "`" || !scannable[i]) { i++; continue; }
            let n = 1;
            while (line[i + n] === "`") n++;
            let j = i + n;
            let close = -1;
            while (j < line.length) {
                if (line[j] !== "`") { j++; continue; }
                let k = 1;
                while (line[j + k] === "`") k++;
                if (k === n) { close = j; break; }
                j += k;
            }
            if (close < 0) { i += n; continue; }
            mark(i, i + n);
            mark(close, close + n);
            lock(i, close + n);
            i = close + n;
        }

        for (let i = pos; i < line.length; i++) {
            if (line[i] !== "<" || !scannable[i]) continue;
            AUTOLINK.lastIndex = i;
            const a = AUTOLINK.exec(line);
            if (!a) continue;
            const end = i + a[0].length;
            mark(i, i + 1);
            mark(end - 1, end);
            lock(i, end);
            i = end - 1;
        }

        const brackets = [];
        for (let i = pos; i < line.length; i++) {
            if (!scannable[i]) continue;
            if (line[i] === "[") {
                const image = i > pos && line[i - 1] === "!" && scannable[i - 1];
                brackets.push(image ? i - 1 : i);
            } else if (line[i] === "]" && brackets.length) {
                const openAt = brackets.pop();
                let tailEnd = 0;
                if (line[i + 1] === "(") {
                    const n = inlineTailLength(line, i + 1);
                    if (n && scannable[i + 1]) tailEnd = i + 1 + n;
                } else if (line[i + 1] === "[") {
                    REF_LABEL.lastIndex = i + 1;
                    const r = REF_LABEL.exec(line);
                    if (r) tailEnd = i + 1 + r[0].length;
                }
                if (!tailEnd) continue;
                const textStart = line[openAt] === "!" ? openAt + 2 : openAt + 1;
                mark(openAt, textStart);
                mark(i, tailEnd);
                lock(openAt, textStart);
                lock(i, tailEnd);
                i = tailEnd - 1;
            }
        }

        const open = { "*": [], "_": [] };
        for (let i = pos; i < line.length;) {
            const c = line[i];
            if ((c !== "*" && c !== "_") || !scannable[i]) { i++; continue; }
            let n = 1;
            while (line[i + n] === c && scannable[i + n]) n++;
            const before = i > 0 ? line[i - 1] : " ";
            const after = i + n < line.length ? line[i + n] : " ";
            const alnumBefore = /[\p{L}\p{N}]/u.test(before);
            const alnumAfter = /[\p{L}\p{N}]/u.test(after);
            const canOpen = !/\s/.test(after) && !(c === "_" && alnumBefore);
            const canClose = !/\s/.test(before) && !(c === "_" && alnumAfter);
            const stack = open[c];
            const matchAt = canClose ? stack.findLastIndex(o => o.n === n) : -1;
            if (matchAt >= 0) {
                const o = stack[matchAt];
                mark(o.i, o.i + n);
                mark(i, i + n);
                stack.length = matchAt;
            } else if (canOpen) {
                stack.push({ i, n });
            }
            i += n;
        }
        return ids;
    }

    function syntaxSpans(source, mode) {
        source = String(source);
        if (mode === "code") return [{ text: source, syntax: false }];
        const spans = [];
        const push = (text, syntax) => {
            if (!text) return;
            const last = spans[spans.length - 1];
            if (last && !last.syntax && !syntax) last.text += text;
            else spans.push({ text, syntax });
        };
        const lines = source.split("\n");
        lines.forEach((raw, n) => {
            const cr = raw.endsWith("\r") ? "\r" : "";
            const line = cr ? raw.slice(0, -1) : raw;
            const ids = lineSyntaxIds(line);
            let from = 0;
            for (let i = 1; i <= line.length; i++) {
                if (i === line.length || ids[i] !== ids[from]) {
                    push(line.slice(from, i), ids[from] !== 0);
                    from = i;
                }
            }
            push(cr + (n < lines.length - 1 ? "\n" : ""), false);
        });
        return spans;
    }

    // Anything that can sit between two rendered characters in the source.
    // Capped at 6 per gap to bound backtracking on pathological delimiter runs.
    const INLINE_JUNK = "(?:\\]\\([^)\\s]*\\)|[*_`\\[\\]]){0,6}";

    // The pattern is ~55 chars per input char; past this the regex can exceed engine limits.
    const MAX_SELECTION = 2000;

    function escapeChar(ch) {
        return /[\\^$.*+?()[\]{}|\/]/.test(ch) ? "\\" + ch : ch;
    }

    // Returns the unique source range whose rendered text is `selected`; null
    // whenever that is not certain, so a wrong range is never reported.
    function mapSelection(source, selected) {
        source = String(source);
        const text = String(selected).trim();
        if (!text || text.length > MAX_SELECTION) return null;
        const tokens = [];
        for (let i = 0; i < text.length; i++) {
            if (/\s/.test(text[i])) {
                while (i + 1 < text.length && /\s/.test(text[i + 1])) i++;
                tokens.push("\\s+");
            } else {
                tokens.push(escapeChar(text[i]));
            }
        }
        try {
            const re = new RegExp(tokens.join(INLINE_JUNK), "g");
            let found = null;
            let m;
            while ((m = re.exec(source)) !== null) {
                if (found) return null;
                found = { start: m.index, end: m.index + m[0].length };
                // Overlapping matches count as ambiguous too.
                re.lastIndex = m.index + 1;
            }
            return found;
        } catch (e) {
            return null;
        }
    }

    function blockInfo(tagName, classList) {
        const tag = String(tagName).toUpperCase();
        const classes = Array.from(classList || []);
        if (tag === "P") return { mode: "prose", label: "Edit Paragraph" };
        if (/^H[1-6]$/.test(tag)) return { mode: "prose", label: "Edit Heading" };
        if (tag === "LI") return { mode: "prose", label: "Edit List Item" };
        if (tag === "UL" || tag === "OL") return { mode: "prose", label: "Edit List" };
        if (tag === "DIV" && classes.includes("markee-html-block")) return { mode: "code", label: "Edit Block" };
        if (tag === "TABLE") return { mode: "code", label: "Edit Table" };
        if (tag === "PRE") {
            return classes.includes("mermaid")
                ? { mode: "code", label: "Edit Diagram" }
                : { mode: "code", label: "Edit Code Block" };
        }
        return { mode: "prose", label: "Edit Block" };
    }

    // markdown-it counts a lone "\r" as a line break but split("\n") doesn't,
    // so its token-map line numbers would no longer index the file's lines.
    function hasLoneCR(source) {
        return /\r(?!\n)/.test(String(source));
    }

    // Source lines start..<end, "\r"-stripped, minus trailing blank lines
    // (markdown-it's map end can include them). Null if out of range or the
    // source's line numbering can't be trusted.
    function sliceLines(source, start, end) {
        if (hasLoneCR(source)) return null;
        const lines = String(source).split("\n");
        if (end > lines.length) return null;
        const strip = (l) => (l.endsWith("\r") ? l.slice(0, -1) : l);
        while (end - start > 1 && strip(lines[end - 1]).trim() === "") end--;
        return { end, text: lines.slice(start, end).map(strip).join("\n") };
    }

    // The first non-blank source line at or after `line`; `line` itself when
    // only blank lines follow or the source isn't known.
    function skipBlankLines(source, line) {
        if (source == null) return line;
        const lines = String(source).split("\n");
        for (let i = line; i < lines.length; i++) {
            if (lines[i].trim() !== "") return i;
        }
        return line;
    }

    return { syntaxSpans, mapSelection, blockInfo, sliceLines, hasLoneCR, skipBlankLines };
});
