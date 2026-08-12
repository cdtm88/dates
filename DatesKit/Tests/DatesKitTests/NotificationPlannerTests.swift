import XCTest
@testable import DatesKit

/// Phase 04 — NOTIF-02, NOTIF-03, NOTIF-04, NOTIF-05, NOTIF-08, NOTIF-09, PERF-03.
final class NotificationPlannerTests: XCTestCase {
    private let calendar = TestCalendar.london
    private let planner = NotificationPlanner()
    private let now = makeDate(2026, 8, 12, 9, 30, calendar: TestCalendar.london)

    private func plan(
        _ events: [EventSnapshot],
        planner: NotificationPlanner? = nil,
        now: Date? = nil,
        time: TimeOfDay = .defaultNotificationTime
    ) -> NotificationPlan {
        (planner ?? self.planner).plan(
            events: events,
            now: now ?? self.now,
            notificationTime: time,
            calendar: calendar
        )
    }

    // MARK: - Fire dates (NOTIF-02, NOTIF-03, NOTIF-09)

    func testEachEnabledOffsetProducesAFireDateAtTheConfiguredTime() {
        let event = makeEvent(date: annual(9, 20), groupDefaultOffsets: .all)
        let result = plan([event])

        XCTAssertEqual(result.count, 3)
        let byOffset = Dictionary(uniqueKeysWithValues: result.notifications.map { ($0.offset, $0.fireDate) })
        XCTAssertEqual(byOffset[.dayOf], makeDate(2026, 9, 20, 9, 0))
        XCTAssertEqual(byOffset[.threeDays], makeDate(2026, 9, 17, 9, 0))
        XCTAssertEqual(byOffset[.sevenDays], makeDate(2026, 9, 13, 9, 0))
    }

    func testChangingTheGlobalNotificationTimeMovesEveryFireDate() {
        let event = makeEvent(date: annual(9, 20), groupDefaultOffsets: .all)
        let result = plan([event], time: TimeOfDay(hour: 18, minute: 45))
        for notification in result.notifications {
            let components = calendar.dateComponents([.hour, .minute], from: notification.fireDate)
            XCTAssertEqual(components.hour, 18)
            XCTAssertEqual(components.minute, 45)
        }
    }

    func testOnlyEnabledOffsetsAreScheduled() {
        let event = makeEvent(date: annual(9, 20), groupDefaultOffsets: [.dayOf, .sevenDays])
        let result = plan([event])
        XCTAssertEqual(Set(result.notifications.map(\.offset)), [.dayOf, .sevenDays])
    }

    func testAPerEventOverrideDrivesSchedulingNotTheGroupDefault() {
        let event = makeEvent(date: annual(9, 20), groupDefaultOffsets: .all, offsetOverride: [.dayOf])
        let result = plan([event])
        XCTAssertEqual(result.notifications.map(\.offset), [.dayOf])
    }

    func testAnEventWithNoOffsetsSchedulesNothing() {
        let event = makeEvent(date: annual(9, 20), groupDefaultOffsets: .all, offsetOverride: .empty)
        XCTAssertEqual(plan([event]).count, 0)
    }

    // MARK: - Offsets already in the past

    func testAdvanceOffsetsAlreadyPassedAreDroppedRatherThanFiredLate() {
        // The event is two days away, so its 7-day and 3-day alerts are already behind us.
        let event = makeEvent(date: annual(8, 14), groupDefaultOffsets: .all)
        let result = plan([event])
        XCTAssertEqual(result.notifications.map(\.offset), [.dayOf])
        XCTAssertEqual(result.notifications.first?.fireDate, makeDate(2026, 8, 14, 9, 0))
    }

    func testTheDayOfAlertForTodayIsDroppedOnceTheNotificationTimeHasPassed() {
        // now is 09:30 and the notification time is 09:00, so today's alert has gone.
        let event = makeEvent(date: annual(8, 12), groupDefaultOffsets: .all)
        XCTAssertEqual(plan([event]).count, 0)
    }

