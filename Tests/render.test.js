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
const { createRenderer, stripFrontMatter, isSelfContainedHtml } = require(path.join(ROOT, "Resources", "web", "render-core.js"));

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
    assert.match(html, /<h1 data-line="2" data-line-end="3">One<\/h1>/);
    assert.match(html, /<h2>raw<\/h2>/);
    assert.match(html, /<h2 data-line="6" data-line-end="7">Two<\/h2>/);
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

test("a bare domain with @ in its path stays plain text", () => {
    const html = buildNodeRenderer().render("See medium.com/@user and github.com/foo.\n");
    assert.doesNotMatch(html, /<a /);
});

function decodeEntities(s) {
    return s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&");
}

// No DOM in Node: walk the tag stream and collect the text under each stamped element.
function stampedElements(html) {
    const VOID = new Set(["hr", "br", "img", "input", "meta", "link"]);
    const out = [];
    const stack = [];
    const re = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>|([^<]+)/g;
    let m;
    while ((m = re.exec(html))) {
        if (m[4] !== undefined) {
            const text = decodeEntities(m[4]);
            for (const e of stack) e.text += text;
            continue;
        }
        const [, closing, tag, attrs] = m;
        if (closing) {
            const e = stack.pop();
            if (e && e.stamped) out.push(e);
            continue;
        }
        const line = attrs.match(/data-line="(\d+)"/);
        const end = attrs.match(/data-line-end="(\d+)"/);
        const el = {
            tag,
            parent: [...stack].reverse().find((e) => e.stamped) || null,
            cls: (attrs.match(/class="([^"]*)"/) || [])[1] || "",
            start: line && Number(line[1]),
            end: end && Number(end[1]),
            stamped: !!line,
            text: ""
        };
        if (VOID.has(tag.toLowerCase())) {
            if (el.stamped) out.push(el);
        } else {
            stack.push(el);
        }
    }
    return out;
}

const alnum = (s) => (s.match(/[\p{L}\p{N}]/gu) || []).join("");

test("every stamped block range round-trips to its source", () => {
    const md = buildNodeRenderer();
    const src = fs.readFileSync(path.join(ROOT, "fixtures", "sample.md"), "utf8");
    const fm = stripFrontMatter(src);
    const html = md.render(fm.body, { lineOffset: fm.lineCount });
    const lines = src.split("\n");
    const els = stampedElements(html);
    assert.ok(els.length > 10, "fixture should stamp many blocks");
    for (const el of els) {
        assert.ok(el.end > el.start, `${el.tag} ${el.start}..${el.end}`);
        const slice = lines.slice(el.start, el.end).join("\n");
        assert.ok(slice.trim().length > 0, `${el.tag} slice empty at ${el.start}`);
        if (el.tag === "pre" && el.cls.includes("mermaid")) continue;
        if (el.tag === "ol" || el.tag === "ul") continue;
        const head = alnum(el.text).slice(0, 12);
        assert.ok(alnum(slice).includes(head), `${el.tag} at ${el.start}..${el.end}: "${head}" not in "${slice}"`);
    }
});

test("fence outputs carry their range on <pre>", () => {
    const md = buildNodeRenderer();
    for (const src of ["```js\nx\n```\n", "```mermaid\ngraph TD\n```\n", "```\nx\n```\n"]) {
        assert.match(md.render(src), /^<pre data-line="0" data-line-end="3"/, src);
    }
});

test("tight list items carry the range, hidden paragraphs don't", () => {
    const html = buildNodeRenderer().render("- a\n- b\n");
    assert.equal((html.match(/<li data-line="\d+" data-line-end="\d+">/g) || []).length, 2);
    assert.doesNotMatch(html, /<p data-line/);
});

test("task items inside footnotes keep data-line", () => {
    const html = buildNodeRenderer().render("a[^1]\n\n[^1]: note\n\n    - [ ] t\n");
    assert.match(html, /<li class="task-list-item[^"]*" data-line="\d+"/);
});

