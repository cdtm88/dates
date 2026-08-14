import XCTest
@testable import DatesKit

/// The app↔widget contract: the JSON shape round-trips and the widget's slice is
/// soonest-first regardless of the order the app wrote.
final class WidgetBridgeTests: XCTestCase {

    private func widgetEvent(_ name: String, _ month: Int, _ day: Int, year: Int? = nil) -> WidgetEvent {
        WidgetEvent(id: UUID(), name: name, type: .birthday, date: annual(month, day, year: year))
    }

    func testWidgetEventsRoundTripThroughJSON() throws {
        let events = [
            widgetEvent("Anna", 3, 14, year: 1990),
            WidgetEvent(id: UUID(), name: "Priya & Sam", type: .anniversary, date: annual(2, 29)),
        ]
        let data = try JSONEncoder().encode(events)
        let decoded = try JSONDecoder().decode([WidgetEvent].self, from: data)
        XCTAssertEqual(decoded, events)
    }

    func testUpcomingIsSoonestFirstAndCapped() {
        let now = makeDate(2026, 8, 14)
        let events = [
            widgetEvent("December", 12, 25),
            widgetEvent("Tomorrow", 8, 15),
            widgetEvent("NextWeek", 8, 21),
            widgetEvent("Today", 8, 14),
        ]
        let upcoming = WidgetBridge.upcoming(events, limit: 3, now: now, calendar: TestCalendar.london)
        XCTAssertEqual(upcoming.map(\.name), ["Today", "Tomorrow", "NextWeek"])
    }

    func testUpcomingBreaksSameDayTiesByName() {
        let now = makeDate(2026, 8, 14)
        let events = [
            widgetEvent("zoe", 9, 1),
            widgetEvent("Anna", 9, 1),
        ]
        let upcoming = WidgetBridge.upcoming(events, limit: 5, now: now, calendar: TestCalendar.london)
        XCTAssertEqual(upcoming.map(\.name), ["Anna", "zoe"])
    }

    func testAMilestoneYearSurfacesOnTheWidgetEventToo() {
        let now = makeDate(2026, 8, 14)
        let thirty = widgetEvent("Anna", 9, 1, year: 1996)
        XCTAssertEqual(thirty.milestoneYears(from: now, calendar: TestCalendar.london), 30)
        XCTAssertNil(widgetEvent("Ben", 9, 1, year: 1997).milestoneYears(from: now, calendar: TestCalendar.london))
    }
}
