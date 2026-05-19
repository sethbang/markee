import XCTest
import WebKit
@testable import MarkeeKit

@MainActor
final class WebRendererTests: XCTestCase {
    func test_constructsWithAWebView() {
        let renderer = WebRenderer(docRoot: URL(fileURLWithPath: "/tmp"))
        XCTAssertNotNil(renderer.webView)
    }

    func test_loadTemplateDoesNotCrash() {
        let renderer = WebRenderer(docRoot: URL(fileURLWithPath: "/tmp"))
        renderer.loadTemplate()
        XCTAssertNotNil(renderer.webView.configuration)
    }

    func test_deallocatesAfterLastReference() {
        weak var weakRenderer: WebRenderer?
        autoreleasepool {
            let renderer = WebRenderer(docRoot: URL(fileURLWithPath: "/tmp"))
            weakRenderer = renderer
            XCTAssertNotNil(weakRenderer)
        }
        // Drain autorelease pools / let WebKit settle.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(weakRenderer,
                     "WebRenderer must not be retained by its own WKWebView's message handler")
    }
}
