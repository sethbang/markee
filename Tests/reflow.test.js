// Run with: node --test Tests/reflow.test.js
// Unit-tests reflow.js against an input->output table using the same markdown-it
// pipeline render.test.js builds. Requires `just fetch-vendor` to have run.

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const ROOT = path.join(__dirname, "..");
const VENDOR = path.join(ROOT, "Resources", "web", "vendor", "markdown-it");
const { createRenderer } = require(path.join(ROOT, "Resources", "web", "render-core.js"));
const { reflow } = require(path.join(ROOT, "Resources", "web", "reflow.js"));

function buildMd() {
    return createRenderer({
        markdownit: require(path.join(VENDOR, "markdown-it.min.js")),
        footnote: require(path.join(VENDOR, "markdown-it-footnote.min.js")),
        deflist: require(path.join(VENDOR, "markdown-it-deflist.min.js")),
        attrs: require(path.join(VENDOR, "markdown-it-attrs.min.js")),
        taskLists: require(path.join(VENDOR, "markdown-it-task-lists.min.js"))
    });
}

const md = buildMd();
const r = (src) => reflow(src, md);

test("collapses a hard-wrapped prose paragraph", () => {
    assert.equal(
        r("This is a paragraph that\nwas wrapped narrow\nacross three lines."),
        "This is a paragraph that was wrapped narrow across three lines.");
});

test("preserves blank-line paragraph breaks", () => {
    assert.equal(r("first para one\ntwo\n\nsecond para one\ntwo"),
        "first para one two\n\nsecond para one two");
});

test("unwraps an unordered list item, keeps the marker", () => {
    assert.equal(r("- a list item wrapped across\n  two source lines\n- second item"),
        "- a list item wrapped across two source lines\n- second item");
});

test("unwraps an ordered list item", () => {
    assert.equal(r("1. first item wrapped\n   onto a second line"),
        "1. first item wrapped onto a second line");
});

test("unwraps a blockquote, keeps one > per output line", () => {
    assert.equal(r("> a blockquote wrapped\n> across two lines"),
        "> a blockquote wrapped across two lines");
});

test("unwraps a nested blockquote", () => {
    assert.equal(r("> > deeply wrapped\n> > second line"),
        "> > deeply wrapped second line");
});

test("unwraps a blockquote nested in a list item", () => {
    assert.equal(r("- item\n  > quote wrapped\n  > here"),
        "- item\n  > quote wrapped here");
});

test("leaves fenced code untouched", () => {
    const src = "```js\nconst x = 1\nconst y = 2\n```";
    assert.equal(r(src), src);
});

test("leaves a table untouched", () => {
    const src = "| a | b |\n|---|---|\n| 1 | 2 |";
    assert.equal(r(src), src);
});

test("leaves headings and hr untouched, reflows prose after", () => {
    assert.equal(r("# Heading\n\n---\n\nprose line one\nline two"),
        "# Heading\n\n---\n\nprose line one line two");
});

test("leaves a two-space hard-break paragraph verbatim", () => {
    const src = "line one has a hard break  \nline two after break";
    assert.equal(r(src), src);
});

test("leaves a backslash hard-break paragraph verbatim", () => {
    const src = "line one\\\nline two";
    assert.equal(r(src), src);
});

test("preserves YAML front matter verbatim", () => {
    assert.equal(r("---\ntitle: My Doc\ntags: [a, b]\n---\n\nprose one\ntwo"),
        "---\ntitle: My Doc\ntags: [a, b]\n---\n\nprose one two");
});

test("preserves a trailing newline", () => {
    assert.equal(r("prose one\ntwo\n"), "prose one two\n");
});

test("normalizes CRLF input to LF but still reflows", () => {
    assert.equal(r("prose one\r\ntwo\r\n"), "prose one two\n");
});

test("returns non-string input safely", () => {
    assert.equal(r(null), "");
    assert.equal(r(undefined), "");
});

test("keeps a leading BOM as the real U+FEFF character", () => {
    const out = r("﻿first\nsecond\n");
    assert.equal(out, "﻿first second\n");
    assert.ok(!out.includes("\\uFEFF"));
});

test("front matter with a ... closer is kept verbatim", () => {
    assert.equal(r("---\na: 1\n...\nwrapped\nline\n"), "---\na: 1\n...\nwrapped line\n");
});