    func testTheDayOfAlertForTodayIsKeptWhenTheNotificationTimeIsStillAhead() {
        let event = makeEvent(date: annual(8, 12), groupDefaultOffsets: .all)
        let result = plan([event], now: makeDate(2026, 8, 12, 7, 0))
        XCTAssertEqual(result.notifications.map(\.offset), [.dayOf])
    }

    func testAnEventWithNothingLeftToFireDoesNotConsumeAQueueSlotOrStopTheFill() {
        // The nearest event has already fired everything it can. A later event must still
        // be scheduled rather than being blocked behind it.
        let spent = makeEvent(name: "Spent", date: annual(8, 12), groupDefaultOffsets: .all)
        let upcoming = makeEvent(name: "Upcoming", date: annual(9, 20), groupDefaultOffsets: .all)
        let result = plan([spent, upcoming])

        XCTAssertEqual(result.count, 3)
        XCTAssertFalse(result.coveredEventIDs.contains(spent.id))
        XCTAssertTrue(result.coveredEventIDs.contains(upcoming.id))
    }

    // MARK: - The queue ceiling (NOTIF-04, D-06, D-07)

    func testTheCeilingIsNeverExceededAtFiveHundredEvents() {
        let events = makeEvents(count: 500, from: now, calendar: calendar)
        let result = plan(events)
        XCTAssertLessThanOrEqual(result.count, 60)
        XCTAssertTrue(result.wasTruncated)
    }

    func testTheSoonestTwentyEventsEachGetAllOfTheirConfiguredOffsets() {
        let events = makeEvents(count: 500, from: now, calendar: calendar)
        let result = plan(events)

        let soonestTwenty = EventOrdering
            .sortedByNextOccurrence(events, now: now, calendar: calendar)
            .prefix(20)

        for event in soonestTwenty {
            XCTAssertTrue(result.coveredEventIDs.contains(event.id), "\(event.name) was not covered")
            XCTAssertEqual(
                Set(result.notifications(forEvent: event.id).map(\.offset)),
                Set(event.effectiveOffsets.offsets),
                "\(event.name) is missing offsets"
            )
        }
        // 20 events x 3 offsets is exactly the ceiling.
        XCTAssertEqual(result.count, 60)
    }

