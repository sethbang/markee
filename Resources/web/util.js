// Pure utility functions shared between the in-browser renderer and Node tests.
// UMD-ish: exposes `window.markeeUtil` in the browser, `module.exports` in Node.

(function (root, factory) {
    if (typeof module !== "undefined" && module.exports) {
        module.exports = factory();
    } else {
        root.markeeUtil = factory();
    }
})(typeof self !== "undefined" ? self : (typeof globalThis !== "undefined" ? globalThis : this), function () {
    "use strict";

    /**
     * Scan raw markdown source for task-list lines, skipping YAML front matter
     * and fenced code blocks. Returns 0-based line indices in DOM order.
     *
     * A task-list line is a list item whose first inline token is `[ ]` or
     * `[x]` (or `[X]`). The line indices returned line up 1:1 with the
     * task-list <li> elements that markdown-it-task-lists produces.
     */
    function collectTaskLineNumbers(source) {
        const result = [];
        if (typeof source !== "string" || source.length === 0) return result;

        const lines = source.replace(/^﻿/, "").split("\n");
        let i = 0;

        // Skip YAML front matter when the file starts with `---`
        if (lines[0] === "---") {
            for (let j = 1; j < lines.length; j++) {
                if (lines[j] === "---" || lines[j] === "...") {
                    i = j + 1;
                    break;
                }
            }
        }

        let fence = null; // "`" or "~" when inside a fenced code block
        const TASK_RE = /^\s*(?:[-+*]|\d+\.)\s+\[[ xX]\](?:\s|$)/;
        const FENCE_RE = /^\s{0,3}(```+|~~~+)/;

        for (; i < lines.length; i++) {
            const line = lines[i].replace(/\r$/, "");
            const fm = line.match(FENCE_RE);
            if (fm) {
                const marker = fm[1][0];
                if (fence === null) fence = marker;
                else if (fence === marker) fence = null;
                continue;
            }
            if (fence !== null) continue;
            if (TASK_RE.test(line)) result.push(i);
        }
        return result;
    }

    /**
     * Slug a heading-text string into an html-id-safe form.
     * Accepts an optional `counts` map for de-duplication across multiple calls.
     */
    function slugify(text, counts) {
        const base = String(text)
            .toLowerCase()
            .replace(/[^\w\s-]/g, "")
            .trim()
            .replace(/\s+/g, "-") || "section";
        if (!counts) return base;
        const n = counts.get(base) || 0;
        counts.set(base, n + 1);
        return n === 0 ? base : `${base}-${n}`;
    }

    return { collectTaskLineNumbers, slugify };
});
