import Foundation

/// One notification the scheduler should have pending.
public struct PlannedNotification: Hashable, Sendable, Identifiable {
    public let identifier: String
    public let eventID: UUID
    public let offset: NotificationOffset
    /// Local midnight of the occurrence this notification is warning about.
    public let occurrence: Date
    /// The exact instant the notification fires, at the global notification time.
    public let fireDate: Date
    public let title: String
    public let body: String

    public var id: String { identifier }
}

/// The result of a planning pass.
public struct NotificationPlan: Hashable, Sendable {
    /// Sorted ascending by fire date.
    public let notifications: [PlannedNotification]
    /// Events that got their full set of schedulable offsets.
    public let coveredEventIDs: Set<UUID>
    /// True when the ceiling stopped the plan short of covering every event.
    public let wasTruncated: Bool

    public var count: Int { notifications.count }
    public var identifiers: [String] { notifications.map(\.identifier) }
    /// The furthest-out notification in the plan; how long the queue survives without a
    /// top-up if the user never opens the app (PRD §8 risk).
    public var coverageHorizon: Date? { notifications.last?.fireDate }

    public func notifications(forEvent eventID: UUID) -> [PlannedNotification] {
        notifications.filter { $0.eventID == eventID }
    }
}

/// Builds the rolling notification window (D-06).
///
/// iOS caps pending requests at 64, so repeating yearly triggers cannot cover a realistic
/// dataset: 100 events with three offsets each would need 300. Instead the queue holds the
/// nearest events only and is topped up on foreground and by background refresh.
///
/// Two rules define the fill:
///
/// 1. **Event order, not fire order.** Events are taken in ascending order of next
///    occurrence. Filling strictly by fire date would interleave offsets from different
///    events and leave the tail of the queue holding, say, a 7-day warning whose day-of
///    reminder did not fit — the one combination that is worse than no advance warning.
/// 2. **Whole events only.** An event is added with all of its schedulable offsets or not
///    at all, and the fill stops at the first event that does not fit. That guarantees the
///    nearest N events are completely covered (Phase 04 done criterion) at a cost of at
///    most two unused slots.
public struct NotificationPlanner: Sendable {
    /// Deliberately under the iOS limit of 64, leaving headroom so a mid-session event
    /// creation never silently fails to schedule (NOTIF-04, D-07).
    public static let defaultQueueCeiling = 60

    /// How far ahead to schedule. Longer than a year on purpose: the ceiling is the real
    /// constraint for a large dataset, and for a small one a long window means the queue
    /// covers every event for over a year, which is the main defence against the queue
    /// draining while the app goes unopened (PRD §8 risk).
    public static let defaultWindowDays = 400

    public let queueCeiling: Int
    public let windowDays: Int

    public init(queueCeiling: Int = defaultQueueCeiling, windowDays: Int = defaultWindowDays) {
        self.queueCeiling = max(0, queueCeiling)
        self.windowDays = max(0, windowDays)
    }

    public func plan(
        events: [EventSnapshot],
        now: Date,
        notificationTime: TimeOfDay = .defaultNotificationTime,
        calendar: Calendar = .current
    ) -> NotificationPlan {
        let today = calendar.startOfDay(for: now)
        let windowEnd = calendar.date(byAdding: .day, value: windowDays, to: today) ?? today

        var planned: [PlannedNotification] = []
        var covered: Set<UUID> = []
        var wasTruncated = false

        for event in EventOrdering.sortedByNextOccurrence(events, now: now, calendar: calendar) {
            let candidates = schedulableNotifications(
                for: event,
                now: now,
                today: today,
                windowEnd: windowEnd,
                notificationTime: notificationTime,
                calendar: calendar
            )
            // An event whose offsets have all already fired this year consumes no slots and
            // must not stop the fill.
            guard !candidates.isEmpty else { continue }

            guard planned.count + candidates.count <= queueCeiling else {
                wasTruncated = true
                break
            }
            planned.append(contentsOf: candidates)
            covered.insert(event.id)
        }

        planned.sort { lhs, rhs in
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            return lhs.identifier < rhs.identifier
        }

        return NotificationPlan(
            notifications: planned,
            coveredEventIDs: covered,
            wasTruncated: wasTruncated
        )
    }

    /// Every offset of one event that can still fire: not already past, and inside the window.
    private func schedulableNotifications(
        for event: EventSnapshot,
        now: Date,
        today: Date,
        windowEnd: Date,
        notificationTime: TimeOfDay,
        calendar: Calendar
    ) -> [PlannedNotification] {
        let offsets = event.effectiveOffsets
        guard !offsets.isEmpty else { return [] }
        guard let occurrence = event.nextOccurrence(from: now, calendar: calendar) else { return [] }

        let yearsElapsed = event.yearsElapsed(from: now, calendar: calendar)
        let body = NotificationContentBuilder.body(
            name: event.name,
            type: event.type,
            yearsElapsed: yearsElapsed
        )

        return offsets.offsets.compactMap { offset in
            guard let fireDay = calendar.date(byAdding: .day, value: -offset.daysBefore, to: occurrence),
                  let fireDate = notificationTime.applied(to: fireDay, calendar: calendar)
            else { return nil }
            // Compared on the day so that a window boundary does not depend on the
            // configured notification time.
            guard fireDay <= windowEnd else { return nil }
            // A notification whose moment has passed — including the day-of alert for an
            // event that is today, when the configured time is already behind us — is
            // dropped rather than fired late.
            guard fireDate > now else { return nil }

            return PlannedNotification(
                identifier: NotificationIdentifier.make(eventID: event.id, offset: offset),
                eventID: event.id,
                offset: offset,
                occurrence: occurrence,
                fireDate: fireDate,
                title: NotificationContentBuilder.title(for: offset),
                body: body
            )
        }
    }
}
