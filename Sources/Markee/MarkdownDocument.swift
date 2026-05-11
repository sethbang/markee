import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown: UTType = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    static let commonmark: UTType = UTType(importedAs: "org.commonmark.markdown", conformingTo: .plainText)
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.markdown, .commonmark, .plainText]
    }

    static var writableContentTypes: [UTType] { [] }

    init() {}

    init(configuration: ReadConfiguration) throws {
        // We don't actually need the contents here — PreviewView re-reads from disk
        // via its own FileWatcher. DocumentGroup still requires init(configuration:).
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}
