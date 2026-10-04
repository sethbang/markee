// Run with: node --test Tests/util.test.js
// (or `just test-js` from the repo root)

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const {
    slugify, pickActiveHeading,
    codeLanguageFromClass, wordCount, readingMinutes,
    headingLinkMarkdown, findMatchOffsets, shouldSuppressTaskToggle,
    maskCurrencyDollars
} = require(path.join(__dirname, "..", "Resources", "web", "util.js"));

test("slugify — basic kebabification", () => {
    assert.equal(slugify("Hello World"), "hello-world");
    assert.equal(slugify("Why & How?"), "why-how");
    assert.equal(slugify("   spaced   "), "spaced");
});

test("slugify — empty falls back to 'section'", () => {
    assert.equal(slugify(""), "section");
    assert.equal(slugify("!@#$"), "section");
});

test("slugify — keeps Unicode letters and digits", () => {
    assert.equal(slugify("Café au lait"), "café-au-lait");
    assert.equal(slugify("概要"), "概要");
    assert.equal(slugify("Шаг 2"), "шаг-2");
});

test("slugify — suffixes never collide with emitted or reserved slugs", () => {
    const used = new Map();
    assert.equal(slugify("Foo", used), "foo");
    assert.equal(slugify("Foo", used), "foo-1");
    assert.equal(slugify("Foo 1", used), "foo-1-1");
    assert.equal(slugify("Foo", used), "foo-2");
    const reserved = new Map([["intro", 1]]);
    assert.equal(slugify("Intro", reserved), "intro-1");
});

test("slugify — counts map de-duplicates across calls", () => {
    const counts = new Map();
    assert.equal(slugify("Setup", counts), "setup");
    assert.equal(slugify("Setup", counts), "setup-1");
    assert.equal(slugify("Setup", counts), "setup-2");
    assert.equal(slugify("Other", counts), "other");
});

test("pickActiveHeading — empty list returns null", () => {
    assert.equal(pickActiveHeading([], 800), null);
});

test("pickActiveHeading — scrolled to top picks first heading", () => {
    // All heading tops are below the 20% threshold (160px) → first heading wins.
    const positions = [
        { id: "intro", top: 300 },
        { id: "setup", top: 600 },
    ];
    assert.equal(pickActiveHeading(positions, 800), "intro");
});

test("pickActiveHeading — last heading at-or-above the 20% line wins", () => {
    // viewport 800, threshold = 160. Heading tops as seen via getBoundingClientRect:
    // 'intro' at top 50 (passed), 'setup' at top 150 (just barely passed),
    // 'next' at top 220 (not yet). Active = 'setup'.
    const positions = [
        { id: "intro", top: 50 },
        { id: "setup", top: 150 },
        { id: "next", top: 220 },
    ];
    assert.equal(pickActiveHeading(positions, 800), "setup");
});

test("pickActiveHeading — exactly at the threshold is active", () => {
    // threshold = 0.2 * 800 = 160. Heading at top = 160 is active.
    assert.equal(
        pickActiveHeading([{ id: "h", top: 160 }, { id: "h2", top: 161 }], 800),
        "h"
    );
});

test("pickActiveHeading — all headings below threshold picks first", () => {
    const positions = [
        { id: "a", top: 1000 },
        { id: "b", top: 2000 },
    ];
    assert.equal(pickActiveHeading(positions, 800), "a");
});

test("pickActiveHeading — preserves document order, not visual position", () => {
    // Caller passes positions in document order. We pick last qualifying entry
    // in that order, even if positions are non-monotonic (shouldn't happen,
    // but be tolerant).
    const positions = [
        { id: "first", top: 100 },
        { id: "second", top: 50 },
    ];
    // threshold 160. Both qualify. Last in order = 'second'.
    assert.equal(pickActiveHeading(positions, 800), "second");
});

test("codeLanguageFromClass — extracts language token", () => {
    assert.equal(codeLanguageFromClass("language-swift"), "swift");
    assert.equal(codeLanguageFromClass("hljs language-python foo"), "python");
    assert.equal(codeLanguageFromClass("language-objective-c"), "objective-c");
});

