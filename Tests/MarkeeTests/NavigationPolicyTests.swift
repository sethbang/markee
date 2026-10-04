import XCTest
@testable import Markee

final class NavigationPolicyTests: XCTestCase {
    private let template = URL(string: "markee-app://app/template.html")!

    private func decide(_ s: String, main: Bool = true, link: Bool = true) -> NavigationDecision {
        NavigationPolicy.decide(url: URL(string: s)!, isMainFrame: main, isLinkActivated: link)
    }

    func test_templateLoadIsTheOnlyAllowedMainFrameLoad() {
        XCTAssertEqual(decide("markee-app://app/template.html", link: false), .allow)
        XCTAssertEqual(decide("markee-app://app/template.html#x", link: false), .allow)
        XCTAssertEqual(decide("markee-app://app/theme.css", link: false), .cancel)
        XCTAssertEqual(decide("markee-doc://doc/a.svg", link: false), .cancel)
        XCTAssertEqual(decide("https://evil.example/", link: false), .cancel)
        XCTAssertEqual(decide("about:blank", link: false), .cancel)
    }

    func test_clickedWorkspaceFilesOpenOutsideThePreview() {
        XCTAssertEqual(decide("markee-doc://doc/docs/arch.svg"),
                       .openWorkspaceFile(path: "/docs/arch.svg"))
        XCTAssertEqual(decide("markee-doc://doc/notes.md"), .cancel)
    }

    func test_externalAndBlockedSchemes() {
        let url = URL(string: "https://example.com")!
        XCTAssertEqual(decide("https://example.com"), .openExternally(url))
        XCTAssertEqual(decide("javascript:alert(1)"), .blockedScheme("javascript"))
        XCTAssertEqual(decide("file:///etc/passwd"), .blockedScheme("file"))
        XCTAssertEqual(decide("markee-app://app/template.html"), .cancel)
    }

    func test_subframesMayOnlyLoadAbout() {
        XCTAssertEqual(decide("about:blank", main: false, link: false), .allow)
        XCTAssertEqual(decide("markee-doc://doc/x.html", main: false, link: false), .cancel)
        XCTAssertEqual(decide("https://evil.example", main: false, link: false), .cancel)
    }

    func test_onlyViewableFileTypesOpenInTheirApp() {
        XCTAssertTrue(NavigationPolicy.isSafeToOpen(URL(fileURLWithPath: "/w/a.png")))
        XCTAssertTrue(NavigationPolicy.isSafeToOpen(URL(fileURLWithPath: "/w/a.pdf")))
        XCTAssertTrue(NavigationPolicy.isSafeToOpen(URL(fileURLWithPath: "/w/a.txt")))
        XCTAssertFalse(NavigationPolicy.isSafeToOpen(URL(fileURLWithPath: "/w/run.command")))
        XCTAssertFalse(NavigationPolicy.isSafeToOpen(URL(fileURLWithPath: "/w/run.sh")))
        XCTAssertFalse(NavigationPolicy.isSafeToOpen(URL(fileURLWithPath: "/w/Evil.app")))
        XCTAssertFalse(NavigationPolicy.isSafeToOpen(URL(fileURLWithPath: "/w/page.html")))
    }
}
