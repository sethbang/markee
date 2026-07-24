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
