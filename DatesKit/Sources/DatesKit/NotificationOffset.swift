import Foundation

/// The three notification offsets fixed for v1 (PRD §9: no arbitrary custom offsets).
/// The raw value is the number of days before the event, and is also the suffix used
/// in notification identifiers (D-08).
public enum NotificationOffset: Int, Codable, CaseIterable, Hashable, Sendable, Comparable {
    case dayOf = 0
    case threeDays = 3
    case sevenDays = 7

    public var daysBefore: Int { rawValue }

    /// Ordered soonest-firing first: the 7-day alert fires before the 3-day, which
    /// fires before the day-of.
    public static var fireOrder: [NotificationOffset] { [.sevenDays, .threeDays, .dayOf] }

    public var shortLabel: String {
        switch self {
        case .dayOf: return "On the day"
        case .threeDays: return "3 days before"
        case .sevenDays: return "7 days before"
        }
    }

    public static func < (lhs: NotificationOffset, rhs: NotificationOffset) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A set of offsets, stored as a bitmask so SwiftData persists it as a single Int and
/// equality is order-independent.
public struct OffsetSelection: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let dayOf = OffsetSelection(rawValue: 1 << 0)
    public static let threeDays = OffsetSelection(rawValue: 1 << 1)
    public static let sevenDays = OffsetSelection(rawValue: 1 << 2)

    public static let empty: OffsetSelection = []
    public static let all: OffsetSelection = [.dayOf, .threeDays, .sevenDays]

    public init(_ offsets: some Sequence<NotificationOffset>) {
        var mask = 0
        for offset in offsets {
            mask |= Self.flag(for: offset).rawValue
        }
        self.rawValue = mask
    }

    public static func flag(for offset: NotificationOffset) -> OffsetSelection {
        switch offset {
        case .dayOf: return .dayOf
        case .threeDays: return .threeDays
        case .sevenDays: return .sevenDays
        }
    }

    public func contains(_ offset: NotificationOffset) -> Bool {
        contains(Self.flag(for: offset))
    }

    /// The selected offsets in the order they fire: 7-day, then 3-day, then day-of.
    public var offsets: [NotificationOffset] {
        NotificationOffset.fireOrder.filter { contains($0) }
    }

    /// The selected offsets ordered for display: on the day, then 3, then 7.
    public var displayOrderedOffsets: [NotificationOffset] {
        offsets.sorted()
    }

    public var count: Int { offsets.count }
}
