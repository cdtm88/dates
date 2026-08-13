import Foundation

/// The single global time of day at which notifications fire (NOTIF-09, PRD §9).
public struct TimeOfDay: Hashable, Codable, Sendable, Comparable {
    public let hour: Int
    public let minute: Int

    /// Defaults to 09:00 local (NOTIF-09).
    public static let defaultNotificationTime = TimeOfDay(hour: 9, minute: 0)

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// Minutes since local midnight, used for persistence in a single integer.
    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public init(minutesSinceMidnight: Int) {
        let clamped = min(max(minutesSinceMidnight, 0), 24 * 60 - 1)
        self.init(hour: clamped / 60, minute: clamped % 60)
    }

    /// Applies this time to the day containing `day`, in `calendar`'s timezone.
    public func applied(to day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: day))
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}
