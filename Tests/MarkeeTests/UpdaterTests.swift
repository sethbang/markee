import XCTest
@testable import Markee

final class AppVersionTests: XCTestCase {
    func test_parsesDottedNumbers() {
        XCTAssertEqual(AppVersion("0.4.0")?.components, [0, 4, 0])
    }

    func test_toleratesLeadingV() {
        XCTAssertEqual(AppVersion("v1.2.3")?.components, [1, 2, 3])
    }

    func test_dropsPrereleaseSuffix() {
        XCTAssertEqual(AppVersion("0.5.0-beta")?.components, [0, 5, 0])
    }

    func test_newerComparesGreater() {
        XCTAssertTrue(AppVersion("0.5.0")! > AppVersion("0.4.0")!)
        XCTAssertTrue(AppVersion("0.4.1")! > AppVersion("0.4.0")!)
        XCTAssertTrue(AppVersion("1.0.0")! > AppVersion("0.9.9")!)
    }

    func test_missingTrailingComponentsTreatedAsZero() {
        XCTAssertEqual(AppVersion("0.4"), AppVersion("0.4.0"))
        XCTAssertFalse(AppVersion("0.4")! > AppVersion("0.4.0")!)
    }

    func test_rejectsNonNumeric() {
        XCTAssertNil(AppVersion("not-a-version"))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1.x.0"))
    }
}

final class GitHubReleaseTests: XCTestCase {
    private func payload(includeZip: Bool) -> Data {
        let asset = includeZip
            ? """
              { "name": "Markee.app.zip",
                "browser_download_url": "https://example.com/dl/Markee.app.zip" }
              """
            : """
              { "name": "SomethingElse.txt",
                "browser_download_url": "https://example.com/dl/other.txt" }
              """
        return """
        {
          "tag_name": "v0.5.0",
          "html_url": "https://github.com/sethbang/markee/releases/tag/v0.5.0",
          "body": "Release notes here.",
          "assets": [ \(asset) ]
        }
        """.data(using: .utf8)!
    }

    func test_parsesValidPayload() {
        let release = GitHubRelease(json: payload(includeZip: true))
        XCTAssertNotNil(release)
        XCTAssertEqual(release?.tagName, "v0.5.0")
        XCTAssertEqual(release?.version, AppVersion("0.5.0"))
        XCTAssertEqual(release?.zipURL.absoluteString, "https://example.com/dl/Markee.app.zip")
        XCTAssertEqual(release?.notes, "Release notes here.")
    }

    func test_nilWhenZipAssetMissing() {
        XCTAssertNil(GitHubRelease(json: payload(includeZip: false)))
    }

    func test_nilWhenMalformedJSON() {
        XCTAssertNil(GitHubRelease(json: Data("not json".utf8)))
    }
}
