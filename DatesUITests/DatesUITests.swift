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

        // Phase 05 placeholders must be visible but not tappable.
        XCTAssertFalse(app.buttons["Import from Calendar"].isEnabled)
        XCTAssertFalse(app.buttons["Import a CSV"].isEnabled)
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

        // Switching to a known non-leap year clamps the day back to 28. The switch element
        // spans the whole row, so a centre tap misses the control at the trailing edge.
        let yearToggle = app.switches["I know the year"].firstMatch
        XCTAssertTrue(yearToggle.waitForExistence(timeout: 5))
        yearToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()

        let yearPicker = pickerButton(titled: "Year")
        XCTAssertTrue(yearPicker.waitForExistence(timeout: 5), "turning the year on must reveal the year picker")
        yearPicker.tap()
        XCTAssertTrue(scrollToMenuOption("2023"))
        app.buttons["2023"].tap()
        XCTAssertTrue(pickerButton(titled: "Day").label.contains("28"), "29 February 2023 does not exist")
    }

    // MARK: - Settings (NOTIF-04, NOTIF-09)

    func testSettingsShowsTheReminderQueue() {
        addEvent(named: "Queue Check")
        XCTAssertTrue(app.staticTexts["Queue Check"].waitForExistence(timeout: 10))

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Filter and settings'")).firstMatch.tap()
        app.buttons["Settings"].tap()

        XCTAssertTrue(app.staticTexts["Reminder time"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Scheduled"].exists)
        XCTAssertTrue(app.staticTexts["Dates covered"].exists)
        XCTAssertFalse(app.staticTexts["Could not schedule"].exists, "no request may fail on a healthy run")

        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Queue Check"].waitForExistence(timeout: 10))
    }

    // MARK: - Helpers

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
