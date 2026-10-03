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
        return Data("""
        {
          "tag_name": "v0.5.0",
          "html_url": "https://github.com/sethbang/markee/releases/tag/v0.5.0",
          "body": "Release notes here.",
          "assets": [ \(asset) ]
        }
        """.utf8)
    }

    func test_parsesValidPayload() {
        let release = GitHubRelease(json: payload(includeZip: true))
        XCTAssertNotNil(release)
        XCTAssertEqual(release?.tagName, "v0.5.0")
        XCTAssertEqual(release?.version, AppVersion("0.5.0"))
        XCTAssertEqual(release?.zipURL.absoluteString, "https://example.com/dl/Markee.app.zip")
        XCTAssertEqual(release?.notes, "Release notes here.")
        XCTAssertEqual(release?.pageURL.absoluteString,
                       "https://github.com/sethbang/markee/releases/tag/v0.5.0")
    }

    func test_nilWhenZipAssetMissing() {
        XCTAssertNil(GitHubRelease(json: payload(includeZip: false)))
    }

    func test_nilWhenMalformedJSON() {
        XCTAssertNil(GitHubRelease(json: Data("not json".utf8)))
    }

    func test_notesEmptyWhenBodyMissing() {
        let json = Data("""
        {
          "tag_name": "v0.5.0",
          "html_url": "https://github.com/sethbang/markee/releases/tag/v0.5.0",
          "assets": [
            { "name": "Markee.app.zip",
              "browser_download_url": "https://example.com/dl/Markee.app.zip" }
          ]
        }
        """.utf8)
        let release = GitHubRelease(json: json)
        XCTAssertNotNil(release)
        XCTAssertEqual(release?.notes, "")
    }
}

/// Staged-bundle validation: the gate between a downloaded zip and replacing
/// the running app.
final class StagedBundleValidationTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkeeStagedBundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A minimal Markee.app; ad-hoc signed when `sign` is set.
    private func makeBundle(id: String = "com.markee.test", version: String = "2.0.0", sign: Bool) throws -> URL {
        let app = dir.appendingPathComponent("Markee.app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"),
                                         to: macos.appendingPathComponent("Markee"))
        let plist: NSDictionary = [
            "CFBundleIdentifier": id,
            "CFBundleExecutable": "Markee",
            "CFBundleShortVersionString": version,
            "CFBundlePackageType": "APPL",
        ]
        plist.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        if sign {
            try Updater.runProcess("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        }
        return app
    }

    func test_productionRequirementRejectsAdHocBundle() throws {
        let app = try makeBundle(id: "com.markee.preview", sign: true)
        XCTAssertThrowsError(try Updater.validateStagedBundle(app, expectedVersion: AppVersion("2.0.0")!))
    }

    /// Guards the production requirement string itself: a real Developer-ID
    /// release must pass, or every user's update would be refused.
    func test_productionRequirementAcceptsSignedRelease() throws {
        let installed = URL(fileURLWithPath: "/Applications/Markee.app")
        guard let info = NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist")),
              let v = info["CFBundleShortVersionString"] as? String, let version = AppVersion(v),
              (try? Updater.runProcess("/usr/bin/codesign", ["--verify", "-R=anchor apple generic", installed.path])) != nil
        else { throw XCTSkip("no Developer-ID-signed Markee in /Applications") }
        XCTAssertNoThrow(try Updater.validateStagedBundle(installed, expectedVersion: version))
    }

    func test_unsignedBundleIsRejected() throws {
        let app = try makeBundle(sign: false)
        XCTAssertThrowsError(try Updater.validateStagedBundle(
            app, expectedVersion: AppVersion("2.0.0")!,
            bundleID: "com.markee.test", requirement: #"identifier "com.markee.test""#))
    }

    func test_signedBundleMatchingRequirementIsAccepted() throws {
        let app = try makeBundle(sign: true)
        XCTAssertNoThrow(try Updater.validateStagedBundle(
            app, expectedVersion: AppVersion("2.0.0")!,
            bundleID: "com.markee.test", requirement: #"identifier "com.markee.test""#))
    }

    func test_versionOrBundleIDMismatchIsRejected() throws {
        let app = try makeBundle(sign: true)
        let req = #"identifier "com.markee.test""#
        XCTAssertThrowsError(try Updater.validateStagedBundle(
            app, expectedVersion: AppVersion("2.0.1")!, bundleID: "com.markee.test", requirement: req))
        XCTAssertThrowsError(try Updater.validateStagedBundle(
            app, expectedVersion: AppVersion("2.0.0")!, bundleID: "com.other", requirement: req))
    }

    /// Tampering after signing must fail strict validation.
    func test_modifiedSignedBundleIsRejected() throws {
        let app = try makeBundle(sign: true)
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        let plist = NSMutableDictionary(contentsOf: plistURL)!
        plist["Injected"] = "yes"
        plist.write(to: plistURL, atomically: true)
        XCTAssertThrowsError(try Updater.validateStagedBundle(
            app, expectedVersion: AppVersion("2.0.0")!,
            bundleID: "com.markee.test", requirement: #"identifier "com.markee.test""#))
    }
}
