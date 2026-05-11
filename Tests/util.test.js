// Run with: node --test Tests/util.test.js
// (or `make test-js` from the repo root)

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const { collectTaskLineNumbers, slugify } = require(path.join(__dirname, "..", "Resources", "web", "util.js"));
const { pickActiveHeading } = require(path.join(__dirname, "..", "Resources", "web", "util.js"));

test("collectTaskLineNumbers — empty input", () => {
    assert.deepEqual(collectTaskLineNumbers(""), []);
    assert.deepEqual(collectTaskLineNumbers(null), []);
    assert.deepEqual(collectTaskLineNumbers(undefined), []);
});

test("collectTaskLineNumbers — three consecutive tasks", () => {
    const src = "- [ ] one\n- [x] two\n- [X] three\n";
    assert.deepEqual(collectTaskLineNumbers(src), [0, 1, 2]);
});

test("collectTaskLineNumbers — task lines mixed with prose", () => {
    const src = [
        "# heading",
        "",
        "intro paragraph",
        "",
        "- [ ] first",
        "- regular bullet",
        "- [x] second",
        "",
        "outro",
    ].join("\n");
    assert.deepEqual(collectTaskLineNumbers(src), [4, 6]);
});

test("collectTaskLineNumbers — different bullet styles + numeric ordered lists", () => {
    const src = [
        "- [ ] dash",
        "* [ ] star",
        "+ [x] plus",
        "1. [ ] numeric",
    ].join("\n");
    assert.deepEqual(collectTaskLineNumbers(src), [0, 1, 2, 3]);
});

test("collectTaskLineNumbers — indented (nested) tasks count", () => {
    const src = [
        "- [ ] parent",
        "    - [ ] nested",
        "        - [x] deeply nested",
    ].join("\n");
    assert.deepEqual(collectTaskLineNumbers(src), [0, 1, 2]);
});

test("collectTaskLineNumbers — skips fenced code blocks", () => {
    const src = [
        "- [ ] real task",
        "",
        "```",
        "- [ ] fake task in code",
        "- [x] also fake",
        "```",
        "",
        "- [x] another real",
    ].join("\n");
    assert.deepEqual(collectTaskLineNumbers(src), [0, 7]);
});

test("collectTaskLineNumbers — tilde fences also recognized", () => {
    const src = [
        "- [ ] real",
        "~~~bash",
        "- [ ] hidden",
        "~~~",
        "- [x] real",
    ].join("\n");
    assert.deepEqual(collectTaskLineNumbers(src), [0, 4]);
});

test("collectTaskLineNumbers — backtick fence inside tilde block doesn't close it", () => {
    const src = [
        "~~~",
        "```",
        "- [ ] still hidden",
        "```",
        "~~~",
        "- [ ] real",
    ].join("\n");
    assert.deepEqual(collectTaskLineNumbers(src), [5]);
});

test("collectTaskLineNumbers — skips YAML front matter", () => {
    const src = [
        "---",
        "title: example",
        "tags:",
        "  - [a, b]",
        "---",
        "",
        "- [ ] first real task",
        "- [x] second real task",
    ].join("\n");
    assert.deepEqual(collectTaskLineNumbers(src), [6, 7]);
});

test("collectTaskLineNumbers — front matter with ... terminator", () => {
    const src = "---\ntitle: x\n...\n- [ ] task\n";
    assert.deepEqual(collectTaskLineNumbers(src), [3]);
});

test("collectTaskLineNumbers — no front matter when first line isn't ---", () => {
    const src = "# heading\n\n- [ ] task\n";
    assert.deepEqual(collectTaskLineNumbers(src), [2]);
});

test("collectTaskLineNumbers — CRLF line endings", () => {
    const src = "- [ ] one\r\n- [x] two\r\n";
    assert.deepEqual(collectTaskLineNumbers(src), [0, 1]);
});

test("collectTaskLineNumbers — BOM at start of file", () => {
    const src = "﻿- [ ] task\n";
    assert.deepEqual(collectTaskLineNumbers(src), [0]);
});

test("collectTaskLineNumbers — must have a space after bracket", () => {
    // "[ ]task" with no space after isn't a task list per markdown-it
    const src = "- [ ]task\n- [ ] task\n";
    assert.deepEqual(collectTaskLineNumbers(src), [1]);
});

test("collectTaskLineNumbers — bracket must contain space, x, or X (single char)", () => {
    const src = [
        "- [y] not a task",
        "- [  ] two spaces, not a task",
        "- [ ] yes task",
    ].join("\n");
    assert.deepEqual(collectTaskLineNumbers(src), [2]);
});

test("slugify — basic kebabification", () => {
    assert.equal(slugify("Hello World"), "hello-world");
    assert.equal(slugify("Why & How?"), "why-how");
    assert.equal(slugify("   spaced   "), "spaced");
});

test("slugify — empty falls back to 'section'", () => {
    assert.equal(slugify(""), "section");
    assert.equal(slugify("!@#$"), "section");
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
