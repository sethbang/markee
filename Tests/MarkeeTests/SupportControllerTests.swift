import XCTest
@testable import Markee

@MainActor
final class SupportControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var clock: Date!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SupportControllerTests")!
        defaults.removePersistentDomain(forName: "SupportControllerTests")
        clock = Date(timeIntervalSince1970: 1_750_000_000)
    }

    private func makeController(configured: Bool = true) -> SupportController {
        SupportController(defaults: defaults, now: { self.clock }, isConfigured: { configured })
    }

    private func advance(days: Double) {
        clock = clock.addingTimeInterval(days * 24 * 3600)
    }

    func test_registerLaunchStampsFirstLaunchOnceAndCounts() {
        let c = makeController()
        c.registerLaunch()
        let first = defaults.object(forKey: "support.firstLaunchDate") as? Date
        XCTAssertEqual(first, clock)
        advance(days: 1)
        c.registerLaunch()
        XCTAssertEqual(defaults.object(forKey: "support.firstLaunchDate") as? Date, first)
        XCTAssertEqual(defaults.integer(forKey: "support.launchCount"), 2)
    }

    func test_supportDocTriggerStampsWhenConsumed() {
        let c = makeController()
        for _ in 0..<5 { c.registerLaunch() }
        advance(days: 14)
        XCTAssertTrue(c.consumeSupportDocTrigger())
        XCTAssertFalse(c.consumeSupportDocTrigger())
        advance(days: 30)
        XCTAssertTrue(c.consumeSupportDocTrigger())
    }

    func test_markSupporterPersistsAndSilencesEverything() {
        let c = makeController()
        for _ in 0..<5 { c.registerLaunch() }
        advance(days: 14)
        c.registerLaunch()
        c.markSupporter(key: "MARKEE-TEST-KEY", activationID: "act-1")
        XCTAssertTrue(c.isSupporter)
        XCTAssertFalse(c.consumeSupportDocTrigger())
        XCTAssertEqual(defaults.string(forKey: "support.licenseKey"), "MARKEE-TEST-KEY")
        XCTAssertEqual(defaults.string(forKey: "support.activationId"), "act-1")

        let reloaded = makeController()
        XCTAssertTrue(reloaded.isSupporter)
    }

    func test_corruptDefaultsDegradeToFreshInstall() {
        defaults.set("garbage", forKey: "support.firstLaunchDate")
        let c = makeController()
        c.registerLaunch()
        XCTAssertFalse(c.consumeSupportDocTrigger())
        XCTAssertEqual(defaults.object(forKey: "support.firstLaunchDate") as? Date, clock)
    }

    func test_unconfiguredBuildShowsNoNudgesEvenPastGrace() {
        let c = makeController(configured: false)
        for _ in 0..<5 { c.registerLaunch() }
        advance(days: 14)
        c.registerLaunch()
        XCTAssertFalse(c.consumeSupportDocTrigger())
    }

    func test_forceNudgesShowsNudgesImmediatelyEvenUnconfigured() {
        let c = SupportController(defaults: defaults, now: { self.clock },
                                  isConfigured: { false }, forceNudges: true)
        c.registerLaunch()
        XCTAssertTrue(c.consumeSupportDocTrigger())
    }

    func test_heartHiddenInUnconfiguredBuild() {
        let c = makeController(configured: false)
        XCTAssertFalse(c.showSupportButton)
    }

    func test_heartShownForNonSupporterWhenConfigured() {
        let c = makeController()
        XCTAssertTrue(c.showSupportButton)
    }

    func test_heartClearedByMarkSupporter() {
        let c = makeController()
        c.markSupporter(key: "K", activationID: "A")
        XCTAssertFalse(c.showSupportButton)
    }

    // The regression guard for the dev toggle: flipping supporter back off must
    // bring the heart back, not leave it stale-hidden.
    func test_heartReturnsWhenSupporterToggledOff() {
        let c = makeController()
        c.markSupporter(key: "K", activationID: "A")
        XCTAssertFalse(c.showSupportButton)
        c.setSupporter(false)
        XCTAssertTrue(c.showSupportButton)
        XCTAssertFalse(c.isSupporter)
    }

    func test_setSupporterTruePersistsAcrossReload() {
        let c = makeController()
        c.setSupporter(true)
        XCTAssertTrue(makeController().isSupporter)
    }

    func test_nudgesInactiveInUnconfiguredBuild() {
        XCTAssertFalse(makeController(configured: false).nudgesActive)
    }

    func test_nudgesActiveWhenConfigured() {
        XCTAssertTrue(makeController().nudgesActive)
    }

    // The env override is ephemeral: it must not write through to defaults, so
    // unsetting it returns the install to its real state.
    func test_forceSupporterOverridesWithoutPersisting() {
        let c = SupportController(defaults: defaults, now: { self.clock },
                                  isConfigured: { true }, forceSupporter: true)
        XCTAssertTrue(c.isSupporter)
        XCTAssertFalse(c.showSupportButton)
        XCTAssertFalse(defaults.bool(forKey: "support.active"))
    }

    func test_resetNudgeTimersRearmsTheSupportDoc() {
        let c = makeController()
        for _ in 0..<5 { c.registerLaunch() }
        advance(days: 14)
        XCTAssertTrue(c.consumeSupportDocTrigger())
        XCTAssertFalse(c.consumeSupportDocTrigger())
        c.resetNudgeTimers()
        for _ in 0..<5 { c.registerLaunch() }
        advance(days: 14)
        XCTAssertTrue(c.consumeSupportDocTrigger())
    }
}