test("lists carry their own range", () => {
    const html = buildNodeRenderer().render("- a\n- b\n\n1. x\n2. y\n");
    assert.match(html, /<ul data-line="0" data-line-end="2"/);
    assert.match(html, /<ol data-line="3" data-line-end="5"/);
});

test("lists inside footnotes get no new range", () => {
    const html = buildNodeRenderer().render("a[^1]\n\n[^1]: note\n\n    - x\n    - y\n");
    assert.doesNotMatch(html, /<ul data-line/);
});

test("exact ranges with a front-matter offset", () => {
    const md = buildNodeRenderer();
    const r = (src) => md.render(src, { lineOffset: 3 });
    assert.match(r("para\nmore\n"), /<p data-line="3" data-line-end="5">/);
    assert.match(r("# H\n"), /<h1 data-line="3" data-line-end="4">/);
    assert.match(r("    code\n    more\n"), /^<pre data-line="3" data-line-end="5"/);
    assert.match(r("- item\n\n  ```\n  x\n  ```\n"), /<pre data-line="5" data-line-end="8"/);
    assert.match(r("> q\n>\n> ```\n> x\n> ```\n"), /<pre data-line="5" data-line-end="8"/);
    assert.match(r("a\n\n---\n\nb\n"), /<hr data-line="5" data-line-end="6"/);
    const dl = r("Term\n:   Def\n");
    assert.match(dl, /<dl data-line="3" data-line-end="5">/);
    assert.match(dl, /<dt data-line="3" data-line-end="4">/);
    assert.match(dl, /<dd data-line="4" data-line-end="5">/);
});

test("heading inside a footnote keeps data-line", () => {
    const html = buildNodeRenderer().render("a[^1]\n\n[^1]: note\n\n    # H\n");
    assert.match(html, /<h1 data-line="\d+" data-line-end="\d+">H<\/h1>/);
});

test("self-contained html block is wrapped with its range", () => {
    const html = buildNodeRenderer().render("<div>\n<b>x</b>\n</div>\n");
    assert.match(html, /^<div class="markee-html-block" data-line="0" data-line-end="3"><div>\n<b>x<\/b>\n<\/div>\n<\/div>/);
});

test("html block range honours the front-matter offset", () => {
    const html = buildNodeRenderer().render("<p>x</p>\n", { lineOffset: 4 });
    assert.match(html, /<div class="markee-html-block" data-line="4" data-line-end="5">/);
});

test("partial html block is not wrapped", () => {
    const html = buildNodeRenderer().render("<details>\n<summary>s</summary>\n\nbody\n\n</details>\n");
    assert.doesNotMatch(html, /markee-html-block/);
    assert.match(html, /<details>\n<summary>s<\/summary>/);
    assert.match(html, /<\/details>/);
});

test("isSelfContainedHtml", () => {
    assert.equal(isSelfContainedHtml("<div><p>a</p></div>"), true);
    assert.equal(isSelfContainedHtml("<div>\n<b>x</b>\n</div>\n"), true);
    assert.equal(isSelfContainedHtml("<p>a<br>b<img src=x></p>"), true);
    assert.equal(isSelfContainedHtml("<x/>"), false);
    assert.equal(isSelfContainedHtml("<DIV></div>"), true);
    assert.equal(isSelfContainedHtml("<!-- c --><div>x</div>"), true);
    assert.equal(isSelfContainedHtml("<!-- only a comment -->"), false);
    assert.equal(isSelfContainedHtml("<div><p>a</div>"), false);
    assert.equal(isSelfContainedHtml("<div>x"), false);
    assert.equal(isSelfContainedHtml("<b><i>x</b></i>"), false);
    assert.equal(isSelfContainedHtml("</div>"), false);
    assert.equal(isSelfContainedHtml("<details>\n<summary>s</summary>\n"), false);
});

