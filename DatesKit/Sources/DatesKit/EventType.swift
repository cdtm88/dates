import Foundation

/// The three event types fixed for v1 (PRD §9: users cannot define custom types).
public enum EventType: String, Codable, CaseIterable, Hashable, Sendable {
    case birthday
    case anniversary
    case other

    /// Title-case label for pickers and detail rows.
    public var displayName: String {
        switch self {
        case .birthday: return "Birthday"
        case .anniversary: return "Anniversary"
        case .other: return "Key date"
        }
    }

    /// Lowercase noun used inside notification bodies (NOTIF-08).
    public var notificationNoun: String {
        switch self {
        case .birthday: return "birthday"
        case .anniversary: return "anniversary"
        case .other: return "key date"
        }
    }

    /// How a known year is described for this type: an age for a birthday,
    /// elapsed years for anything else (DATA-03).
    public var countsAge: Bool {
        self == .birthday
    }
}
