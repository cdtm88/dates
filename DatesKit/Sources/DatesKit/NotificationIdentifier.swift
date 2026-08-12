import Foundation

/// Deterministic notification identifiers, formatted `evt-{uuid}-{offset}` (D-08).
///
/// Because the identifier is derived from the event id and the offset, an edit can cancel
/// exactly the requests belonging to one event without maintaining a separate index
/// (NOTIF-07).
public enum NotificationIdentifier {
    public static let prefix = "evt-"

    public static func make(eventID: UUID, offset: NotificationOffset) -> String {
        "\(prefix)\(eventID.uuidString)-\(offset.rawValue)"
    }

    /// The prefix shared by every request belonging to one event. Cancellation matches on
    /// this rather than enumerating offsets, so an offset removed from the set is still
    /// cleaned up.
    public static func eventPrefix(for eventID: UUID) -> String {
        "\(prefix)\(eventID.uuidString)-"
    }

    public static func parse(_ identifier: String) -> (eventID: UUID, offset: NotificationOffset)? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let remainder = identifier.dropFirst(prefix.count)
        // The UUID itself contains hyphens, so split on the last one.
        guard let separator = remainder.lastIndex(of: "-") else { return nil }
        guard let eventID = UUID(uuidString: String(remainder[remainder.startIndex..<separator])),
              let rawOffset = Int(remainder[remainder.index(after: separator)...]),
              let offset = NotificationOffset(rawValue: rawOffset)
        else { return nil }
        return (eventID, offset)
    }

    /// Whether a pending request belongs to the app at all, used to avoid cancelling
    /// anything the app did not schedule.
    public static func isEventIdentifier(_ identifier: String) -> Bool {
        parse(identifier) != nil
    }
}