test("a self-closed non-void tag is an open tag", () => {
    assert.equal(isSelfContainedHtml("<div/>"), false);
    assert.equal(isSelfContainedHtml("<div><span/></div>"), false);
    assert.equal(isSelfContainedHtml("<br/>"), true);
    assert.equal(isSelfContainedHtml("<img src=x />"), true);
    assert.equal(isSelfContainedHtml("<hr/>"), true);
    assert.equal(isSelfContainedHtml("<param name=a/>"), true);
    assert.equal(isSelfContainedHtml("<svg><path d=\"M0\"/></svg>"), true);
    assert.equal(isSelfContainedHtml("<math><mspace/></math>"), true);
    assert.equal(isSelfContainedHtml("<svg/>"), true);
});

test("a lone <div/> html block is not wrapped", () => {
    assert.doesNotMatch(buildNodeRenderer().render("<div/>\n"), /markee-html-block/);
});

test("<div/> opens a context: later html blocks are not wrapped inside it", () => {
    const html = buildNodeRenderer().render("<div/>\n\n<div>y</div>\n");
    assert.doesNotMatch(html, /markee-html-block/);
});

test("list inside a blockquote excludes the quote-only separator line", () => {
    const html = buildNodeRenderer().render("> - a\n> - b\n>\n> para\n");
    assert.match(html, /<ul data-line="0" data-line-end="2"/);
});

test("isSelfContainedHtml stays fast on in-cap unterminated tags and rejects oversized input", () => {
    const t = Date.now();
    assert.equal(isSelfContainedHtml("<a ".repeat(30000)), false);
    assert.ok(Date.now() - t < 500, "took " + (Date.now() - t) + "ms");
    assert.equal(isSelfContainedHtml("<a href=x>y</a>"), true);
    assert.equal(isSelfContainedHtml("<div>" + "x".repeat(100001) + "</div>"), false);
});

test("html block inside a footnote is not wrapped", () => {
    const html = buildNodeRenderer().render("a[^1]\n\n[^1]: note\n\n    <div>x</div>\n");
    assert.doesNotMatch(html, /markee-html-block/);
});

test("self-contained html inside an open partial html context is not wrapped", () => {
    const md = buildNodeRenderer();
    const shapes = [
        "<p align=\"center\">\n\n<img src=\"logo.png\">\n\n</p>\n",
        "<details>\n\n<summary>More</summary>\n\nBody\n\n</details>\n",
        "<table>\n\n<tr><td>a</td></tr>\n\n</table>\n",
        "<ul>\n\n<li>a</li>\n\n</ul>\n"
    ];
    for (const src of shapes) assert.doesNotMatch(md.render(src), /markee-html-block/, src);
});

test("html wrapping resumes once the partial context closes", () => {
    const html = buildNodeRenderer().render("<div>x</div>\n\n<details>\n\n<summary>s</summary>\n\n</details>\n\n<div>y</div>\n");
    const wraps = html.match(/<div class="markee-html-block"[^>]*><div>[xy]<\/div>/g) || [];
    assert.equal(wraps.length, 2, html);
    assert.doesNotMatch(html, /markee-html-block[^>]*><summary>/);
});

test("a stray closing tag doesn't poison later wrapping", () => {
    const html = buildNodeRenderer().render("</div>\n\n<div>y</div>\n");
    assert.match(html, /<div class="markee-html-block"[^>]*><div>y<\/div>/);
});

test("a partial html context closed by its markdown container frees later blocks", () => {
    const html = buildNodeRenderer().render("> <div>\n\npara\n\n<div>y</div>\n");
    assert.match(html, /<div class="markee-html-block"[^>]*><div>y<\/div>/);
});

test("an over-cap html block stops wrapping for the rest of the document", () => {
    const big = "<table>" + "x".repeat(100001) + "\n";
    const html = buildNodeRenderer().render(big + "\n<div>y</div>\n");
    assert.ok(!html.includes("markee-html-block"), "a block after the over-cap one was wrapped");
});

// Every stamp render-core emits carries env.stampKey; app.js drops data-line /
// data-line-end from any element without it, so raw HTML can't forge a range.
function openTags(html) {
    return html.match(/<[a-zA-Z][^>]*>/g) || [];
}

