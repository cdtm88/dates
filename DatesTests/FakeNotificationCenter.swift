import Foundation
import UserNotifications
@testable import Dates

/// Stand-in for `UNUserNotificationCenter`, so scheduling behaviour can be asserted without
/// a device and without the system prompt.
final class FakeNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    var authorizationStatus: UNAuthorizationStatus = .authorized
    var authorizationGrantResult = true
    private(set) var authorizationRequestCount = 0
    private(set) var requests: [UNNotificationRequest] = []

    private let lock = NSLock()

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        lock.withLock { authorizationRequestCount += 1 }
        return authorizationGrantResult
    }

    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatus
    }

    func add(_ request: UNNotificationRequest) async throws {
        lock.withLock { requests.append(request) }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        lock.withLock { requests }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        let removals = Set(identifiers)
        lock.withLock { requests.removeAll { removals.contains($0.identifier) } }
    }

    // MARK: - Assertions helpers

    var identifiers: [String] {
        lock.withLock { requests.map(\.identifier) }
    }

    func identifiers(withPrefix prefix: String) -> [String] {
        identifiers.filter { $0.hasPrefix(prefix) }
    }

    /// The fire dates the center was actually handed, so a test can prove an edit moved them.
    func fireDateComponents(forPrefix prefix: String) -> [DateComponents] {
        lock.withLock {
            requests
                .filter { $0.identifier.hasPrefix(prefix) }
                .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents }
        }
    }
}
