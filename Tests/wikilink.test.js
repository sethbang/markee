// Run with: node --test Tests/wikilink.test.js
const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const ROOT = path.join(__dirname, "..");
const VENDOR = path.join(ROOT, "Resources", "web", "vendor", "markdown-it");
const { createRenderer } = require(path.join(ROOT, "Resources", "web", "render-core.js"));

function md() {
    return createRenderer({ markdownit: require(path.join(VENDOR, "markdown-it.min.js")) });
}
const INDEX = { note: "markee-doc://doc/Note.md", "api/ref": "markee-doc://doc/api/ref.md" };

test("resolved [[Note]] becomes a wiki anchor", () => {
    const html = md().render("See [[Note]].", { wikiIndex: INDEX });
    assert.match(html, /<a href="markee-doc:\/\/doc\/Note\.md" class="markee-wikilink">Note<\/a>/);
});

test("[[Note#Heading]] appends a slug fragment", () => {
    const html = md().render("[[Note#Big Heading]]", { wikiIndex: INDEX });
    assert.match(html, /href="markee-doc:\/\/doc\/Note\.md#big-heading"/);
});

test("[[Note|Alias]] uses the alias as label", () => {
    const html = md().render("[[Note|Click me]]", { wikiIndex: INDEX });
    assert.match(html, />Click me<\/a>/);
});

test("unresolved [[Missing]] renders a broken span", () => {
    const html = md().render("[[Missing]]", { wikiIndex: INDEX });
    assert.match(html, /<span class="markee-wikilink-broken"[^>]*>Missing<\/span>/);
    assert.doesNotMatch(html, /<a /);
});

test("no wikiIndex (Quick Look) → everything broken, never an anchor", () => {
    const html = md().render("[[Note]]", {});
    assert.match(html, /markee-wikilink-broken/);
    assert.doesNotMatch(html, /<a /);
});
