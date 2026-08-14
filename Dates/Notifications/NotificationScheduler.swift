import Foundation
import OSLog
import UserNotifications
import DatesKit

/// What a scheduling pass actually achieved, as opposed to what the plan asked for.
///
/// The two differ when `UNUserNotificationCenter.add` rejects a request; hiding that gap
/// would make the coverage read-out in Settings optimistic (NOTIF-04).
struct ScheduleOutcome: Sendable {
    let plan: NotificationPlan
    /// How many requests the notification center actually accepted.
    let scheduledCount: Int

    var failedCount: Int { plan.count - scheduledCount }
}

/// The subset of `UNUserNotificationCenter` the scheduler uses, so tests can substitute a fake.
///
/// Authorisation is exposed as a bare status rather than `UNNotificationSettings`, which has
/// no public initialiser and therefore cannot be faked.
protocol NotificationCenterProtocol: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func currentAuthorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: NotificationCenterProtocol {
    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}

/// Owns the pending notification queue.
///
/// An actor, so a full reschedule of 500 events never runs on the main thread (PERF-03).
actor NotificationScheduler {
    static let shared = NotificationScheduler()

    /// Carried in `userInfo` so a tap can open the right event (NOTIF-10).
    static let eventIDUserInfoKey = "eventID"

    private static let logger = Logger(subsystem: "com.moorelabs.Dates", category: "notifications")

    private let center: NotificationCenterProtocol
    private let planner: NotificationPlanner

    /// The most recent scheduling pass. Actors are re-entrant at suspension points, so two
    /// overlapping reschedules could interleave their cancel and add phases; each pass waits
    /// for the previous one, making the most recent caller the last writer.
    private var inFlightReschedule: Task<ScheduleOutcome, Never>?

    init(
        center: NotificationCenterProtocol = UNUserNotificationCenter.current(),
        planner: NotificationPlanner = NotificationPlanner()
    ) {
        self.center = center
        self.planner = planner
    }

    // MARK: - Authorisation (NOTIF-01)

    /// Shows the system prompt. Called on first event save rather than first launch, so the
    /// ask arrives once the user has demonstrated they want reminders.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // A thrown error here means the prompt could not be shown. The app stays fully
            // usable for viewing and editing either way (NOTIF-01).
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.currentAuthorizationStatus()
    }

    private func canSchedule() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Scheduling

    /// Rebuilds the pending queue from scratch (NOTIF-05, NOTIF-07).
    ///
    /// Every app-owned request is removed and the fresh plan is added, rather than diffing.
    /// A request's identifier encodes only the event and the offset, not the fire date, so a
    /// diff by identifier would happily keep a request whose date is now wrong. At a ceiling
    /// of 60 the rewrite costs nothing.
    @discardableResult
    func reschedule(
        snapshots: [EventSnapshot],
        notificationTime: TimeOfDay,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> ScheduleOutcome {
        let previous = inFlightReschedule
        let task = Task {
            _ = await previous?.value
            return await self.performReschedule(
                snapshots: snapshots,
                notificationTime: notificationTime,
                now: now,
                calendar: calendar
            )
        }
        inFlightReschedule = task
        return await task.value
    }

    private func performReschedule(
        snapshots: [EventSnapshot],
        notificationTime: TimeOfDay,
        now: Date,
        calendar: Calendar
    ) async -> ScheduleOutcome {
        await cancelAllEventNotifications()

        guard await canSchedule() else {
            // Nothing to schedule against, but the plan is still returned so callers can show
            // coverage information without a permission grant.
            let plan = planner.plan(events: [], now: now, notificationTime: notificationTime, calendar: calendar)
            return ScheduleOutcome(plan: plan, scheduledCount: 0)
        }

        let plan = planner.plan(
            events: snapshots,
            now: now,
            notificationTime: notificationTime,
            calendar: calendar
        )

        var scheduledCount = 0
        for planned in plan.notifications {
            do {
                try await center.add(makeRequest(for: planned, calendar: calendar))
                scheduledCount += 1
            } catch {
                Self.logger.error("Could not schedule \(planned.identifier, privacy: .public): \(error)")
            }
        }

        return ScheduleOutcome(plan: plan, scheduledCount: scheduledCount)
    }

    /// Removes every pending request belonging to one event, matched on the identifier prefix
    /// so that an offset the user has just switched off is cleaned up too (NOTIF-07, D-08).
    func cancelNotifications(forEventID eventID: UUID) async {
        let prefix = NotificationIdentifier.eventPrefix(for: eventID)
        let identifiers = await pendingIdentifiers().filter { $0.hasPrefix(prefix) }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Removes only requests this app scheduled, never anything else pending on the device.
    func cancelAllEventNotifications() async {
        let identifiers = await pendingIdentifiers().filter(NotificationIdentifier.isEventIdentifier)
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    /// Count of app-owned pending requests, which is the number NOTIF-04 caps at 60.
    func pendingEventNotificationCount() async -> Int {
        await pendingIdentifiers().filter(NotificationIdentifier.isEventIdentifier).count
    }

    // MARK: - Request construction

    private func makeRequest(for planned: PlannedNotification, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = .default
        content.userInfo = [Self.eventIDUserInfoKey: planned.eventID.uuidString]

        // The components are deliberately left floating — no calendar or timezone pinned —
        // so the trigger means "09:00 on that day, wherever the device is". A pinned zone
        // would fire at the origin zone's 09:00 after the user travels or DST shifts.
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: planned.fireDate)

        // Non-repeating: the rolling window re-plans instead, because a repeating yearly
        // trigger per offset cannot fit inside the 64-request cap (D-06).
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        return UNNotificationRequest(identifier: planned.identifier, content: content, trigger: trigger)
    }
}
