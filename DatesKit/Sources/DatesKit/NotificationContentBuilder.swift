import Foundation

/// Builds notification copy. Kept free of `UNNotificationContent` so the exact strings are
/// assertable on any platform (NOTIF-08).
public enum NotificationContentBuilder {

    /// The lead line, which is how far away the event is.
    public static func title(for offset: NotificationOffset) -> String {
        switch offset {
        case .dayOf: return "Today"
        case .threeDays: return "In 3 days"
        case .sevenDays: return "In 7 days"
        }
    }

    /// The body states the name, the event type, and the age or years elapsed where the
    /// year is known (NOTIF-08). Where the year is unknown no number appears (DATA-03).
    ///
    /// Possessives are avoided so that names ending in "s" do not need special casing, and
    /// no ordinal formatting is used so the copy is identical in every locale.
    public static func body(name: String, type: EventType, yearsElapsed: Int?) -> String {
        let trimmedName = EventValidation.normalisedName(name)
        guard let yearsElapsed else {
            return "\(trimmedName) — \(type.notificationNoun)."
        }
        if type.countsAge {
            return "\(trimmedName) — \(type.notificationNoun), turning \(yearsElapsed)."
        }
        let unit = yearsElapsed == 1 ? "year" : "years"
        return "\(trimmedName) — \(type.notificationNoun), \(yearsElapsed) \(unit)."
    }

    public static func body(for event: EventSnapshot, now: Date, calendar: Calendar = .current) -> String {
        body(
            name: event.name,
            type: event.type,
            yearsElapsed: event.yearsElapsed(from: now, calendar: calendar)
        )
    }
}
