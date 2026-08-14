import Foundation
import OSLog
import SwiftData
import Observation
import WidgetKit
import DatesKit

enum EventStoreError: LocalizedError {
    case invalidName
    case missingGroup

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Enter a name between 1 and 100 characters."
        case .missingGroup: return "This event could not be assigned to a group."
        }
    }
}

/// What the last scheduling pass produced, surfaced in Settings so the 60-request ceiling is
/// observable on device rather than only in tests (NOTIF-04, success criterion 4).
struct QueueSummary: Equatable {
    var scheduledCount: Int
    var ceiling: Int
    var coveredEventCount: Int
    var totalEventCount: Int
    var coverageHorizon: Date?
    var wasTruncated: Bool
    /// Requests the plan wanted but the notification center rejected. Non-zero is abnormal
    /// and surfaced in Settings rather than silently shrinking coverage.
    var failedCount: Int
}

/// Every mutation goes through here.
///
/// Centralising writes is what makes NOTIF-07 enforceable: there is one place that saves an
/// event and one place that reschedules, so no view can add an event without the queue being
/// rebuilt before the call returns.
@MainActor
@Observable
final class EventStore {
    private static let logger = Logger(subsystem: "com.moorelabs.Dates", category: "store")

    private let context: ModelContext
    private let scheduler: NotificationScheduler
    private let settings: AppSettings

    private(set) var queueSummary: QueueSummary?

    init(context: ModelContext, scheduler: NotificationScheduler = .shared, settings: AppSettings) {
        self.context = context
        self.scheduler = scheduler
        self.settings = settings
    }

    // MARK: - Reads

    func allEvents() -> [DateEvent] {
        do {
            return try context.fetch(FetchDescriptor<DateEvent>())
        } catch {
            // An empty list is indistinguishable from having no events, so a failed fetch
            // must at least be loud in diagnostics.
            Self.logger.fault("Event fetch failed: \(error)")
            return []
        }
    }

    func snapshots() -> [EventSnapshot] {
        allEvents().map(\.snapshot)
    }

    func ungroupedGroup() throws -> EventGroup {
        try DatesModelContainer.ungroupedGroup(context)
    }

    // MARK: - Events

    @discardableResult
    func createEvent(
        name: String,
        date: AnnualDate,
        type: EventType,
        group: EventGroup?,
        offsetOverride: OffsetSelection? = nil
    ) async throws -> DateEvent {
        let trimmed = EventValidation.normalisedName(name)
        guard EventValidation.isValidName(trimmed) else { throw EventStoreError.invalidName }

        let resolvedGroup = try group ?? ungroupedGroup()
        let event = DateEvent(
            name: trimmed,
            date: date,
            type: type,
            group: resolvedGroup,
            offsetOverride: offsetOverride
        )
        context.insert(event)
        try context.save()

        // The permission prompt arrives on the first save, not at launch (NOTIF-01).
        await requestAuthorisationOnFirstSave()
        await rescheduleAll()
        return event
    }

    func updateEvent(
        _ event: DateEvent,
        name: String,
        date: AnnualDate,
        type: EventType,
        group: EventGroup?,
        offsetOverride: OffsetSelection?
    ) async throws {
        let trimmed = EventValidation.normalisedName(name)
        guard EventValidation.isValidName(trimmed) else { throw EventStoreError.invalidName }

        event.name = trimmed
        event.setAnnualDate(date)
        event.type = type
        event.group = try group ?? ungroupedGroup()
        event.offsetOverride = offsetOverride
        event.touch()
        try context.save()

        // Cancel by identifier prefix first: the event's date may have moved, and an offset
        // may have been switched off, so a plain re-add would leave stale requests (NOTIF-07).
        await scheduler.cancelNotifications(forEventID: event.uuid)
        await rescheduleAll()
    }

    func deleteEvent(_ event: DateEvent) async throws {
        let eventID = event.uuid
        context.delete(event)
        try context.save()

        await scheduler.cancelNotifications(forEventID: eventID)
        await rescheduleAll()
    }

    // MARK: - Import (Phase 05)

