const test = require("node:test");
const assert = require("node:assert/strict");
const { syntaxSpans, mapSelection, blockInfo, sliceLines, hasLoneCR, skipBlankLines } = require("../Resources/web/quick-edit-core.js");

test("spans concatenate back to source", () => {
    const samples = [
        "## Heading with `code`",
        "- [x] done *item*",
        "> quoted **bold** text",
        "some _emph_ and __strong__ here",
        "see [the list](./a.md) and ![img](p.png)",
        "| a | b |\n|---|---|\n| 1 | 2 |",
        "    let x = a * b;\n    return x;",
        "*"
    ];
    for (const s of samples) {
        assert.equal(syntaxSpans(s, "prose").map(x => x.text).join(""), s);
    }
});

test("link punctuation is syntax, link text is not", () => {
    const syn = syntaxSpans("see [the list](./a.md).", "prose").filter(x => x.syntax).map(x => x.text);
    assert.deepEqual(syn, ["[", "](./a.md)"]);
});

test("unpaired asterisk is prose", () => {
    assert.equal(syntaxSpans("5 * 3", "prose").some(x => x.syntax), false);
});

test("code mode greys nothing", () => {
    assert.deepEqual(syntaxSpans("**x**", "code"), [{ text: "**x**", syntax: false }]);
});

test("heading, list, task, quote markers are syntax", () => {
    const syn = s => syntaxSpans(s, "prose").filter(x => x.syntax).map(x => x.text);
    assert.deepEqual(syn("## Title"), ["## "]);
    assert.deepEqual(syn("1. one"), ["1. "]);
    assert.deepEqual(syn("- [ ] todo"), ["- ", "[ ]"]);
    assert.deepEqual(syn("> > q"), ["> > "]);
    assert.deepEqual(syn("a **b** c"), ["**", "**"]);
    assert.deepEqual(syn("`x`"), ["`", "`"]);
    assert.deepEqual(syn("|---|---|"), ["|---|---|"]);
});

test("maps a sentence across soft wrap and bold", () => {
    const src = "We ship to **beta**\nfirst. Cut me.";
    const r = mapSelection(src, "beta first. Cut me.");
    assert.deepEqual(r, { start: src.indexOf("beta"), end: src.length });
});

test("ambiguous selection maps to null", () => {
    assert.equal(mapSelection("a b a b", "a b"), null);
});

test("typographer-changed text maps to null", () => {
    assert.equal(mapSelection('say "hi"', "say “hi”"), null);
});

test("empty and missing selections map to null", () => {
    assert.equal(mapSelection("abc", ""), null);
    assert.equal(mapSelection("abc", "   "), null);
    assert.equal(mapSelection("abc", "xyz"), null);
});

test("maps across a link tail", () => {
    const src = "go to [the list](./a.md) now";
    const r = mapSelection(src, "the list");
    assert.equal(src.slice(r.start, r.end), "the list");
    const r2 = mapSelection(src, "the list now");
    assert.equal(src.slice(r2.start, r2.end), "the list](./a.md) now");
});

test("regex metacharacters in selection are literal", () => {
    assert.deepEqual(mapSelection("cost (a+b)? yes", "(a+b)?"), { start: 5, end: 11 });
});

test("labels", () => {
    assert.deepEqual(blockInfo("P", []), { mode: "prose", label: "Edit Paragraph" });
    for (const h of ["H1", "H2", "H3", "H4", "H5", "H6"]) {
        assert.deepEqual(blockInfo(h, []), { mode: "prose", label: "Edit Heading" });
    }
    assert.deepEqual(blockInfo("LI", []), { mode: "prose", label: "Edit List Item" });
    assert.deepEqual(blockInfo("TABLE", []), { mode: "code", label: "Edit Table" });
    assert.deepEqual(blockInfo("PRE", ["mermaid"]), { mode: "code", label: "Edit Diagram" });
    assert.deepEqual(blockInfo("PRE", []), { mode: "code", label: "Edit Code Block" });
    for (const t of ["BLOCKQUOTE", "DL", "DT", "DD", "HR"]) {
        assert.deepEqual(blockInfo(t, []), { mode: "prose", label: "Edit Block" });
    }
});

test("long selection maps to null instead of throwing", () => {
    const long = "word ".repeat(1200).trim();
    assert.equal(mapSelection(long, long), null);
});

