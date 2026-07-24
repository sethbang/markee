import XCTest
import AppKit
@testable import Markee

@MainActor
final class PrintPDFTests: XCTestCase {
    func test_pdfPrintInfoSavesToURLWithSaveDisposition() {
        let url = URL(fileURLWithPath: "/tmp/markee-test.pdf")
        let info = PreviewController.pdfPrintInfo(savingTo: url)
        XCTAssertEqual(info.jobDisposition, .save)
        let saved = info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue]
        XCTAssertEqual(saved as? URL, url)
    }

    func test_pdfPrintInfoUsesPositiveMargins() {
        let info = PreviewController.pdfPrintInfo(savingTo: URL(fileURLWithPath: "/tmp/x.pdf"))
        XCTAssertGreaterThan(info.topMargin, 0)
        XCTAssertGreaterThan(info.leftMargin, 0)
    }
}