test("codeLanguageFromClass — null when no language token", () => {
    assert.equal(codeLanguageFromClass("hljs"), null);
    assert.equal(codeLanguageFromClass(""), null);
    assert.equal(codeLanguageFromClass(null), null);
    assert.equal(codeLanguageFromClass("language-"), null);
});

test("wordCount — splits on whitespace, ignores empties", () => {
    assert.equal(wordCount("one two three"), 3);
    assert.equal(wordCount("  leading   and   trailing  "), 3);
    assert.equal(wordCount(""), 0);
    assert.equal(wordCount("\n\n"), 0);
    assert.equal(wordCount(null), 0);
});

test("readingMinutes — ceil at 225 wpm, floor of 1", () => {
    assert.equal(readingMinutes(0), 1);
    assert.equal(readingMinutes(1), 1);
    assert.equal(readingMinutes(225), 1);
    assert.equal(readingMinutes(226), 2);
    assert.equal(readingMinutes(450), 2);
    assert.equal(readingMinutes(451), 3);
});

test("headingLinkMarkdown — builds a relative markdown link", () => {
    assert.equal(
        headingLinkMarkdown("Installation", "guide.md", "installation"),
        "[Installation](guide.md#installation)"
    );
});

test("headingLinkMarkdown — escapes brackets in the title", () => {
    assert.equal(
        headingLinkMarkdown("See [note]", "a.md", "see-note"),
        "[See \\[note\\]](a.md#see-note)"
    );
});

test("findMatchOffsets — case-insensitive, non-overlapping", () => {
    assert.deepEqual(findMatchOffsets("aXaXa", "x"), [1, 3]);
    assert.deepEqual(findMatchOffsets("AaAa", "aa"), [0, 2]);
    assert.deepEqual(findMatchOffsets("hello", "z"), []);
    assert.deepEqual(findMatchOffsets("abc", ""), []);
});

test("shouldSuppressTaskToggle — a plain click still toggles", () => {
    assert.equal(shouldSuppressTaskToggle({ dx: 0, dy: 0 }), false);
    assert.equal(shouldSuppressTaskToggle({ dx: 2, dy: 2 }), false);
    assert.equal(shouldSuppressTaskToggle({}), false);
});

test("shouldSuppressTaskToggle — a selection drag does not toggle", () => {
    assert.equal(shouldSuppressTaskToggle({ dx: 60, dy: 0 }), true);
    assert.equal(shouldSuppressTaskToggle({ dx: 0, dy: -30 }), true);
    assert.equal(shouldSuppressTaskToggle({ dx: 0, dy: 0, hasSelection: true }), true);
});

test("shouldSuppressTaskToggle — the checkbox itself always toggles", () => {
    assert.equal(shouldSuppressTaskToggle({ onCheckbox: true, hasSelection: true }), false);
    assert.equal(shouldSuppressTaskToggle({ onCheckbox: true, dx: 90, dy: 90 }), false);
});

test("maskCurrencyDollars — money in prose is masked", () => {
    const M = "";
    assert.equal(
        maskCurrencyDollars("peak need is ~$127k, Prolific ~$350M", M),
        `peak need is ~${M}127k, Prolific ~${M}350M`
    );
    assert.equal(maskCurrencyDollars("paid $100/hour", M), `paid ${M}100/hour`);
});

test("maskCurrencyDollars — inline math survives", () => {
    const M = "";
    assert.equal(maskCurrencyDollars("Inline: $a^2 + b^2 = c^2$.", M), "Inline: $a^2 + b^2 = c^2$.");
    assert.equal(maskCurrencyDollars("no dollars here", M), "no dollars here");
    assert.equal(maskCurrencyDollars("", M), "");
    assert.equal(maskCurrencyDollars(null, M), "");
});

test("maskCurrencyDollars — $$ display math is left alone", () => {
    const M = "";
    assert.equal(maskCurrencyDollars("$$5 + 5$$", M), "$$5 + 5$$");
    assert.equal(maskCurrencyDollars("$$\n1 + 2\n$$", M), "$$\n1 + 2\n$$");
});