test("sliceLines strips CR and trailing blank lines", () => {
    assert.deepEqual(sliceLines("a\r\nb\r\n\r\nc", 0, 3), { end: 2, text: "a\nb" });
    assert.equal(sliceLines("a\nb", 0, 5), null);
});

test("a lone CR refuses slicing; CRLF does not", () => {
    assert.equal(hasLoneCR("a\r\nb\r\n"), false);
    assert.equal(hasLoneCR("a\rb\n"), true);
    assert.equal(hasLoneCR("a\nb\r"), true);
    assert.equal(sliceLines("# T\ra\n\nalpha\n", 2, 3), null);
});

test("blockInfo labels lists and html blocks", () => {
    assert.deepEqual(blockInfo("UL", []), { mode: "prose", label: "Edit List" });
    assert.deepEqual(blockInfo("OL", []), { mode: "prose", label: "Edit List" });
    assert.deepEqual(blockInfo("DIV", ["markee-html-block"]), { mode: "code", label: "Edit Block" });
    assert.deepEqual(blockInfo("DIV", ["other"]), { mode: "prose", label: "Edit Block" });
});

const synOf = s => syntaxSpans(s, "prose").filter(x => x.syntax).map(x => x.text);
const joined = s => syntaxSpans(s, "prose").map(x => x.text).join("");

test("image nested in a link greys only punctuation", () => {
    const s = "[![alt](img.png)](http://u)";
    assert.deepEqual(synOf(s), ["[", "![", "](img.png)", "](http://u)"]);
    assert.equal(joined(s), s);
});

test("reference and collapsed links grey brackets and ref", () => {
    assert.deepEqual(synOf("see [text][ref] now"), ["[", "][ref]"]);
    assert.deepEqual(synOf("see [text][] now"), ["[", "][]"]);
});

test("reference definition line is all syntax", () => {
    const s = '[ref]: https://x "t"';
    assert.deepEqual(synOf(s), [s]);
});

test("autolink brackets are syntax, URL is prose", () => {
    assert.deepEqual(synOf("go <https://example.com> now"), ["<", ">"]);
    const spans = syntaxSpans("<https://example.com>", "prose");
    assert.deepEqual(spans.map(x => x.text), ["<", "https://example.com", ">"]);
});

test("link URL with balanced parentheses is one syntax tail", () => {
    const s = "[t](https://en.wikipedia.org/wiki/A_(b)) end";
    assert.deepEqual(synOf(s), ["[", "](https://en.wikipedia.org/wiki/A_(b))"]);
    assert.equal(joined(s), s);
});

test("CRLF input keeps CR out of syntax and concatenates", () => {
    const s = "> a **b**\r\n> c\r\n\r\n- x\r\n- y\r\n";
    assert.equal(joined(s), s);
    for (const sp of syntaxSpans(s, "prose")) {
        if (sp.syntax) assert.doesNotMatch(sp.text, /\r/);
    }
});

test("multi-line quote and list greys markers on every line", () => {
    const q = "> one\n> two\n> three";
    assert.equal(joined(q), q);
    assert.deepEqual(synOf(q), ["> ", "> ", "> "]);
    const l = "- a\n- b\n  - c";
    assert.equal(joined(l), l);
    assert.deepEqual(synOf(l), ["- ", "- ", "- "]);
});

test("mapSelection returns null when the regex engine throws", () => {
    const Real = globalThis.RegExp;
    globalThis.RegExp = function () { throw new Error("boom"); };
    try {
        assert.equal(mapSelection("hello world", "hello"), null);
    } finally {
        globalThis.RegExp = Real;
    }
});

test("adversarial bracket line is fast and still concatenates", () => {
    const s = "[[[".repeat(6000) + "](".repeat(6000) + "](".repeat(1000);
    const t = Date.now();
    const out = syntaxSpans(s, "prose").map(x => x.text).join("");
    assert.ok(Date.now() - t < 500, "took " + (Date.now() - t) + "ms");
    assert.equal(out, s);
});

test("skipBlankLines lands on the next non-blank line", () => {
    const src = "a\n\n \t\r\n<details>\nb\n";
    assert.equal(skipBlankLines(src, 1), 3);
    assert.equal(skipBlankLines(src, 3), 3);
    assert.equal(skipBlankLines(src, 0), 0);
});

test("skipBlankLines keeps the line when only blanks follow or the source is unknown", () => {
    assert.equal(skipBlankLines("a\n\n\n", 1), 1);
    assert.equal(skipBlankLines(null, 4), 4);
    assert.equal(skipBlankLines("a\n", 9), 9);
});
