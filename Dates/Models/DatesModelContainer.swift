import Foundation
import SwiftData
import DatesKit

/// Container construction and first-launch seeding.
enum DatesModelContainer {
    static let schema = Schema([DateEvent.self, EventGroup.self])

    /// The private-database container CloudKit syncs into (Phase 06, SYNC).
    static let cloudKitContainerIdentifier = "iCloud.com.moorelabs.Dates"

    /// The on-disk container, CloudKit-backed by default (Phase 06).
    ///
    /// The schema was kept CloudKit-shaped from Phase 01 — every attribute has a default
    /// and every relationship is optional — so turning sync on is this flag plus the
    /// entitlement, with no migration (D-03, D-04). Sync is per-store, not per-record:
    /// with no iCloud account the container still works and everything stays local.
    ///
    /// `syncsWithCloudKit: false` is for tests and the `--uitest` launch, where the
    /// entitlement may be absent and a CloudKit-backed init would throw.
    static func makeContainer(inMemory: Bool = false, syncsWithCloudKit: Bool = true) throws -> ModelContainer {
        let cloudKit: ModelConfiguration.CloudKitDatabase =
            (syncsWithCloudKit && !inMemory) ? .private(cloudKitContainerIdentifier) : .none
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKit
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Creates the seeded groups on first launch and guarantees Ungrouped exists (GROUP-01).
    ///
    /// Idempotent, so a later launch — or a CloudKit sync that already brought the groups
    /// down — does not duplicate them.
    @MainActor
    @discardableResult
    static func seedIfNeeded(_ context: ModelContext) throws -> EventGroup {
        let existing = try context.fetch(FetchDescriptor<EventGroup>())

        if existing.isEmpty {
            for definition in SeedGroups.definitions {
                context.insert(
                    EventGroup(
                        name: definition.name,
                        defaultOffsets: definition.defaultOffsets,
                        isUngrouped: definition.isUngrouped
                    )
                )
            }
            try context.save()
            return try ungroupedGroup(context)
        }

        // Ungrouped can never be deleted through the UI, but a partial CloudKit sync or a
        // restore could still leave it missing, and every event needs somewhere to land.
        if existing.contains(where: \.isUngrouped) == false {
            let definition = SeedGroups.definitions.first { $0.isUngrouped }
            let ungrouped = EventGroup(
                name: definition?.name ?? SeedGroups.ungroupedName,
                defaultOffsets: definition?.defaultOffsets ?? .dayOf,
                isUngrouped: true
            )
            context.insert(ungrouped)
            try context.save()
            return ungrouped
        }

        return try ungroupedGroup(context)
    }

    #if DEBUG
    /// Sample dates for simulator screenshots (`--demo`, Debug builds only). Inserted
    /// directly rather than through `EventStore` because the store path requests
    /// notification permission, and the system alert would sit over the screenshot.
    /// Days-ahead offsets are relative so the list always looks current, spanning enough
    /// months to show the section headers, including one that wraps into next year.
    @MainActor
    static func seedDemoDataIfEmpty(_ context: ModelContext, now: Date = Date()) throws {
        guard try context.fetch(FetchDescriptor<DateEvent>()).isEmpty else { return }
        let groups = try context.fetch(FetchDescriptor<EventGroup>())

        let calendar = Calendar.current
        func annual(daysAhead: Int, turning: Int?) -> AnnualDate? {
            guard let occurrence = calendar.date(byAdding: .day, value: daysAhead, to: now) else { return nil }
            let components = calendar.dateComponents([.year, .month, .day], from: occurrence)
            guard let year = components.year, let month = components.month, let day = components.day else { return nil }
            return AnnualDate(month: month, day: day, year: turning.map { year - $0 })
        }

        let samples: [(name: String, daysAhead: Int, turning: Int?, type: EventType, group: String)] = [
            ("Mum", 2, 58, .birthday, "Close family"),
            ("Priya & Sam", 9, 12, .anniversary, "Friends"),
            ("Grandpa Joe", 16, 81, .birthday, "Close family"),
            ("Lena", 24, nil, .birthday, "Friends"),
            ("Aunt Carol", 38, 62, .birthday, "Wider family"),
            ("Marco", 47, nil, .birthday, "Work"),
            ("Our anniversary", 63, 6, .anniversary, "Close family"),
            ("Dad", 90, 61, .birthday, "Close family"),
            ("Nadia", 132, 29, .birthday, "Friends"),
            ("Tom", 200, nil, .birthday, "Work"),
        ]
        for sample in samples {
            guard let date = annual(daysAhead: sample.daysAhead, turning: sample.turning) else { continue }
            context.insert(DateEvent(
                name: sample.name,
                date: date,
                type: sample.type,
                group: groups.first { $0.name == sample.group }
            ))
        }
        try context.save()
    }
    #endif

    @MainActor
    static func ungroupedGroup(_ context: ModelContext) throws -> EventGroup {
        var descriptor = FetchDescriptor<EventGroup>(predicate: #Predicate { $0.isUngrouped })
        descriptor.fetchLimit = 1
        if let found = try context.fetch(descriptor).first {
            return found
        }
        let created = EventGroup(name: SeedGroups.ungroupedName, defaultOffsets: .dayOf, isUngrouped: true)
        context.insert(created)
        try context.save()
        return created
    }
}
