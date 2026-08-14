import XCTest
import SwiftData
import DatesKit
@testable import Dates

/// Phase 05 — the bulk import path through the store: one save, one reschedule, group
/// matching by name, and the re-import guard.
@MainActor
final class ImportTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var center: FakeNotificationCenter!
    private var store: EventStore!

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
        _ = try DatesModelContainer.seedIfNeeded(context)
    }

    override func tearDownWithError() throws {
        store = nil
        center = nil
        context = nil
        container = nil
    }

    private func fetchGroup(_ name: String) throws -> EventGroup {
        try XCTUnwrap(try context.fetch(FetchDescriptor<EventGroup>()).first { $0.name == name })
    }

    /// An annual date `days` from today, so tests never depend on the time of year they run.
    private func annualDate(inDays days: Int, calendar: Calendar = .current) throws -> AnnualDate {
        let target = try XCTUnwrap(calendar.date(byAdding: .day, value: days, to: Date()))
        let components = calendar.dateComponents([.month, .day], from: target)
        return try XCTUnwrap(AnnualDate(month: try XCTUnwrap(components.month), day: try XCTUnwrap(components.day)))
    }

    func testABatchImportStoresEveryCandidateAndSchedulesTheirNotifications() async throws {
        let candidates = [
            ImportCandidate(name: "Anna", type: .birthday, date: try annualDate(inDays: 30)),
            ImportCandidate(name: "Bob", type: .anniversary, date: try annualDate(inDays: 60)),
            ImportCandidate(name: "Carol", type: .other, date: try annualDate(inDays: 90)),
        ]
        let imported = try await store.importEvents(candidates, fallbackGroup: nil)

        XCTAssertEqual(imported, 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DateEvent>()), 3)
        XCTAssertFalse(center.identifiers.isEmpty, "imported dates must get notifications like any other")
    }

    func testACandidateNamingAnExistingGroupJoinsItAndTheRestUseTheFallback() async throws {
        let friends = try fetchGroup("Friends")
        let candidates = [
            ImportCandidate(name: "Anna", type: .birthday, date: try annualDate(inDays: 30), groupName: "close FAMILY"),
            ImportCandidate(name: "Bob", type: .birthday, date: try annualDate(inDays: 60), groupName: "No such group"),
            ImportCandidate(name: "Carol", type: .birthday, date: try annualDate(inDays: 90)),
        ]
        try await store.importEvents(candidates, fallbackGroup: friends)

        let events = try context.fetch(FetchDescriptor<DateEvent>())
        XCTAssertEqual(events.first { $0.name == "Anna" }?.group?.name, "Close family",
                       "group names match case-insensitively")
        XCTAssertEqual(events.first { $0.name == "Bob" }?.group?.name, "Friends",
                       "an unknown group name falls back rather than creating a group")
        XCTAssertEqual(events.first { $0.name == "Carol" }?.group?.name, "Friends")
    }

    func testWithNoFallbackGroupCandidatesLandInUngrouped() async throws {
        try await store.importEvents(
            [ImportCandidate(name: "Anna", type: .birthday, date: try annualDate(inDays: 30))],
            fallbackGroup: nil
        )
        let events = try context.fetch(FetchDescriptor<DateEvent>())
        XCTAssertEqual(events.first?.group?.name, SeedGroups.ungroupedName)
    }

    func testReimportingTheSameBatchAddsNothing() async throws {
        let candidates = [
            ImportCandidate(name: "Anna", type: .birthday, date: try annualDate(inDays: 30)),
            ImportCandidate(name: "Bob", type: .anniversary, date: try annualDate(inDays: 60)),
        ]
        let first = try await store.importEvents(candidates, fallbackGroup: nil)
        let second = try await store.importEvents(candidates, fallbackGroup: nil)

        XCTAssertEqual(first, 2)
        XCTAssertEqual(second, 0, "the store screens duplicates even if the review step is bypassed")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DateEvent>()), 2)
    }

    func testImportRequestsAuthorisationOnTheFirstSaveExactlyOnce() async throws {
        XCTAssertEqual(center.authorizationRequestCount, 0)
        try await store.importEvents(
            [
                ImportCandidate(name: "Anna", type: .birthday, date: try annualDate(inDays: 30)),
                ImportCandidate(name: "Bob", type: .birthday, date: try annualDate(inDays: 60)),
            ],
            fallbackGroup: nil
        )
        XCTAssertEqual(center.authorizationRequestCount, 1,
                       "a 200-row import must produce one prompt, not 200")
    }

    func testExportOfTheStoreRoundTripsThroughTheImporterAsPureDuplicates() async throws {
        let close = try fetchGroup("Close family")
        try await store.createEvent(
            name: "Zoë, the léap one",
            date: try XCTUnwrap(AnnualDate(month: 2, day: 29, year: 2000)),
            type: .birthday,
            group: close
        )

        let outcome = try EventCSV.decode(EventCSV.encode(store.snapshots()))
        XCTAssertTrue(outcome.rejectedRows.isEmpty)
        XCTAssertEqual(outcome.candidates.count, 1)
        XCTAssertEqual(outcome.candidates.first?.groupName, "Close family")

        let imported = try await store.importEvents(outcome.candidates, fallbackGroup: nil)
        XCTAssertEqual(imported, 0, "an exported file re-imports as pure duplicates")
    }
}
