import Foundation

/// A plain-value view of a stored event, produced from the SwiftData model.
///
/// Everything the app can get wrong — ordering, offset resolution, which notifications
/// to schedule — operates on snapshots, so it is all testable without a simulator.
public struct EventSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let type: EventType
    public let date: AnnualDate
    public let groupID: UUID
    public let groupName: String
    public let groupDefaultOffsets: OffsetSelection
    /// Per-event override. `nil` means "inherit the group default" (GROUP-04).
    public let offsetOverride: OffsetSelection?

    public init(
        id: UUID,
        name: String,
        type: EventType,
        date: AnnualDate,
        groupID: UUID,
        groupName: String,
        groupDefaultOffsets: OffsetSelection,
        offsetOverride: OffsetSelection? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.date = date
        self.groupID = groupID
        self.groupName = groupName
        self.groupDefaultOffsets = groupDefaultOffsets
        self.offsetOverride = offsetOverride
    }

    /// The offsets that actually apply to this event (GROUP-04).
    public var effectiveOffsets: OffsetSelection {
        OffsetResolver.effectiveOffsets(override: offsetOverride, groupDefault: groupDefaultOffsets)
    }

    public var inheritsGroupOffsets: Bool { offsetOverride == nil }

    // MARK: - Derived date facts

    public func nextOccurrence(from now: Date, calendar: Calendar = .current) -> Date? {
        date.nextOccurrence(from: now, calendar: calendar)
    }

    public func daysUntil(from now: Date, calendar: Calendar = .current) -> Int? {
        date.daysUntilNextOccurrence(from: now, calendar: calendar)
    }

    /// Age for a birthday, years elapsed for anything else. Nil when the year is unknown.
    public func yearsElapsed(from now: Date, calendar: Calendar = .current) -> Int? {
        date.yearsElapsedAtNextOccurrence(from: now, calendar: calendar)
    }

    public func isToday(_ now: Date, calendar: Calendar = .current) -> Bool {
        daysUntil(from: now, calendar: calendar) == 0
    }
}

/// Constraints applied when validating user or imported input (DATA-01).
public enum EventValidation {
    public static let nameLengthRange = 1...100

    public static func normalisedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A name is valid when, after trimming, it is 1 to 100 characters (DATA-01).
    public static func isValidName(_ raw: String) -> Bool {
        nameLengthRange.contains(normalisedName(raw).count)
    }
}
