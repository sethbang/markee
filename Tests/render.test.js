// Run with: node --test Tests/render.test.js
// Snapshots the real markdown-it pipeline (render-core.js + the vendored
// bundles) against fixtures/sample.md. Update goldens with:
//   UPDATE_SNAPSHOTS=1 node --test Tests/render.test.js
//
// Requires `just fetch-vendor` to have run (CI does this before `just test`).

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.join(__dirname, "..");
const VENDOR = path.join(ROOT, "Resources", "web", "vendor", "markdown-it");
const { createRenderer, stripFrontMatter } = require(path.join(ROOT, "Resources", "web", "render-core.js"));

function buildNodeRenderer() {
    return createRenderer({
        markdownit: require(path.join(VENDOR, "markdown-it.min.js")),
        footnote: require(path.join(VENDOR, "markdown-it-footnote.min.js")),
        deflist: require(path.join(VENDOR, "markdown-it-deflist.min.js")),
        attrs: require(path.join(VENDOR, "markdown-it-attrs.min.js")),
        taskLists: require(path.join(VENDOR, "markdown-it-task-lists.min.js"))
        // no hljs → fenced code renders as escaped <pre><code>, deterministic.
    });
}

test("sample.md renders to the committed snapshot", () => {
    const md = buildNodeRenderer();
    assert.ok(md, "renderer should build");
    const src = fs.readFileSync(path.join(ROOT, "fixtures", "sample.md"), "utf8");
    const { body } = stripFrontMatter(src);
    const html = md.render(body);

    const snapPath = path.join(__dirname, "snapshots", "sample.html");
    if (process.env.UPDATE_SNAPSHOTS === "1") {
        fs.mkdirSync(path.dirname(snapPath), { recursive: true });
        fs.writeFileSync(snapPath, html);
        return;
    }
    const expected = fs.readFileSync(snapPath, "utf8");
    assert.equal(html, expected);
});

test("markdown-it-attrs never emits event-handler or style attributes", () => {
    const md = buildNodeRenderer();
    const html = md.render('para {onmouseover="alert(1)" onclick=x style="color:red" .ok #anchor data-k=v}\n');
    assert.doesNotMatch(html, /\son\w+=/i);
    assert.doesNotMatch(html, /style=/);
    assert.match(html, /class="ok"/);
    assert.match(html, /id="anchor"/);
    assert.match(html, /data-k="v"/);
});

// ---- source-line stamping (task write-back targets) -------------------------
// Mirrors Swift's toggleTask guard: the stamped line must be the task's own
// marker line, or a click rewrites some other line of the file.
const SWIFT_TASK_RE = /^\s*(?:>\s*)*(?:[-+*]|\d+[.)])\s+\[[ xX]\]/;

function taskLines(source) {
    const md = buildNodeRenderer();
    const fm = stripFrontMatter(source);
    const html = md.render(fm.body, { lineOffset: fm.lineCount });
    const items = html.match(/<li class="task-list-item[^"]*"[^>]*>/g) || [];
    return items.map((tag) => {
        const m = tag.match(/data-line="(\d+)"/);
        return m ? Number(m[1]) : null;
    });
}

function assertTaskLines(source, expected) {
    const lines = taskLines(source);
    assert.deepEqual(lines, expected);
    const raw = source.replace(/^﻿/, "").split("\n");
    for (const n of lines) assert.match(raw[n].replace(/\r$/, ""), SWIFT_TASK_RE, `line ${n}`);
}

test("task lines: plain list, prose, numeric and paren ordered lists", () => {
    assertTaskLines("- [ ] a\n\ntext\n\n* [x] b\n1. [ ] c\n\n2) [ ] d\n", [0, 4, 5, 7]);
});

test("task lines: blockquoted tasks", () => {
    assertTaskLines("> - [ ] quoted\n> - [x] two\n\n- [ ] a\n", [0, 1, 3]);
});

test("task lines: fences, indented code and HTML blocks hold no tasks", () => {
    const src = [
        "- item",                 // 0
        "  ```",                  // 1
        "  - [ ] in fence",       // 2
        "  ```",                  // 3
        "",                       // 4
        "````",                   // 5
        "```",                    // 6
        "- [ ] in longer fence",  // 7
        "````",                   // 8
        "",                       // 9
        "    - [ ] indented code", // 10
        "",                       // 11
        "<div>",                  // 12
        "- [ ] in html block",    // 13
        "</div>",                 // 14
        "",                       // 15
        "- [ ] real",             // 16
    ].join("\n");
    assertTaskLines(src, [16]);
});

test("task lines: front matter offsets (LF, CRLF, ... closer)", () => {
    assertTaskLines("---\ntitle: x\n---\n- [ ] a\n", [3]);
    assertTaskLines("---\r\ntags:\r\n  - [ ] not a task\r\n---\r\n- [ ] a\r\n", [4]);
    assertTaskLines("---\ntitle: x\n...\n\n- [ ] a\n", [4]);
    assertTaskLines("﻿---\na: 1\n---\n- [ ] a\n", [3]);
});

test("task lines: nested tasks each get their own line", () => {
    assertTaskLines("- [ ] parent\n  - [x] child\n    - [ ] grandchild\n", [0, 1, 2]);
});

test("headings carry their source line; raw HTML headings don't", () => {
    const md = buildNodeRenderer();
    const html = md.render("# One\n\n<h2>raw</h2>\n\n## Two\n", { lineOffset: 2 });
    assert.match(html, /<h1 data-line="2">One<\/h1>/);
    assert.match(html, /<h2>raw<\/h2>/);
    assert.match(html, /<h2 data-line="6">Two<\/h2>/);
});

test("splitFrontMatter keeps BOM and block verbatim", () => {
    const { splitFrontMatter } = require(path.join(ROOT, "Resources", "web", "render-core.js"));
    const parts = splitFrontMatter("﻿---\r\na: 1\r\n---\r\nbody\n");
    assert.equal(parts.bom, "﻿");
    assert.equal(parts.frontMatter, "---\r\na: 1\r\n---\r\n");
    assert.equal(parts.body, "body\n");
    assert.equal(parts.lineCount, 3);
    assert.equal(splitFrontMatter("--- not fm\n").frontMatter, "");
    assert.equal(splitFrontMatter("---\na: 1\n---").body, "");
});

test("autolinks follow GFM: www. and schemes link, bare file names don't", () => {
    const html = buildNodeRenderer().render(
        "Visit www.example.com, https://example.com/x, mail me@example.com, read notes.md, README.md and example.com.\n");
    assert.match(html, /<a href="http:\/\/www\.example\.com">www\.example\.com<\/a>/);
    assert.match(html, /<a href="https:\/\/example\.com\/x">/);
    assert.match(html, /<a href="mailto:me@example\.com">/);
    assert.doesNotMatch(html, /href="http:\/\/notes\.md"/);
    assert.doesNotMatch(html, /href="http:\/\/README\.md"/);
    assert.doesNotMatch(html, /href="http:\/\/example\.com"/);
    assert.match(html, /read notes\.md, README\.md and example\.com\./);
});
