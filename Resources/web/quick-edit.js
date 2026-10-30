// Quick Edit — swaps one rendered block for its raw Markdown, in place.
// Swift drives it through window.markee.beginQuickEdit / focusQuickEdit /
// saveQuickEdit / cancelQuickEdit / resolveQuickEdit / noticeQuickEdit and
// receives (kind) blockEdit/editState/contextBlock via webkit.messageHandlers.markee.

(function () {
    "use strict";

    const post = (kind, payload = {}) => {
        try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.markee) {
                window.webkit.messageHandlers.markee.postMessage(Object.assign({ kind }, payload));
            }
        } catch (_) { /* ignore */ }
    };

    const core = window.markeeQuickEditCore;
    const api = window.markee;
    if (!core || !api) return;

    const SOURCE_CLASS = "markee-quickedit-source";
    const NOTICES = {
        "disk-changed": "File changed on disk",
        "conflict": "Changed in another editor",
        "encoding": "Can't save: this file's encoding can't store some characters",
        "write": "Couldn't save the file"
    };

    let edit = null;
    let pointer = null;
    let contextTarget = null;
    let lastState = null;
    let loneCR = false;
    let renderedSource = null;

    const contentRoot = () => document.getElementById("content");

    function postState() {
        const state = {
            open: !!edit,
            dirty: !!edit && edit.dirty,
            // activeElement stays the textarea while native UI (find bar,
            // search palette) has the keyboard; hasFocus() tells them apart.
            focused: !!edit && document.activeElement === edit.textarea && document.hasFocus()
        };
        if (lastState && lastState.open === state.open && lastState.dirty === state.dirty &&
            lastState.focused === state.focused) return;
        lastState = state;
        post("editState", state);
    }

    function elementOf(node) {
        if (!node) return null;
        return node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
    }

    function blockFor(node) {
        const root = contentRoot();
        const el = elementOf(node);
        if (!root || !el || !root.contains(el) || el.closest(".markee-quickedit")) return null;
        let block = el.closest("[data-line]");
        if (block && !root.contains(block)) block = null;
        // A loose list wraps each item's text in a <p>; the item (with its marker) is the unit.
        if (block && block.tagName === "P" && block.parentElement && block.parentElement.tagName === "LI" &&
            block.parentElement.hasAttribute("data-line")) {
            block = block.parentElement;
        }
        return { el, block };
    }

    function rangeOf(block) {
        if (!block || !block.hasAttribute("data-line-end")) return null;
        const start = parseInt(block.getAttribute("data-line"), 10);
        const end = parseInt(block.getAttribute("data-line-end"), 10);
        return Number.isInteger(start) && Number.isInteger(end) && end > start ? { start, end } : null;
    }

    // Nearest known source line for an element with no range of its own (e.g.
    // footnotes, partial raw HTML): the first non-blank line after the last
    // stamped block before it.
    function nearestLine(el) {
        const root = contentRoot();
        if (!root || !el) return null;
        const owner = el.closest("[data-line]");
        if (owner && root.contains(owner)) return parseInt(owner.getAttribute("data-line"), 10);
        let line = null;
        for (const s of root.querySelectorAll("[data-line]")) {
            if (s.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_PRECEDING) break;
            const at = parseInt(s.getAttribute("data-line-end") ?? s.getAttribute("data-line"), 10);
            if (Number.isInteger(at) && (line === null || at > line)) line = at;
        }
        return line === null ? null : core.skipBlankLines(renderedSource, line);
    }

    function pickTarget(mode) {
        if (mode === "context") {
            const hit = blockFor(contextTarget);
            return hit ? { hit, carry: null } : null;
        }
        const sel = window.getSelection();
        if (sel && !sel.isCollapsed && sel.rangeCount > 0) {
            const range = sel.getRangeAt(0);
            const common = blockFor(range.commonAncestorContainer);
            if (common && common.block) return { hit: common, carry: sel.toString() };
            const first = blockFor(range.startContainer);
            return first ? { hit: first, carry: null } : null;
        }
        if (!pointer) return null;
        const hit = blockFor(document.elementFromPoint(pointer.x, pointer.y));
        return hit ? { hit, carry: null } : null;
    }

    function paintMirror() {
        const { mirror, textarea, mode } = edit;
        mirror.textContent = "";
        for (const span of core.syntaxSpans(textarea.value, mode)) {
            if (span.syntax) {
                const s = document.createElement("span");
                s.className = "markee-quickedit-syntax";
                s.textContent = span.text;
                mirror.appendChild(s);
            } else {
                mirror.appendChild(document.createTextNode(span.text));
            }
        }
        // Keeps a trailing newline's empty last line the same height as the textarea's.
        mirror.appendChild(document.createTextNode("​"));
    }

    function autosize() {
        const ta = edit.textarea;
        ta.style.height = "auto";
        ta.style.height = ta.scrollHeight + "px";
    }

    function setNotice(kind) {
        if (!edit || !NOTICES[kind]) return;
        edit.notice.textContent = NOTICES[kind];
        edit.notice.hidden = false;
    }

    function build(mode) {
        const wrapper = document.createElement("div");
        wrapper.className = "markee-quickedit markee-chrome" + (mode === "code" ? " markee-quickedit-code" : "");
        const field = document.createElement("div");
        field.className = "markee-quickedit-field markee-chrome";
        const mirror = document.createElement("div");
        mirror.className = "markee-quickedit-mirror markee-chrome";
        mirror.setAttribute("aria-hidden", "true");
        const textarea = document.createElement("textarea");
        textarea.className = "markee-quickedit-input markee-chrome";
        textarea.spellcheck = mode !== "code";
        textarea.setAttribute("aria-label", "Quick Edit");
        const notice = document.createElement("div");
        notice.className = "markee-quickedit-notice markee-chrome";
        notice.setAttribute("role", "status");
        notice.hidden = true;
        const hint = document.createElement("div");
        hint.className = "markee-quickedit-hint markee-chrome";
        const kbd = (t) => { const k = document.createElement("kbd"); k.textContent = t; return k; };
        hint.append(kbd("⌘↩"), " save · ", kbd("Esc"), " cancel");
        field.append(mirror, textarea);
        wrapper.append(field, notice, hint);
        return { wrapper, mirror, textarea, notice };
    }

    function close() {
        if (!edit) return;
        const { wrapper, block } = edit;
        edit = null;
        wrapper.remove();
        block.classList.remove(SOURCE_CLASS);
        api.setEditStandIn(null);
        postState();
    }

    function beginQuickEdit(source, mode) {
        if (api.isReadOnly()) return { ok: false, reason: "readonly" };
        if (edit) return { ok: false, reason: "already-open" };
        if (core.hasLoneCR(source)) return { ok: false, reason: "no-range" };
        const target = pickTarget(mode);
        if (!target) return { ok: false, reason: "no-block" };
        const { hit, carry } = target;
        const range = rangeOf(hit.block);
        const slice = range && core.sliceLines(source, range.start, range.end);
        if (!slice) {
            const line = nearestLine(hit.el);
            return line === null || Number.isNaN(line)
                ? { ok: false, reason: "no-range" }
                : { ok: false, reason: "no-range", line };
        }

        api.clearFind();
        const sel = window.getSelection();
        if (sel) sel.removeAllRanges();

        const info = core.blockInfo(hit.block.tagName, hit.block.classList);
        const parts = build(info.mode);
        edit = Object.assign(parts, {
            block: hit.block,
            mode: info.mode,
            start: range.start,
            end: slice.end,
            original: slice.text,
            dirty: false,
            refused: false,
            saving: false
        });
        parts.textarea.value = slice.text;
        hit.block.before(parts.wrapper);
        hit.block.classList.add(SOURCE_CLASS);
        api.setEditStandIn(parts.wrapper);
        wire(parts.textarea);
        paintMirror();
        autosize();

        const mapped = carry ? core.mapSelection(slice.text, carry) : null;
        parts.textarea.focus({ preventScroll: true });
        if (mapped) parts.textarea.setSelectionRange(mapped.start, mapped.end);
        else parts.textarea.setSelectionRange(0, 0);
        lastState = null;
        postState();
        return { ok: true };
    }

    function wire(textarea) {
        textarea.addEventListener("input", () => {
            if (!edit) return;
            edit.dirty = textarea.value !== edit.original;
            paintMirror();
            autosize();
            postState();
        });
        textarea.addEventListener("keydown", (ev) => {
            if (ev.key !== "Escape" || ev.isComposing || ev.keyCode === 229) return;
            ev.preventDefault();
            cancelQuickEdit();
        });
        textarea.addEventListener("focus", postState);
        textarea.addEventListener("blur", postState);
    }

    function focusQuickEdit() {
        if (!edit) return false;
        edit.wrapper.scrollIntoView({ block: "nearest" });
        edit.textarea.focus({ preventScroll: true });
        postState();
        return true;
    }

    function saveQuickEdit() {
        if (!edit || edit.refused || edit.saving) return;
        const replacement = edit.textarea.value;
        if (replacement === edit.original) { close(); return; }
        edit.saving = true;
        post("blockEdit", { start: edit.start, end: edit.end, original: edit.original, replacement });
    }

    function cancelQuickEdit() {
        close();
    }

    // result: { ok, reason }. Only a conflict refuses further saves; an
    // encoding or write failure leaves the edit open to change and retry.
    function resolveQuickEdit(result) {
        if (!edit) return;
        edit.saving = false;
        if (result && result.ok) { close(); return; }
        const reason = result && (result.reason === "encoding" || result.reason === "write")
            ? result.reason : "conflict";
        if (reason === "conflict") edit.refused = true;
        setNotice(reason);
    }

    function noticeQuickEdit(kind) {
        setNotice(kind);
    }

    window.addEventListener("mousemove", (ev) => {
        pointer = { x: ev.clientX, y: ev.clientY };
    }, { capture: true, passive: true });
    document.documentElement.addEventListener("mouseleave", () => { pointer = null; });
    window.addEventListener("focus", postState);
    window.addEventListener("blur", postState);

    document.addEventListener("contextmenu", (ev) => {
        contextTarget = ev.target;
        const hit = blockFor(ev.target);
        const range = hit && rangeOf(hit.block);
        const label = range ? core.blockInfo(hit.block.tagName, hit.block.classList).label : null;
        let line = null;
        if (range) line = range.start;
        else if (hit) line = nearestLine(hit.el);
        else if (edit && edit.wrapper.contains(elementOf(ev.target))) line = edit.start;
        post("contextBlock", {
            label,
            editable: !!range && !edit && !api.isReadOnly() && !loneCR,
            line: Number.isInteger(line) ? line : null
        });
    }, true);

    // A render rebuilds #content, taking the editor with it; close the edit
    // first so nothing stale survives even if the render bails early.
    const baseRender = api.render;
    function render(payload) {
        if (edit) close();
        loneCR = core.hasLoneCR(payload && payload.source);
        renderedSource = payload && typeof payload.source === "string" ? payload.source : null;
        return baseRender(payload);
    }

    Object.assign(api, {
        render,
        beginQuickEdit,
        focusQuickEdit,
        saveQuickEdit,
        cancelQuickEdit,
        resolveQuickEdit,
        noticeQuickEdit
    });
})();
