import Foundation

/// A message `app.js` posts over `webkit.messageHandlers.markee`, decoded from
/// its `{kind, …}` body. Parsing is pure so it unit-tests without WebKit; the
/// trust check (main frame, template origin) stays in
/// `PreviewController.userContentController`, the single entry point.
enum BridgeMessage: Equatable {
    case ready
    case outline([OutlineEntry])
    case error(String?)
    case taskToggle(line: Int, checked: Bool)
    case scrollSection(id: String?)
    case copyText(String, note: String)
    case docStats(words: Int, minutes: Int)
    case findResult(current: Int, total: Int)
    case navigate(path: String, fragment: String, newWindow: Bool)

    /// Nil for an unknown kind or a message missing a required field.
    init?(body: Any) {
        guard let body = body as? [String: Any], let kind = body["kind"] as? String else { return nil }
        switch kind {
        case "ready":
            self = .ready
        case "outline":
            let items = body["items"] as? [[String: Any]] ?? []
            self = .outline(items.compactMap { d in
                guard let id = d["id"] as? String,
                      let level = d["level"] as? Int,
                      let title = d["title"] as? String else { return nil }
                return OutlineEntry(id: id, level: level, title: title, line: d["line"] as? Int)
            })
        case "error":
            self = .error(body["message"] as? String)
        case "taskToggle":
            guard let line = body["line"] as? Int, let checked = body["checked"] as? Bool else { return nil }
            self = .taskToggle(line: line, checked: checked)
        case "scrollSection":
            self = .scrollSection(id: body["id"] as? String)
        case "copyText":
            guard let text = body["text"] as? String else { return nil }
            self = .copyText(text, note: body["note"] as? String ?? "Copied")
        case "docStats":
            self = .docStats(words: body["words"] as? Int ?? 0, minutes: body["minutes"] as? Int ?? 1)
        case "findResult":
            self = .findResult(current: body["current"] as? Int ?? 0, total: body["total"] as? Int ?? 0)
        case "navigate":
            guard let path = body["path"] as? String else { return nil }
            self = .navigate(path: path,
                             fragment: body["fragment"] as? String ?? "",
                             newWindow: body["newWindow"] as? Bool ?? false)
        default:
            return nil
        }
    }
}
