import XCTest

/// End-to-end smoke of the flows the manual acceptance checklist walks through
/// (docs/xcode-handover.md): first launch, creating a date, leap-day handling, and the
/// queue read-out in Settings.
///
/// The app launches with `--uitest`, so the store is in-memory and every test starts from
/// the empty state. The notification permission prompt is answered when it appears; the
/// system remembers the grant per install, so only the first test run on a fresh simulator
/// sees it.
final class DatesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - First launch

    func testFirstLaunchShowsTheEmptyState() {
        XCTAssertTrue(app.staticTexts["No dates yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add a date"].firstMatch.isEnabled)

        // All three entry routes are live now that Phase 05 has landed (LIST-06).
        XCTAssertTrue(app.buttons["Import from Contacts"].isEnabled)
        XCTAssertTrue(app.buttons["Import a CSV"].isEnabled)
    }

    // MARK: - Creating a date

    func testAddingADateShowsItInTheList() {
        addEvent(named: "Ada Lovelace")

        XCTAssertTrue(app.staticTexts["Ada Lovelace"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No dates yet"].exists)
    }

    func testSaveIsDisabledUntilANameIsEntered() {
        app.buttons["Add a date"].firstMatch.tap()

        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertFalse(save.isEnabled, "an empty name must not be savable")

        let nameField = app.textFields["Name"]
        nameField.tap()
        nameField.typeText("Grace Hopper")
        XCTAssertTrue(save.isEnabled)

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["No dates yet"].waitForExistence(timeout: 10))
    }

    // MARK: - Leap day (DATA-04)

    func testLeapDayIsOfferableWhenTheYearIsUnknown() {
        app.buttons["Add a date"].firstMatch.tap()
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 10))

        pickerButton(titled: "Month").tap()
        XCTAssertTrue(scrollToMenuOption("February"))
        app.buttons["February"].tap()

        // With the year toggle off, 29 February must be offerable.
        let dayPicker = pickerButton(titled: "Day")
        dayPicker.tap()
        XCTAssertTrue(scrollToMenuOption("29"), "February without a year must offer day 29")
        XCTAssertFalse(app.buttons["30"].isHittable, "February must not offer day 30")
        app.buttons["29"].tap()
        XCTAssertTrue(dayPicker.label.contains("29"))

        // Picking a known non-leap year clamps the day back to 28. The year picker is
        // always visible and defaults to "Not set".
        let yearPicker = pickerButton(titled: "Year")
        XCTAssertTrue(yearPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(yearPicker.label.contains("Not set"), "the year must default to unset")
        yearPicker.tap()
        XCTAssertTrue(scrollToMenuOption("2023"))
        app.buttons["2023"].tap()
        XCTAssertTrue(pickerButton(titled: "Day").label.contains("28"), "29 February 2023 does not exist")
    }

    // MARK: - Settings (NOTIF-04, NOTIF-09)

    func testSettingsShowsTheReminderQueue() {
        addEvent(named: "Queue Check")
        XCTAssertTrue(app.staticTexts["Queue Check"].waitForExistence(timeout: 10))

        openSettingsFromMenu()

        XCTAssertTrue(settingsHeader.waitForExistence(timeout: 10))

        // The appearance control defaults to Light on a fresh install (UI-01, Phase 07).
        let lightSegment = app.buttons["Light"]
        XCTAssertTrue(lightSegment.exists)
        XCTAssertTrue(lightSegment.isSelected, "Light must be the first-launch default")

        // The queue read-out is a footer sentence now, not a diagnostics table.
        let coverage = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'reminders scheduled through'")
        ).firstMatch
        XCTAssertTrue(coverage.waitForExistence(timeout: 10), "the footer must say how far reminders reach")
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'could not be scheduled'")).firstMatch.exists,
            "no request may fail on a healthy run"
        )

        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Queue Check"].waitForExistence(timeout: 10))
    }

    // MARK: - Helpers

    /// The "Reminder time" section header. Matched case-insensitively: iOS 18 exposes a
    /// Form section header's accessibility label as the uppercased text it draws
    /// ("REMINDER TIME"), while newer versions keep the authored case — an exact match
    /// passes locally and fails on CI with nothing in the log to say why.
    private var settingsHeader: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Reminder time'")).firstMatch
    }

    /// Opens Settings via the filter menu, retrying once and dumping the accessibility
    /// hierarchy to the console on failure so a CI-only failure is diagnosable from the log.
    private func openSettingsFromMenu() {
        let menuButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Filter and settings'")).firstMatch
        for attempt in 0..<2 {
            tapWhenReady(menuButton)
            tapWhenReady(app.buttons["Settings"])

            if settingsHeader.waitForExistence(timeout: 5) { return }
            print("openSettingsFromMenu attempt \(attempt) failed; hierarchy:\n\(app.debugDescription)")
        }
        XCTFail("The Settings sheet never presented from the menu")
    }

    /// Creates an event through the form with default date and group, answering the
    /// notification permission prompt if this install has not seen it yet.
    private func addEvent(named name: String) {
        app.buttons["Add a date"].firstMatch.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(name)

        app.buttons["Save"].tap()
        allowNotificationsIfPrompted()
    }

    private func allowNotificationsIfPrompted() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
        }
    }

    /// Taps only once the element exists and is hittable. A tap fired while a menu or sheet
    /// is still animating in gets silently dropped on slow CI runners, which is a flaky
    /// failure two lines later rather than an error here.
    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "element never appeared", file: file, line: line)
        let deadline = Date().addingTimeInterval(timeout)
        while !element.isHittable && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(element.isHittable, "element never became hittable", file: file, line: line)
        element.tap()
    }

    /// A menu-style `Picker` in a `Form` surfaces as a button whose label starts with the
    /// picker's title and carries the current value.
    private func pickerButton(titled title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// Long picker menus lazy-render, so an option far down the list does not exist as an
    /// element until the menu is scrolled towards it.
    private func scrollToMenuOption(_ label: String) -> Bool {
        let option = app.buttons[label]
        for _ in 0..<5 {
            if option.exists && option.isHittable { return true }
            app.swipeUp()
        }
        return option.exists && option.isHittable
    }
}
