import Foundation
import Observation
import UserNotifications
import DatesKit

/// Turns a notification tap into a selection the list can navigate to (NOTIF-10).
///
/// Notifications are passive: opening the event's detail view is the only thing a tap does.
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    /// Set when a notification is tapped; the root view observes it and pushes the detail.
    var pendingEventID: UUID?

    func register() {
        UNUserNotificationCenter.current().delegate = self
    }

    func consumePendingEventID() -> UUID? {
        defer { pendingEventID = nil }
        return pendingEventID
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Prefer the identifier, which is authoritative, and fall back to userInfo.
        let identifier = response.notification.request.identifier
        let parsedID = NotificationIdentifier.parse(identifier)?.eventID
        let userInfoID = (response.notification.request.content.userInfo[NotificationScheduler.eventIDUserInfoKey] as? String)
            .flatMap(UUID.init(uuidString:))

        Task { @MainActor in
            self.pendingEventID = parsedID ?? userInfoID
            completionHandler()
        }
    }

    /// Show the alert even when the app is open, so a reminder that fires mid-session is not
    /// silently swallowed.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
