import XCTest
import SwiftData
import DatesKit
@testable import Dates

/// Phase 01 and 02 requirements that need SwiftData, so they run on a Mac rather than in the
/// DatesKit suite: DATA-02, DATA-05, GROUP-01, GROUP-02.
@MainActor
final class PersistenceTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dates-tests-\(UUID().uuidString).store")
    }

    override func tearDownWithError() throws {
        // SwiftData writes sidecar files alongside the store.
        for suffix in ["", "-shm", "-wal"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// A real on-disk container, so closing and reopening it is a genuine relaunch.
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: DatesModelContainer.schema, url: storeURL)
        return try ModelContainer(for: DatesModelContainer.schema, configurations: [configuration])
    }

    // MARK: - DATA-02

    func testAnEventSurvivesClosingAndReopeningTheStore() throws {
        let eventID = UUID()

        do {
            let container = try makeContainer()
            let context = ModelContext(container)
            let group = try DatesModelContainer.seedIfNeeded(context)
            let event = DateEvent(
                id: eventID,
                name: "Sarah Chen",
                date: AnnualDate(month: 2, day: 29, year: 2000)!,
                type: .birthday,
                group: group,
                offsetOverride: [.dayOf, .sevenDays]
            )
            context.insert(event)
            try context.save()
        }

        let container = try makeContainer()
        let context = ModelContext(container)
        let reloaded = try XCTUnwrap(
            try context.fetch(FetchDescriptor<DateEvent>(predicate: #Predicate { $0.uuid == eventID })).first
        )

        XCTAssertEqual(reloaded.name, "Sarah Chen")
        XCTAssertEqual(reloaded.month, 2)
        XCTAssertEqual(reloaded.day, 29)
        XCTAssertEqual(reloaded.year, 2000)
        XCTAssertEqual(reloaded.type, .birthday)
        XCTAssertEqual(reloaded.offsetOverride, [.dayOf, .sevenDays])
        XCTAssertNotNil(reloaded.group)
    }

    func testAnEditAndADeleteBothSurviveAReopen() throws {
        let eventID = UUID()
        let doomedID = UUID()

        do {
            let container = try makeContainer()
            let context = ModelContext(container)
            let group = try DatesModelContainer.seedIfNeeded(context)
            context.insert(DateEvent(id: eventID, name: "Before", date: AnnualDate(month: 3, day: 1)!, type: .other, group: group))
            context.insert(DateEvent(id: doomedID, name: "Doomed", date: AnnualDate(month: 4, day: 1)!, type: .other, group: group))
            try context.save()
        }

        do {
            let container = try makeContainer()
            let context = ModelContext(container)
            let events = try context.fetch(FetchDescriptor<DateEvent>())
            try XCTUnwrap(events.first { $0.uuid == eventID }).name = "After"
            context.delete(try XCTUnwrap(events.first { $0.uuid == doomedID }))
            try context.save()
        }

        let container = try makeContainer()
        let context = ModelContext(container)
        let events = try context.fetch(FetchDescriptor<DateEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.name, "After")
    }

    // MARK: - DATA-05

    func testFiveHundredEventsInsertAndQueryWithoutError() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let group = try DatesModelContainer.seedIfNeeded(context)

        for index in 0..<500 {
            let month = (index % 12) + 1
            let day = (index % 28) + 1
            context.insert(
                DateEvent(
                    name: String(format: "Person %03d", index),
                    date: AnnualDate(month: month, day: day, year: 1990)!,
                    type: .birthday,
                    group: group
                )
            )
        }
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DateEvent>()), 500)

        let target = "Person 250"
        let matches = try context.fetch(FetchDescriptor<DateEvent>(predicate: #Predicate { $0.name == target }))
        XCTAssertEqual(matches.count, 1)

        // The list path maps every model to a snapshot before sorting, so prove that scales.
        let snapshots = try context.fetch(FetchDescriptor<DateEvent>()).map(\.snapshot)
        XCTAssertEqual(snapshots.count, 500)
        XCTAssertEqual(EventOrdering.sortedByNextOccurrence(snapshots, now: Date()).count, 500)
    }

    // MARK: - GROUP-01

    func testSeedingCreatesFiveGroupsAndIsIdempotent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        try DatesModelContainer.seedIfNeeded(context)
        try DatesModelContainer.seedIfNeeded(context)

        let groups = try context.fetch(FetchDescriptor<EventGroup>())
        XCTAssertEqual(groups.count, 5)
        XCTAssertEqual(groups.filter(\.isUngrouped).count, 1)
        XCTAssertEqual(
            Set(groups.map(\.name)),
            Set(["Close family", "Wider family", "Friends", "Work", "Ungrouped"])
        )
        XCTAssertFalse(try XCTUnwrap(groups.first(where: \.isUngrouped)).isDeletable)
    }

    func testSeedingRecreatesUngroupedIfItIsMissing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(EventGroup(name: "Friends", defaultOffsets: .dayOf))
        try context.save()

        try DatesModelContainer.seedIfNeeded(context)

        let groups = try context.fetch(FetchDescriptor<EventGroup>())
        XCTAssertEqual(groups.filter(\.isUngrouped).count, 1)
    }

    // MARK: - GROUP-02

    func testDeletingAGroupMovesItsEventsToUngroupedRatherThanDeletingThem() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try DatesModelContainer.seedIfNeeded(context)

        let store = makeStore(context: context)
        let group = try store.createGroup(name: "Cycling club", defaultOffsets: [.dayOf, .sevenDays])
        try await store.createEvent(
            name: "Club anniversary",
            date: AnnualDate(month: 6, day: 1)!,
            type: .anniversary,
            group: group
        )

        try await store.deleteGroup(group)

        let events = try context.fetch(FetchDescriptor<DateEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.group?.name, SeedGroups.ungroupedName)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EventGroup>()), 5)
    }

    func testUngroupedCannotBeDeleted() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ungrouped = try DatesModelContainer.seedIfNeeded(context)
        let store = makeStore(context: context)

        try await store.deleteGroup(ungrouped)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EventGroup>()), 5)
    }

    // MARK: - Helpers

    private func makeStore(context: ModelContext) -> EventStore {
        EventStore(
            context: context,
            scheduler: NotificationScheduler(center: FakeNotificationCenter()),
            settings: AppSettings(defaults: isolatedDefaults())
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "dates.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
