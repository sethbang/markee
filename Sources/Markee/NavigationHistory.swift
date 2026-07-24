import Foundation

/// Back/forward stack of document URLs. Pure value type — the authoritative
/// model behind the titlebar chevrons and ⌘[/⌘].
struct NavigationHistory {
    private(set) var stack: [URL]
    private(set) var index: Int

    init(initial: URL) {
        self.stack = [initial.standardizedFileURL]
        self.index = 0
    }

    var current: URL { stack[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < stack.count - 1 }

    /// Append `url`, truncating any forward entries. No-op if it equals current.
    mutating func push(_ url: URL) {
        let u = url.standardizedFileURL
        if u == stack[index] { return }
        if index < stack.count - 1 { stack.removeSubrange((index + 1)...) }
        stack.append(u)
        index = stack.count - 1
    }

    mutating func back() -> URL? {
        guard canGoBack else { return nil }
        index -= 1
        return stack[index]
    }

    mutating func forward() -> URL? {
        guard canGoForward else { return nil }
        index += 1
        return stack[index]
    }
}