final class SupportConfigTests: XCTestCase {
    func test_orgIDFallsBackToProductionWhenEnvUnset() {
        XCTAssertEqual(SupportConfig.resolveOrganizationID(env: [:]),
                       SupportConfig.productionOrganizationID)
    }

    func test_orgIDFallsBackToProductionWhenEnvEmpty() {
        XCTAssertEqual(SupportConfig.resolveOrganizationID(env: ["MARKEE_POLAR_ORG_ID": ""]),
                       SupportConfig.productionOrganizationID)
    }

    func test_orgIDUsesEnvOverrideWhenSet() {
        XCTAssertEqual(
            SupportConfig.resolveOrganizationID(env: ["MARKEE_POLAR_ORG_ID": "sandbox-org-id"]),
            "sandbox-org-id")
    }

    func test_baseURLFallsBackToProductionWhenEnvUnset() {
        XCTAssertEqual(SupportConfig.resolveBaseURL(env: [:]), "https://api.polar.sh")
    }

    func test_baseURLUsesEnvOverrideWhenSet() {
        XCTAssertEqual(
            SupportConfig.resolveBaseURL(env: ["MARKEE_POLAR_BASE_URL": "https://sandbox-api.polar.sh"]),
            "https://sandbox-api.polar.sh")
    }

    func test_baseURLStripsTrailingSlash() {
        XCTAssertEqual(
            SupportConfig.resolveBaseURL(env: ["MARKEE_POLAR_BASE_URL": "https://sandbox-api.polar.sh/"]),
            "https://sandbox-api.polar.sh")
    }

    func test_forceNudgesOffByDefault() {
        XCTAssertFalse(SupportConfig.resolveForceNudges(env: [:]))
        XCTAssertFalse(SupportConfig.resolveForceNudges(env: ["MARKEE_FORCE_NUDGES": "0"]))
    }

    func test_forceNudgesOnForTruthyValues() {
        XCTAssertTrue(SupportConfig.resolveForceNudges(env: ["MARKEE_FORCE_NUDGES": "1"]))
        XCTAssertTrue(SupportConfig.resolveForceNudges(env: ["MARKEE_FORCE_NUDGES": "true"]))
    }

    func test_devToolsOffByDefault() {
        XCTAssertFalse(SupportConfig.resolveDevTools(env: [:]))
        XCTAssertFalse(SupportConfig.resolveDevTools(env: ["MARKEE_DEV_TOOLS": "0"]))
        XCTAssertFalse(SupportConfig.resolveDevTools(env: ["MARKEE_DEV_TOOLS": ""]))
    }

    func test_devToolsOnForTruthyValues() {
        XCTAssertTrue(SupportConfig.resolveDevTools(env: ["MARKEE_DEV_TOOLS": "1"]))
        XCTAssertTrue(SupportConfig.resolveDevTools(env: ["MARKEE_DEV_TOOLS": "true"]))
    }

    func test_forceSupporterOffByDefault() {
        XCTAssertFalse(SupportConfig.resolveForceSupporter(env: [:]))
        XCTAssertFalse(SupportConfig.resolveForceSupporter(env: ["MARKEE_FORCE_SUPPORTER": "0"]))
    }

    func test_forceSupporterOnForTruthyValues() {
        XCTAssertTrue(SupportConfig.resolveForceSupporter(env: ["MARKEE_FORCE_SUPPORTER": "1"]))
        XCTAssertTrue(SupportConfig.resolveForceSupporter(env: ["MARKEE_FORCE_SUPPORTER": "true"]))
    }
}
