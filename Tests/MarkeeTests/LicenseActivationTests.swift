import XCTest
@testable import Markee

final class LicenseActivationParseTests: XCTestCase {
    private func body(status: String, id: String = "act-123") -> Data {
        Data(#"{"id": "\#(id)", "license_key": {"status": "\#(status)", "limit_activations": 3}}"#.utf8)
    }

    func test_grantedReturnsActivationID() {
        XCTAssertEqual(
            LicenseActivation.parseActivationResponse(status: 200, data: body(status: "granted")),
            .activated(activationID: "act-123"))
    }

    func test_revokedIsInvalid() {
        let result = LicenseActivation.parseActivationResponse(status: 200, data: body(status: "revoked"))
        guard case .invalid = result else { return XCTFail("expected .invalid, got \(result)") }
    }

    func test_disabledIsInvalid() {
        let result = LicenseActivation.parseActivationResponse(status: 200, data: body(status: "disabled"))
        guard case .invalid = result else { return XCTFail("expected .invalid, got \(result)") }
    }

    // A future/unknown benign status must not read as "your key is bad".
    func test_unknownStatusIsFailureNotInvalid() {
        let result = LicenseActivation.parseActivationResponse(status: 200, data: body(status: "pending"))
        guard case .failure = result else { return XCTFail("expected .failure, got \(result)") }
    }

    func test_missingActivationIDIsFailure() {
        let data = Data(#"{"license_key": {"status": "granted"}}"#.utf8)
        let result = LicenseActivation.parseActivationResponse(status: 200, data: data)
        guard case .failure = result else { return XCTFail("expected .failure, got \(result)") }
    }

    func test_garbledSuccessBodyIsFailureNotInvalid() {
        let result = LicenseActivation.parseActivationResponse(status: 200, data: Data("not json".utf8))
        guard case .failure = result else { return XCTFail("expected .failure, got \(result)") }
    }

    func test_unknownKeyIsInvalid() {
        let result = LicenseActivation.parseActivationResponse(status: 404, data: Data())
        guard case .invalid = result else { return XCTFail("expected .invalid, got \(result)") }
    }

    // 422 on activate means WE built the request wrong, not that the key is bad.
    // This deliberately diverges from the deleted validate parser.
    func test_malformedRequestIsFailureNotInvalid() {
        let result = LicenseActivation.parseActivationResponse(status: 422, data: Data())
        guard case .failure = result else { return XCTFail("expected .failure, got \(result)") }
    }

    // An unclassified 4xx is most likely the activation limit, but not provably
    // so — with no body we must not invent a cause.
    func test_otherClientErrorIsLimitReachedWithNoDetail() {
        XCTAssertEqual(
            LicenseActivation.parseActivationResponse(status: 403, data: Data()),
            .limitReached(detail: nil))
    }

    // When Polar explains itself, quote it rather than assert "already on 3 Macs".
    func test_limitReachedCarriesPolarsOwnDetail() {
        let data = Data(#"{"detail": "License key activation limit reached."}"#.utf8)
        XCTAssertEqual(
            LicenseActivation.parseActivationResponse(status: 403, data: data),
            .limitReached(detail: "License key activation limit reached."))
    }

    func test_limitReachedFallsBackToErrorField() {
        let data = Data(#"{"error": "NotPermitted"}"#.utf8)
        XCTAssertEqual(
            LicenseActivation.parseActivationResponse(status: 403, data: data),
            .limitReached(detail: "NotPermitted"))
    }

    // Verbatim body Polar returns at the ceiling, captured from the sandbox.
    func test_realPolarLimitBodyIsClassifiedAndQuoted() {
        let data = Data(#"{"error":"NotPermitted","detail":"License key activation limit already reached"}"#.utf8)
        XCTAssertEqual(
            LicenseActivation.parseActivationResponse(status: 403, data: data),
            .limitReached(detail: "License key activation limit already reached"))
    }

    // A rate-limit is transient. Reporting it as "already active on 3 Macs"
    // would send a paying customer to the portal to delete a live activation.
    func test_rateLimitIsFailureNotLimitReached() {
        let result = LicenseActivation.parseActivationResponse(status: 429, data: Data())
        guard case .failure = result else { return XCTFail("expected .failure, got \(result)") }
    }

    func test_unclassifiedClientErrorIsFailureQuotingPolar() {
        let data = Data(#"{"detail": "Something else went wrong"}"#.utf8)
        XCTAssertEqual(
            LicenseActivation.parseActivationResponse(status: 409, data: data),
            .failure(message: "Something else went wrong"))
    }

    func test_serverErrorIsFailureNotInvalid() {
        let result = LicenseActivation.parseActivationResponse(status: 503, data: Data())
        guard case .failure = result else { return XCTFail("expected .failure, got \(result)") }
    }
}

final class DeviceLabelTests: XCTestCase {
    func test_usesHostName() {
        XCTAssertEqual(LicenseActivation.deviceLabel(hostName: "Seth's MacBook Pro"), "Seth's MacBook Pro")
    }

    func test_fallsBackWhenNil() {
        XCTAssertEqual(LicenseActivation.deviceLabel(hostName: nil), "Mac")
    }

    func test_fallsBackWhenBlank() {
        XCTAssertEqual(LicenseActivation.deviceLabel(hostName: "   "), "Mac")
    }
}
