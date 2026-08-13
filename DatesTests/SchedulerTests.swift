import XCTest
import SwiftData
import UserNotifications
import DatesKit
@testable import Dates

/// Phase 04 requirements that need the app layer rather than the pure planner:
/// NOTIF-01, NOTIF-04, NOTIF-07.
@MainActor
final class SchedulerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var center: FakeNotificationCenter!
    private var store: EventStore!
    private var group: EventGroup!

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(schema: DatesModelContainer.schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: DatesModelContainer.schema, configurations: [configuration])
        context = ModelContext(container)
        center = FakeNotificationCenter()

        let suite = "dates.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)

        store = EventStore(
            context: context,
            scheduler: NotificationScheduler(center: center),
            settings: AppSettings(defaults: defaults)
        )
    }

    override func tearDownWithError() throws {
        store = nil
        center = nil
        context = nil
        container = nil
    }

    private func seededGroup() throws -> EventGroup {
        if group == nil {
            _ = try DatesModelContainer.seedIfNeeded(context)
            group = try XCTUnwrap(
                try context.fetch(FetchDescriptor<EventGroup>()).first { $0.name == "Close family" }
            )
        }
        return group
    }

    /// An annual date `days` from today, so tests never depend on the time of year they run.
    private func annualDate(inDays days: Int, calendar: Calendar = .current) throws -> AnnualDate {
        let target = try XCTUnwrap(calendar.date(byAdding: .day, value: days, to: Date()))
        let components = calendar.dateComponents([.month, .day], from: target)
        return try XCTUnwrap(AnnualDate(month: try XCTUnwrap(components.month), day: try XCTUnwrap(components.day)))
    }

    // MARK: - NOTIF-01

    func testAuthorisationIsRequestedOnceOnTheFirstSaveNotAtLaunch() async throws {
        XCTAssertEqual(center.authorizationRequestCount, 0, "nothing should be requested before a save")

        let group = try seededGroup()
        try await store.createEvent(name: "First", date: try annualDate(inDays: 40), type: .birthday, group: group)
        XCTAssertEqual(center.authorizationRequestCount, 1)

        try await store.createEvent(name: "Second", date: try annualDate(inDays: 50), type: .birthday, group: group)
        XCTAssertEqual(center.authorizationRequestCount, 1, "the prompt must not reappear on later saves")
    }

    func testDenialLeavesTheAppFullyUsableAndSchedulesNothing() async throws {
        center.authorizationStatus = .denied
        center.authorizationGrantResult = false

        let group = try seededGroup()
        try await store.createEvent(name: "Denied", date: try annualDate(inDays: 40), type: .birthday, group: group)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DateEvent>()), 1, "the event must still be stored")
        XCTAssertTrue(center.identifiers.isEmpty, "nothing can be scheduled without authorisation")
    }

    func testGrantingPermissionAfterDenialRebuildsTheQueueOnTheNextPass() async throws {
        center.authorizationStatus = .denied
        center.authorizationGrantResult = false

        let group = try seededGroup()
        try await store.createEvent(name: "Later", date: try annualDate(inDays: 40), type: .birthday, group: group)
        XCTAssertTrue(center.identifiers.isEmpty)
        XCTAssertEqual(store.queueSummary?.scheduledCount, 0)

        // The user flips the switch in the Settings app; the next foreground reschedule
        // must pick that up without any further prompting.
        center.authorizationStatus = .authorized
        await store.rescheduleAll()

        XCTAssertFalse(center.identifiers.isEmpty)
        XCTAssertEqual(store.queueSummary?.scheduledCount, center.identifiers.count)
    }

    // MARK: - NOTIF-04

    func testThePendingQueueNeverExceedsSixtyAtFiveHundredEvents() async throws {
        let group = try seededGroup()
        for index in 0..<500 {
            let month = (index % 12) + 1
            let day = (index % 28) + 1
            context.insert(
                DateEvent(
                    name: String(format: "Person %03d", index),
                    date: try XCTUnwrap(AnnualDate(month: month, day: day, year: 1990)),
                    type: .birthday,
                    group: group
                )
            )
        }
        try context.save()

        await store.rescheduleAll()

        XCTAssertLessThanOrEqual(center.identifiers.count, 60)
        XCTAssertEqual(Set(center.identifiers).count, center.identifiers.count, "identifiers must be unique")
        XCTAssertEqual(store.queueSummary?.totalEventCount, 500)
        XCTAssertEqual(store.queueSummary?.wasTruncated, true)
    }

    func testRepeatedReschedulesDoNotAccumulateRequests() async throws {
        let group = try seededGroup()
        try await store.createEvent(name: "Repeat", date: try annualDate(inDays: 40), type: .birthday, group: group)

        let afterFirst = center.identifiers.count
        await store.rescheduleAll()
        await store.rescheduleAll()

        XCTAssertEqual(center.identifiers.count, afterFirst)
    }

    /// The scheduler is a re-entrant actor, so overlapping passes could interleave their
    /// cancel and add phases without the internal chaining. Rapid event creation is the
    /// realistic trigger: every save reschedules before the previous pass has settled.
    func testOverlappingReschedulesLeaveAConsistentQueue() async throws {
        let group = try seededGroup()
        for index in 0..<10 {
            try await store.createEvent(
                name: String(format: "Person %02d", index),
                date: try annualDate(inDays: 30 + index * 7),
                type: .birthday,
                group: group
            )
        }
        let expected = center.identifiers.sorted()

        let scheduler = NotificationScheduler(center: center)
        let snapshots = store.snapshots()
        await withTaskGroup(of: Void.self) { tasks in
            for _ in 0..<8 {
                tasks.addTask {
                    await scheduler.reschedule(snapshots: snapshots, notificationTime: .defaultNotificationTime)
                }
            }
        }

        XCTAssertEqual(center.identifiers.sorted(), expected)
        XCTAssertEqual(Set(center.identifiers).count, center.identifiers.count, "identifiers must stay unique")
    }

    func testFailedRequestSubmissionsAreCountedNotSwallowed() async throws {
        let group = try seededGroup()
        try await store.createEvent(name: "Unlucky", date: try annualDate(inDays: 40), type: .birthday, group: group)
        XCTAssertEqual(store.queueSummary?.failedCount, 0)

        center.addError = FakeNotificationCenter.AddRefused()
        await store.rescheduleAll()

        XCTAssertEqual(store.queueSummary?.scheduledCount, 0)
        XCTAssertGreaterThan(store.queueSummary?.failedCount ?? 0, 0, "refused requests must be visible in the summary")
        XCTAssertTrue(center.identifiers.isEmpty)
    }

    // MARK: - NOTIF-07

    func testEditingAnEventsDateLeavesNoStaleRequestsForIt() async throws {
        let group = try seededGroup()
        let originalDate = try annualDate(inDays: 40)
        let event = try await store.createEvent(name: "Moves", date: originalDate, type: .birthday, group: group)

        let prefix = NotificationIdentifier.eventPrefix(for: event.uuid)
        XCTAssertFalse(center.identifiers(withPrefix: prefix).isEmpty)

        let newDate = try annualDate(inDays: 90)
        try await store.updateEvent(
            event,
            name: "Moves",
            date: newDate,
            type: .birthday,
            group: group,
            offsetOverride: nil
        )

        let components = center.fireDateComponents(forPrefix: prefix)
        XCTAssertFalse(components.isEmpty, "the event should still be scheduled at its new date")

        // Nothing may still be pointing at the old occurrence.
        XCTAssertFalse(
            components.contains { $0.month == originalDate.month && $0.day == originalDate.day },
            "a request still fires on the old date"
        )

        // The day-of request must land exactly on the new date.
        let dayOfIdentifier = NotificationIdentifier.make(eventID: event.uuid, offset: .dayOf)
        let dayOf = try XCTUnwrap(
            center.fireDateComponents(forPrefix: dayOfIdentifier).first,
            "the day-of alert is missing"
        )
        XCTAssertEqual(dayOf.month, newDate.month)
        XCTAssertEqual(dayOf.day, newDate.day)
        XCTAssertEqual(dayOf.hour, TimeOfDay.defaultNotificationTime.hour)
        XCTAssertEqual(dayOf.minute, TimeOfDay.defaultNotificationTime.minute)
    }

    func testRemovingAnOffsetCancelsItsRequest() async throws {
        let group = try seededGroup()
        let event = try await store.createEvent(
            name: "Narrowing",
            date: try annualDate(inDays: 40),
            type: .birthday,
            group: group,
            offsetOverride: [.dayOf, .threeDays, .sevenDays]
        )
        let prefix = NotificationIdentifier.eventPrefix(for: event.uuid)
        XCTAssertEqual(center.identifiers(withPrefix: prefix).count, 3)

        try await store.updateEvent(
            event,
            name: "Narrowing",
            date: event.annualDate,
            type: .birthday,
            group: group,
            offsetOverride: [.dayOf]
        )

        XCTAssertEqual(center.identifiers(withPrefix: prefix), [NotificationIdentifier.make(eventID: event.uuid, offset: .dayOf)])
    }

    /// A pinned calendar or timezone on the trigger would fire at the origin zone's clock
    /// time after the user travels or a DST transition lands between scheduling and firing.
    /// Floating components mean "this wall-clock time, wherever the device is".
    func testTriggerComponentsFloatWithTheLocalTimeZone() async throws {
        let group = try seededGroup()
        let event = try await store.createEvent(name: "Traveller", date: try annualDate(inDays: 40), type: .birthday, group: group)

        let prefix = NotificationIdentifier.eventPrefix(for: event.uuid)
        let allComponents = center.fireDateComponents(forPrefix: prefix)
        XCTAssertFalse(allComponents.isEmpty)

        for components in allComponents {
            XCTAssertNil(components.timeZone, "a pinned timezone breaks travel and DST behaviour")
            XCTAssertNil(components.calendar, "a pinned calendar pins its timezone too")
        }
    }

    func testDeletingAnEventRemovesEveryRequestItOwned() async throws {
        let group = try seededGroup()
        let event = try await store.createEvent(name: "Doomed", date: try annualDate(inDays: 40), type: .birthday, group: group)
        let prefix = NotificationIdentifier.eventPrefix(for: event.uuid)
        XCTAssertFalse(center.identifiers(withPrefix: prefix).isEmpty)

        try await store.deleteEvent(event)

        XCTAssertTrue(center.identifiers(withPrefix: prefix).isEmpty)
    }

    func testTheSchedulerNeverTouchesRequestsItDoesNotOwn() async throws {
        let foreign = UNNotificationRequest(
            identifier: "some-other-feature",
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        try await center.add(foreign)

        let group = try seededGroup()
        try await store.createEvent(name: "Mine", date: try annualDate(inDays: 40), type: .birthday, group: group)
        await store.rescheduleAll()

        XCTAssertTrue(center.identifiers.contains("some-other-feature"))
    }

    // MARK: - GROUP-05

    func testChangingAGroupDefaultReschedulesItsInheritingEvents() async throws {
        let group = try seededGroup()
        try await store.updateGroup(group, name: group.name, defaultOffsets: [.dayOf])

        let event = try await store.createEvent(
            name: "Inherits",
            date: try annualDate(inDays: 40),
            type: .birthday,
            group: group
        )
        let prefix = NotificationIdentifier.eventPrefix(for: event.uuid)
        XCTAssertEqual(center.identifiers(withPrefix: prefix).count, 1)

        try await store.updateGroup(group, name: group.name, defaultOffsets: [.dayOf, .threeDays, .sevenDays])

        XCTAssertEqual(center.identifiers(withPrefix: prefix).count, 3)
    }
}
