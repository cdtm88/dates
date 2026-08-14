import XCTest
@testable import Dates

/// Phase 07 — the appearance setting: Light on first launch (UI-01), persisted per device.
@MainActor
final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "dates.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testTheFirstLaunchAppearanceIsLightNotSystem() {
        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .light,
                       "the PRD wants Light as the first-launch default")
    }

    func testAppearanceSurvivesANewSettingsInstance() {
        AppSettings(defaults: defaults).appearance = .dark
        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .dark)
    }

    func testAnUnrecognisedStoredValueFallsBackToLight() {
        defaults.set("sepia", forKey: "settings.appearance")
        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .light)
    }

    func testEachAppearanceMapsToItsColourScheme() {
        XCTAssertEqual(Appearance.light.colorScheme, .light)
        XCTAssertEqual(Appearance.dark.colorScheme, .dark)
        XCTAssertNil(Appearance.system.colorScheme, "system means the device decides")
    }
}
