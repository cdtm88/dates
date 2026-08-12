import Foundation
import SwiftData
import DatesKit

/// Container construction and first-launch seeding.
enum DatesModelContainer {
    static let schema = Schema([DateEvent.self, EventGroup.self])

    /// The on-disk container.
    ///
    /// Phase 06 turns CloudKit on here by passing `cloudKitDatabase: .private(...)`. The
    /// schema is already CloudKit-shaped — every attribute has a default and every
    /// relationship is optional — so that change needs no migration (D-03, D-04).
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return container
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
