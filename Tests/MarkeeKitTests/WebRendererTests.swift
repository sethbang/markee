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
}
