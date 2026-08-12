import Foundation
import BackgroundTasks
import SwiftData
import DatesKit

/// Reads events off the main actor so a background top-up never touches the UI context.
@ModelActor
actor EventSnapshotProvider {
    func snapshots() throws -> [EventSnapshot] {
        try modelContext.fetch(FetchDescriptor<DateEvent>()).map(\.snapshot)
    }
}

/// Background top-up of the pending queue (NOTIF-06, D-09).
///
/// The rolling window means the queue eventually drains if the app is never opened. This is
/// the mitigation, and it is best-effort by design: iOS decides whether and when to run the
/// task, so a user who ignores the app for months may still miss alerts (PRD §8).
enum BackgroundRefresh {
    /// Must also appear in `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let taskIdentifier = "com.cdtm88.Dates.queueTopUp"

    /// Asks for another run. Called after each refresh and on entering the background, since
    /// a submitted request is consumed once it runs.
    static func scheduleNextRefresh(earliestAfter interval: TimeInterval = 12 * 60 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Submission fails on the simulator and when the user has disabled Background App
            // Refresh. Neither is recoverable and neither should affect the app.
        }
    }

    /// The work performed when iOS grants a run: re-plan and rewrite the queue.
    static func performRefresh(container: ModelContainer, notificationTime: TimeOfDay) async {
        let provider = EventSnapshotProvider(modelContainer: container)
        let snapshots = (try? await provider.snapshots()) ?? []
        await NotificationScheduler.shared.reschedule(
            snapshots: snapshots,
            notificationTime: notificationTime
        )
        scheduleNextRefresh()
    }
}
