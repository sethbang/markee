import XCTest
@testable import Markee

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func makeStore() -> SettingsStore {
        let defaults = UserDefaults(suiteName: "markee.settings.test")!
        defaults.removePersistentDomain(forName: "markee.settings.test")
        return SettingsStore(defaults: defaults)
    }

    func test_themeDefaultsToSystem() {
        XCTAssertEqual(makeStore().themeOverride, .system)
    }

    func test_themeRoundTripsThroughDefaults() {
        let s = makeStore()
        s.themeOverride = .dark
        XCTAssertEqual(s.themeOverride, .dark)
        XCTAssertEqual(s.defaults.string(forKey: "MarkeeThemeOverride"), "dark")
    }

    func test_unknownThemeStringFallsBackToSystem() {
        let s = makeStore()
        s.defaults.set("chartreuse", forKey: "MarkeeThemeOverride")
        XCTAssertEqual(s.themeOverride, .system)
    }

    func test_baseFontClampsToRange() {
        let s = makeStore()
        s.baseFontSize = 2
        XCTAssertEqual(s.baseFontSize, SettingsStore.fontRange.lowerBound)
        s.baseFontSize = 999
        XCTAssertEqual(s.baseFontSize, SettingsStore.fontRange.upperBound)
    }

    func test_accentValidationRejectsUnsafeAndKeepsHex() {
        let s = makeStore()
        s.accentHex = "#A85428"
        XCTAssertEqual(s.accentHex, "#A85428")
        s.accentHex = "javascript:evil"
        XCTAssertEqual(s.accentHex, "")
    }

    func test_payloadReflectsCurrentState() {
        let s = makeStore()
        s.themeOverride = .light
        s.accentHex = "#112233"
        s.baseFontSize = 16
        let p = s.payload()
        XCTAssertEqual(p["theme"] as? String, "light")
        XCTAssertEqual(p["accent"] as? String, "#112233")
        XCTAssertEqual(p["baseFont"] as? Double, 16)
        XCTAssertEqual(p["userCSS"] as? String, "")
    }

    func test_changePostsNotification() {
        let s = makeStore()
        let exp = expectation(forNotification: .settingsDidChange, object: nil, handler: nil)
        s.accentHex = "#445566"
        wait(for: [exp], timeout: 1)
    }

    func test_updateCheckDefaultsOnAndPersists() {
        let s = makeStore()
        XCTAssertTrue(s.updateCheckEnabled)   // default on when unset
        s.updateCheckEnabled = false
        XCTAssertEqual(s.defaults.object(forKey: "MarkeeUpdateCheckEnabled") as? Bool, false)
    }
}