test("every render-core stamp carries the render's stamp key", () => {
    const md = buildNodeRenderer();
    const src = "# H\n\npara\n\n- a\n- b\n\n> q\n\n```js\nx\n```\n\n    code\n\n<div>raw</div>\n\n---\n\n| a |\n|---|\n| 1 |\n\nTerm\n:   Def\n";
    const tags = openTags(md.render(src, { stampKey: "k1" })).filter((t) => /data-line=/.test(t));
    assert.ok(tags.length > 10, tags.join("\n"));
    for (const t of tags) assert.match(t, /data-markee-stamp="k1"/, t);
});

test("no stamp key, no stamp attribute (Node snapshot stays put)", () => {
    assert.doesNotMatch(buildNodeRenderer().render("# H\n\n<div>x</div>\n"), /data-markee-stamp/);
});

test("author-written stamps never carry the key", () => {
    const md = buildNodeRenderer();
    const forged = [
        "<div><p data-line=\"0\" data-line-end=\"99\">x</p></div>\n",
        "<details>\n\n<p data-line=\"0\" data-line-end=\"99\">x</p>\n\n</details>\n",
        "<p data-line=\"0\" data-line-end=\"99\" data-markee-stamp=\"guess\">x</p>\n"
    ];
    for (const src of forged) {
        const p = openTags(md.render(src, { stampKey: "k1" })).find((t) => /^<p /.test(t));
        assert.doesNotMatch(p, /data-markee-stamp="k1"/, src);
    }
});

test("markdown-it-attrs can't set stamp attributes", () => {
    const html = buildNodeRenderer().render("a *x*{data-line=0 data-line-end=99 data-markee-stamp=k1 data-ok=1}\n", { stampKey: "k1" });
    const em = openTags(html).find((t) => /^<em/.test(t));
    assert.doesNotMatch(em, /data-line|data-markee-stamp/);
    assert.match(em, /data-ok="1"/);
});

const { sliceLines } = require(path.join(ROOT, "Resources", "web", "quick-edit-core.js"));

// Every stamped element's presented range (what Quick Edit would open, after
// sliceLines' trim) lies within its nearest stamped ancestor's.
function assertContained(source) {
    const md = buildNodeRenderer();
    const fm = stripFrontMatter(source);
    const html = md.render(fm.body, { lineOffset: fm.lineCount });
    const shown = (el) => (sliceLines(source, el.start, el.end) || { end: el.end }).end;
    for (const el of stampedElements(html)) {
        if (!el.parent) continue;
        const where = `${el.tag} [${el.start},${el.end}) in ${el.parent.tag} [${el.parent.start},${el.parent.end})`;
        assert.ok(el.start >= el.parent.start, where);
        assert.ok(el.end <= el.parent.end, where);
        assert.ok(shown(el) <= shown(el.parent), where);
    }
}

test("stamped ranges nest within their stamped ancestors", () => {
    assertContained(fs.readFileSync(path.join(ROOT, "fixtures", "sample.md"), "utf8"));
    for (const src of [
        "> - a\n>   > q\n>   >\n\nx\n",
        "> - a\n> - b\n>\n> c\n",
        "- a\n\n  b\n\n- c\n\npara\n",
        "> > - a\n> >\n> > b\n",
        "1. x\n\n   > q\n   >\n\n2. y\n"
    ]) assertContained(src);
});

test("a list keeps its nested quote's empty line; an item drops its own quote's", () => {
    const md = buildNodeRenderer();
    const nested = md.render("> - a\n>   > q\n>   >\n\nx\n");
    assert.match(nested, /<ul data-line="0" data-line-end="3"/);
    assert.match(nested, /<li data-line="0" data-line-end="3"/);
    const sibling = md.render("> - a\n> - b\n>\n> c\n");
    assert.match(sibling, /<li data-line="1" data-line-end="2"/);
});

test("many open tags between paragraphs stay fast", () => {
    const src = "<span>\n\npara\n\n".repeat(5000) + "<div>y</div>\n";
    const t = Date.now();
    const html = buildNodeRenderer().render(src);
    assert.ok(Date.now() - t < 2000, "took " + (Date.now() - t) + "ms");
    assert.ok(!html.includes("markee-html-block"));
});