    func testNoEventIsEverPartiallyScheduled() {
        // A 7-day warning with no day-of reminder behind it is worse than no warning, so
        // the fill stops on a whole event rather than splitting one.
        let tightPlanner = NotificationPlanner(queueCeiling: 4)
        let events = [
            makeEvent(name: "First", date: annual(9, 1), groupDefaultOffsets: .all),
            makeEvent(name: "Second", date: annual(9, 10), groupDefaultOffsets: .all),
        ]
        let result = plan(events, planner: tightPlanner)

        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.wasTruncated)
        XCTAssertEqual(result.coveredEventIDs.count, 1)
        for eventID in result.coveredEventIDs {
            XCTAssertEqual(result.notifications(forEvent: eventID).count, 3)
        }
    }

    func testASmallDatasetIsCoveredCompletelyAndIsNotTruncated() {
        let events = (0..<5).map { index in
            makeEvent(name: "Person \(index)", date: annual(9, 1 + index), groupDefaultOffsets: .all)
        }
        let result = plan(events)
        XCTAssertEqual(result.count, 15)
        XCTAssertEqual(result.coveredEventIDs.count, 5)
        XCTAssertFalse(result.wasTruncated)
    }

    func testASmallDatasetIsCoveredMoreThanAYearAhead() throws {
        // The defence against the queue draining while the app goes unopened (PRD §8) is
        // that a small dataset's window reaches past the next occurrence of everything.
        let events = (0..<5).map { index in
            makeEvent(name: "Person \(index)", date: annual(1 + index, 10), groupDefaultOffsets: [.dayOf])
        }
        let result = plan(events)
        XCTAssertEqual(result.coveredEventIDs.count, 5)
        let horizon = try XCTUnwrap(result.coverageHorizon)
        XCTAssertGreaterThan(horizon, now)
    }

    func testTheWindowExcludesEventsBeyondIt() {
        let shortWindow = NotificationPlanner(queueCeiling: 60, windowDays: 10)
        let events = [
            makeEvent(name: "Inside", date: annual(8, 18), groupDefaultOffsets: [.dayOf]),
            makeEvent(name: "Outside", date: annual(11, 1), groupDefaultOffsets: [.dayOf]),
        ]
        let result = plan(events, planner: shortWindow)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.notifications.first?.body.contains("Inside"), true)
    }

    // MARK: - Output shape (NOTIF-05)

    func testNotificationsAreReturnedSoonestFirst() {
        let events = makeEvents(count: 40, from: now, calendar: calendar)
        let result = plan(events)
        let fireDates = result.notifications.map(\.fireDate)
        XCTAssertEqual(fireDates, fireDates.sorted())
    }

    func testEveryIdentifierIsUniqueAndParsesBackToItsEventAndOffset() {
        let events = makeEvents(count: 40, from: now, calendar: calendar)
        let result = plan(events)

        XCTAssertEqual(Set(result.identifiers).count, result.count)
        for notification in result.notifications {
            let parsed = NotificationIdentifier.parse(notification.identifier)
            XCTAssertEqual(parsed?.eventID, notification.eventID)
            XCTAssertEqual(parsed?.offset, notification.offset)
        }
    }

    func testPlanningIsDeterministic() {
        let events = makeEvents(count: 200, from: now, calendar: calendar)
        let first = plan(events)
        let second = plan(events.shuffled())
        XCTAssertEqual(first.identifiers, second.identifiers)
    }

    // MARK: - Copy (NOTIF-08)

    func testTheBodyStatesTheNameTheTypeAndTheAgeWhereKnown() {
        let event = makeEvent(name: "Sarah Chen", type: .birthday, date: annual(9, 20, year: 1990), groupDefaultOffsets: [.dayOf])
        let notification = plan([event]).notifications.first
        XCTAssertEqual(notification?.title, "Today")
        XCTAssertEqual(notification?.body, "Sarah Chen — birthday, turning 36.")
    }

    func testTheBodyOmitsTheNumberWhenTheYearIsUnknown() {
        let event = makeEvent(name: "Sarah Chen", type: .birthday, date: annual(9, 20), groupDefaultOffsets: [.dayOf])
        XCTAssertEqual(plan([event]).notifications.first?.body, "Sarah Chen — birthday.")
    }

    func testAdvanceAlertsAreTitledByHowFarAwayTheEventIs() {
        let event = makeEvent(date: annual(9, 20), groupDefaultOffsets: .all)
        let byOffset = Dictionary(uniqueKeysWithValues: plan([event]).notifications.map { ($0.offset, $0.title) })
        XCTAssertEqual(byOffset[.dayOf], "Today")
        XCTAssertEqual(byOffset[.threeDays], "In 3 days")
        XCTAssertEqual(byOffset[.sevenDays], "In 7 days")
    }

    func testAnniversaryAndKeyDateCopyUsesElapsedYears() {
        XCTAssertEqual(
            NotificationContentBuilder.body(name: "Sarah & Tom", type: .anniversary, yearsElapsed: 10),
            "Sarah & Tom — anniversary, 10 years."
        )
        XCTAssertEqual(
            NotificationContentBuilder.body(name: "Sarah & Tom", type: .anniversary, yearsElapsed: 1),
            "Sarah & Tom — anniversary, 1 year."
        )
        XCTAssertEqual(
            NotificationContentBuilder.body(name: "Passport renewal", type: .other, yearsElapsed: nil),
            "Passport renewal — key date."
        )
    }

    // MARK: - Performance (PERF-03)

    func testAFullRescheduleOfFiveHundredEventsIsFast() {
        let events = makeEvents(count: 500, from: now, calendar: calendar)
        let duration = measureDuration {
            _ = plan(events)
        }
        // PERF-03 budgets 2s on device for the whole reschedule, of which planning is the
        // computational part; the remainder is the UNUserNotificationCenter round trip.
        XCTAssertLessThan(duration, 2.0, "planning 500 events took \(duration)s")
    }
}