    /// Inserts a batch of already-validated candidates with one save and one reschedule.
    ///
    /// Import goes through the store like every other write (NOTIF-07), but not through
    /// `createEvent` in a loop — a 200-row CSV must not rebuild the notification queue 200
    /// times. Candidates naming an existing group (matched case-insensitively) join it;
    /// everything else goes to `fallbackGroup`. Duplicates of stored events are screened
    /// out again here, so re-importing a file cannot double the list even if a caller
    /// bypasses the review step.
    @discardableResult
    func importEvents(_ candidates: [ImportCandidate], fallbackGroup: EventGroup?) async throws -> Int {
        let (fresh, _) = ImportScreening.partition(candidates, existing: snapshots())
        guard !fresh.isEmpty else { return 0 }

        let resolvedFallback = try fallbackGroup ?? ungroupedGroup()
        let groups = try context.fetch(FetchDescriptor<EventGroup>())
        let groupsByName = Dictionary(
            groups.map { ($0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for candidate in fresh {
            let namedGroup = candidate.groupName.flatMap {
                groupsByName[$0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)]
            }
            let event = DateEvent(
                name: candidate.name,
                date: candidate.date,
                type: candidate.type,
                group: namedGroup ?? resolvedFallback
            )
            context.insert(event)
        }
        try context.save()

        await requestAuthorisationOnFirstSave()
        await rescheduleAll()
        return fresh.count
    }

    // MARK: - Groups

    @discardableResult
    func createGroup(name: String, defaultOffsets: OffsetSelection) throws -> EventGroup {
        let trimmed = EventValidation.normalisedName(name)
        guard EventValidation.isValidName(trimmed) else { throw EventStoreError.invalidName }
        let group = EventGroup(name: trimmed, defaultOffsets: defaultOffsets)
        context.insert(group)
        try context.save()
        return group
    }

    /// Renaming or changing defaults reschedules, because every event in the group that has
    /// no override has just had its effective offsets change (GROUP-05).
    func updateGroup(_ group: EventGroup, name: String, defaultOffsets: OffsetSelection) async throws {
        let trimmed = EventValidation.normalisedName(name)
        guard EventValidation.isValidName(trimmed) else { throw EventStoreError.invalidName }

        let offsetsChanged = group.defaultOffsets != defaultOffsets
        group.name = trimmed
        group.defaultOffsets = defaultOffsets
        try context.save()

        if offsetsChanged {
            await rescheduleAll()
        }
    }

    /// Deleting a group reassigns its events to Ungrouped rather than deleting them (GROUP-02).
    func deleteGroup(_ group: EventGroup) async throws {
        guard group.isDeletable else { return }
        let ungrouped = try ungroupedGroup()

        for event in group.events ?? [] {
            event.group = ungrouped
            event.touch()
        }
        context.delete(group)
        try context.save()

        // Those events now inherit a different default set, so the queue is rebuilt.
        await rescheduleAll()
    }

    // MARK: - Scheduling

    /// Rebuilds the pending queue and records what it produced.
    ///
    /// Called on foreground (NOTIF-05), after every mutation (NOTIF-07), and whenever the
    /// global notification time changes (NOTIF-09).
    func rescheduleAll(now: Date = Date(), calendar: Calendar = .current) async {
        let snapshots = snapshots()

        // The widget rides the same trigger set as the queue: every mutation, foreground,
        // and time change lands here, so the shared file can never go stale on its own.
        WidgetBridge.write(snapshots.map(WidgetEvent.init))
        WidgetCenter.shared.reloadAllTimelines()

        let outcome = await scheduler.reschedule(
            snapshots: snapshots,
            notificationTime: settings.notificationTime,
            now: now,
            calendar: calendar
        )
        queueSummary = QueueSummary(
            scheduledCount: outcome.scheduledCount,
            ceiling: NotificationPlanner.defaultQueueCeiling,
            coveredEventCount: outcome.plan.coveredEventIDs.count,
            totalEventCount: snapshots.count,
            coverageHorizon: outcome.plan.coverageHorizon,
            wasTruncated: outcome.plan.wasTruncated,
            failedCount: outcome.failedCount
        )
    }

    private func requestAuthorisationOnFirstSave() async {
        guard !settings.hasRequestedNotificationAuthorisation else { return }
        settings.hasRequestedNotificationAuthorisation = true
        _ = await scheduler.requestAuthorization()
    }
}
