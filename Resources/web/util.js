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

    /**
     * Given an in-document-order list of heading positions `{id, top}` (top in
     * px relative to the viewport, as from getBoundingClientRect().top) and the
     * current viewport height, return the id of the "active" heading — the
     * last one whose top is at-or-above the 20% line. If none qualify (we're
     * above the first heading), returns the first heading's id. Returns null
     * for an empty list.
     */
    function pickActiveHeading(positions, viewportHeight) {
        if (!Array.isArray(positions) || positions.length === 0) return null;
        const threshold = viewportHeight * 0.2;
        let active = positions[0].id;
        for (let i = 0; i < positions.length; i++) {
            if (positions[i].top <= threshold) {
                active = positions[i].id;
            }
        }
        return active;
    }

    /**
     * Pull the language token out of a code element's className, e.g.
     * "hljs language-swift" → "swift". Returns null when there is no
     * non-empty `language-…` token.
     */
    function codeLanguageFromClass(className) {
        const m = String(className || "").match(/(?:^|\s)language-([^\s]+)/);
        return m && m[1] ? m[1] : null;
    }

    /** Count whitespace-delimited words; 0 for empty/null. */
    function wordCount(text) {
        const t = String(text || "").trim();
        if (!t) return 0;
        return t.split(/\s+/).length;
    }

    /** Estimated reading time in whole minutes at 225 wpm, minimum 1. */
    function readingMinutes(words) {
        const w = Number(words) || 0;
        return Math.max(1, Math.ceil(w / 225));
    }

    /**
     * Build a paste-ready relative markdown link to a heading:
     * "[Title](file.md#slug)". Brackets in the title are escaped so the link
     * text stays well-formed.
     */
    function headingLinkMarkdown(title, fileName, slug) {
        const safeTitle = String(title || "").replace(/\[/g, "\\[").replace(/\]/g, "\\]");
        return "[" + safeTitle + "](" + String(fileName || "") + "#" + String(slug || "") + ")";
    }

    /**
     * Case-insensitive, non-overlapping match offsets of `needle` in `haystack`.
     * Returns 0-based start indices. Empty needle → [].
     */
    function findMatchOffsets(haystack, needle) {
        const hay = String(haystack || "").toLowerCase();
        const nee = String(needle || "").toLowerCase();
        const out = [];
        if (!nee) return out;
        let from = 0, idx;
        while ((idx = hay.indexOf(nee, from)) !== -1) {
            out.push(idx);
            from = idx + nee.length;
        }
        return out;
    }

    /**
     * markdown-it-task-lists wraps a task item's text in a <label>, so any
     * click inside the item activates the checkbox. That makes selecting text
     * in a checklist impossible: releasing a selection drag toggles the box and
     * collapses the selection. Decide whether such a click should be
     * suppressed — true when the click ends a selection (drag or double-click),
     * false for a deliberate click on the checkbox itself.
     */
    function shouldSuppressTaskToggle(opts) {
        opts = opts || {};
        if (opts.onCheckbox) return false;
        if (opts.hasSelection) return true;
        const dx = Number(opts.dx) || 0;
        const dy = Number(opts.dy) || 0;
        const threshold = Number(opts.threshold) > 0 ? Number(opts.threshold) : 4;
        return Math.sqrt(dx * dx + dy * dy) > threshold;
    }

    /**
     * KaTeX's auto-render treats every `$` as an inline-math delimiter, so a
     * paragraph holding two currency amounts ("~$127k … ~$350M") gets typeset
     * as one long math run. Markee's rule: a `$` immediately followed by an
     * ASCII digit is money, not a delimiter, and is masked out before KaTeX
     * runs (the caller restores it afterwards).
     *
     * `$` adjacent to another `$` is left alone so `$$…$$` display math still
     * pairs up. The deliberate trade-off: inline math that starts or ends
     * against a digit (`$5=x$`) no longer renders.
     */
    function maskCurrencyDollars(text, mask) {
        const s = String(text == null ? "" : text);
        if (s.indexOf("$") === -1) return s;
        const m = typeof mask === "string" && mask.length ? mask : "\uE000";
        let out = "";
        for (let i = 0; i < s.length; i++) {
            const c = s[i];
            if (c !== "$") { out += c; continue; }
            const prev = i > 0 ? s[i - 1] : "";
            const next = i + 1 < s.length ? s[i + 1] : "";
            if (prev === "$" || next === "$") { out += c; continue; }
            out += (next >= "0" && next <= "9") ? m : c;
        }
        return out;
    }

    return {
        slugify, pickActiveHeading,
        codeLanguageFromClass, wordCount, readingMinutes,
        headingLinkMarkdown, findMatchOffsets, shouldSuppressTaskToggle,
        maskCurrencyDollars
    };
});
