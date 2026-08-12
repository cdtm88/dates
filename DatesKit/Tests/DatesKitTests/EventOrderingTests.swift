import XCTest
@testable import DatesKit

/// Phase 03 — LIST-01, LIST-03, LIST-04, SCALE-01.
final class EventOrderingTests: XCTestCase {
    private let calendar = TestCalendar.london

    // MARK: - Ordering (LIST-01)

    func testEventsSortAscendingByDaysUntilNextOccurrence() {
        let now = makeDate(2026, 8, 12, 9, 0)
        let events = [
            makeEvent(name: "December", date: annual(12, 25)),
            makeEvent(name: "Tomorrow", date: annual(8, 13)),
            makeEvent(name: "Passed in March", date: annual(3, 15)),
            makeEvent(name: "Today", date: annual(8, 12)),
        ]

        let sorted = EventOrdering.sortedByNextOccurrence(events, now: now, calendar: calendar)
        XCTAssertEqual(sorted.map(\.name), ["Today", "Tomorrow", "December", "Passed in March"])
    }

    func testAnEventDatedTodaySortsFirstAndStaysThereAllDay(){
        let events = [
            makeEvent(name: "Tomorrow", date: annual(8, 13)),
            makeEvent(name: "Today", date: annual(8, 12)),
        ]
        for hour in [0, 9, 18, 23] {
            let now = makeDate(2026, 8, 12, hour, 30)
            let sorted = EventOrdering.sortedByNextOccurrence(events, now: now, calendar: calendar)
            XCTAssertEqual(sorted.first?.name, "Today", "failed at \(hour):30")
        }
    }

    func testAPassedEventMovesToItsNextYearPositionOnceTheClockCrossesMidnight(){
        let events = [
            makeEvent(name: "Yesterday", date: annual(8, 12)),
            makeEvent(name: "Tomorrow", date: annual(8, 14)),
            makeEvent(name: "Autumn", date: annual(10, 1)),
        ]
        let afterMidnight = makeDate(2026, 8, 13, 0, 0)
        let sorted = EventOrdering.sortedByNextOccurrence(events, now: afterMidnight, calendar: calendar)
        // Yesterday's event rolls to the bottom, a year away, rather than vanishing.
        XCTAssertEqual(sorted.map(\.name), ["Tomorrow", "Autumn", "Yesterday"])
        XCTAssertEqual(sorted.last?.daysUntil(from: afterMidnight, calendar: calendar), 364)
    }

    func testTiesBreakOnNameSoOrderIsStableAcrossLaunches() {
        let now = makeDate(2026, 8, 12)
        let events = [
            makeEvent(name: "Zara", date: annual(9, 1)),
            makeEvent(name: "Adam", date: annual(9, 1)),
            makeEvent(name: "morgan", date: annual(9, 1)),
        ]
        let first = EventOrdering.sortedByNextOccurrence(events, now: now, calendar: calendar).map(\.name)
        let second = EventOrdering.sortedByNextOccurrence(events.reversed(), now: now, calendar: calendar).map(\.name)
        XCTAssertEqual(first, ["Adam", "morgan", "Zara"])
        XCTAssertEqual(first, second)
    }

    // MARK: - Search and filter (LIST-04)

    func testSearchMatchesNameCaseAndDiacriticInsensitively() {
        let event = makeEvent(name: "Zoë Müller", date: annual(9, 1))
        XCTAssertTrue(EventOrdering.matches(event, query: "zoe"))
        XCTAssertTrue(EventOrdering.matches(event, query: "MÜLLER"))
        XCTAssertTrue(EventOrdering.matches(event, query: "muller"))
        XCTAssertTrue(EventOrdering.matches(event, query: "  zoë  "))
        XCTAssertFalse(EventOrdering.matches(event, query: "smith"))
    }

    func testAnEmptyQueryMatchesEverything() {
        let event = makeEvent(name: "Anyone", date: annual(9, 1))
        XCTAssertTrue(EventOrdering.matches(event, query: ""))
        XCTAssertTrue(EventOrdering.matches(event, query: "   "))
    }

    func testSearchDoesNotMatchOnGroupName() {
        // PRD §9 fixes search to names only; matching the group would make the group filter
        // and the search box fight each other.
        let event = makeEvent(name: "Anyone", date: annual(9, 1), groupName: "Work")
        XCTAssertFalse(EventOrdering.matches(event, query: "Work"))
    }

    func testGroupFilterAndSearchCompose() {
        let now = makeDate(2026, 8, 12)
        let work = UUID()
        let friends = UUID()
        let events = [
            makeEvent(name: "Sarah Chen", date: annual(9, 1), groupID: work),
            makeEvent(name: "Sarah Jones", date: annual(9, 2), groupID: friends),
            makeEvent(name: "Tom Ford", date: annual(9, 3), groupID: work),
        ]

        let workOnly = EventOrdering.filteredAndSorted(events, groupID: work, now: now, calendar: calendar)
        XCTAssertEqual(workOnly.map(\.name), ["Sarah Chen", "Tom Ford"])

        let workNamedSarah = EventOrdering.filteredAndSorted(events, groupID: work, query: "sarah", now: now, calendar: calendar)
        XCTAssertEqual(workNamedSarah.map(\.name), ["Sarah Chen"])

        let allNamedSarah = EventOrdering.filteredAndSorted(events, query: "sarah", now: now, calendar: calendar)
        XCTAssertEqual(allNamedSarah.map(\.name), ["Sarah Chen", "Sarah Jones"])
    }

    // MARK: - Scale (SCALE-01, LIST-04)

    func testSortingAndSearchingFiveHundredEventsStaysWellInsideTheBudget() {
        let now = makeDate(2026, 8, 12)
        let events = makeEvents(count: 500, from: now, calendar: calendar)
        XCTAssertEqual(events.count, 500)

        let sortDuration = measureDuration {
            _ = EventOrdering.sortedByNextOccurrence(events, now: now, calendar: calendar)
        }
        let searchDuration = measureDuration {
            _ = EventOrdering.filteredAndSorted(events, query: "Person 04", now: now, calendar: calendar)
        }

        // LIST-04 budgets 300ms on device. These are Linux numbers, so they are a
        // regression guard on the algorithm rather than the device measurement itself.
        XCTAssertLessThan(sortDuration, 0.3, "sorting 500 events took \(sortDuration)s")
        XCTAssertLessThan(searchDuration, 0.3, "searching 500 events took \(searchDuration)s")
    }

    func testSearchOverFiveHundredEventsReturnsTheExpectedSubset() {
        let now = makeDate(2026, 8, 12)
        let events = makeEvents(count: 500, from: now, calendar: calendar)
        let matches = EventOrdering.filteredAndSorted(events, query: "Person 0499", now: now, calendar: calendar)
        XCTAssertEqual(matches.map(\.name), ["Person 0499"])
    }
}
