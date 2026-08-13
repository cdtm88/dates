import XCTest
@testable import DatesKit

/// Phase 04 — D-08 and the cancellation guarantee behind NOTIF-07.
final class NotificationIdentifierTests: XCTestCase {
    private let eventID = UUID(uuidString: "8B0A0F5E-1C2D-4E3F-9A7B-6C5D4E3F2A1B")!

    func testIdentifiersUseTheDocumentedFormat() {
        XCTAssertEqual(
            NotificationIdentifier.make(eventID: eventID, offset: .sevenDays),
            "evt-8B0A0F5E-1C2D-4E3F-9A7B-6C5D4E3F2A1B-7"
        )
        XCTAssertEqual(
            NotificationIdentifier.make(eventID: eventID, offset: .dayOf),
            "evt-8B0A0F5E-1C2D-4E3F-9A7B-6C5D4E3F2A1B-0"
        )
    }

    func testIdentifiersRoundTripForEveryOffset() {
        for offset in NotificationOffset.allCases {
            let identifier = NotificationIdentifier.make(eventID: eventID, offset: offset)
            let parsed = NotificationIdentifier.parse(identifier)
            XCTAssertEqual(parsed?.eventID, eventID)
            XCTAssertEqual(parsed?.offset, offset)
        }
    }

    func testEveryIdentifierForAnEventSharesItsCancellationPrefix() {
        // Cancellation matches on the prefix rather than enumerating the offsets currently
        // stored, so an offset the user has just switched off is still cleaned up (NOTIF-07).
        let prefix = NotificationIdentifier.eventPrefix(for: eventID)
        for offset in NotificationOffset.allCases {
            XCTAssertTrue(NotificationIdentifier.make(eventID: eventID, offset: offset).hasPrefix(prefix))
        }
    }

    func testOneEventsPrefixDoesNotMatchAnotherEvent() {
        let other = UUID()
        let prefix = NotificationIdentifier.eventPrefix(for: eventID)
        XCTAssertFalse(NotificationIdentifier.make(eventID: other, offset: .dayOf).hasPrefix(prefix))
    }

    func testMalformedIdentifiersAreRejectedRatherThanMisparsed() {
        // The app must never cancel a request it did not schedule.
        XCTAssertNil(NotificationIdentifier.parse(""))
        XCTAssertNil(NotificationIdentifier.parse("evt-"))
        XCTAssertNil(NotificationIdentifier.parse("something-else"))
        XCTAssertNil(NotificationIdentifier.parse("evt-not-a-uuid-0"))
        XCTAssertNil(NotificationIdentifier.parse("evt-\(eventID.uuidString)"))
        XCTAssertNil(NotificationIdentifier.parse("evt-\(eventID.uuidString)-4"))
        XCTAssertNil(NotificationIdentifier.parse("evt-\(eventID.uuidString)-x"))
        XCTAssertFalse(NotificationIdentifier.isEventIdentifier("some-other-app-request"))
    }

    func testTimeOfDayPersistsAsMinutesSinceMidnight() {
        let nineAM = TimeOfDay.defaultNotificationTime
        XCTAssertEqual(nineAM.hour, 9)
        XCTAssertEqual(nineAM.minute, 0)
        XCTAssertEqual(nineAM.minutesSinceMidnight, 540)
        XCTAssertEqual(TimeOfDay(minutesSinceMidnight: 540), nineAM)
        XCTAssertEqual(TimeOfDay(minutesSinceMidnight: 1439), TimeOfDay(hour: 23, minute: 59))
    }

    func testTimeOfDayClampsOutOfRangeInput() {
        XCTAssertEqual(TimeOfDay(hour: 99, minute: 99), TimeOfDay(hour: 23, minute: 59))
        XCTAssertEqual(TimeOfDay(minutesSinceMidnight: -10), TimeOfDay(hour: 0, minute: 0))
        XCTAssertEqual(TimeOfDay(minutesSinceMidnight: 99_999), TimeOfDay(hour: 23, minute: 59))
    }
}
