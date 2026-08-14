import Foundation
import DatesKit

/// Display strings for the list and detail views (LIST-02).
///
/// Formatters are cached: building a `DateFormatter` per row is the classic way to lose the
/// 60fps budget on a long list (PERF-02).
enum EventFormatting {
    private static let dayAndMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter
    }()

    private static let dayMonthAndYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMMM y")
        return formatter
    }()

    private static let weekdayDayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter
    }()

    private static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// Cached once: the picker asks for these twelve times per redraw.
    static let monthNames: [String] = {
        let formatter = DateFormatter()
        return formatter.standaloneMonthSymbols ?? formatter.monthSymbols ?? []
    }()

    static func monthName(_ month: Int) -> String {
        guard month >= 1, month <= monthNames.count else { return "\(month)" }
        return monthNames[month - 1]
    }

    /// "12 September" — the recurring date itself, never a year.
    static func recurringDate(_ event: EventSnapshot, now: Date, calendar: Calendar = .current) -> String {
        guard let occurrence = event.nextOccurrence(from: now, calendar: calendar) else {
            return "\(event.date.day)/\(event.date.month)"
        }
        dayAndMonth.calendar = calendar
        dayAndMonth.timeZone = calendar.timeZone
        return dayAndMonth.string(from: occurrence)
    }

    /// "Friday 12 September" — used in the detail view where there is room.
    static func nextOccurrenceLong(_ event: EventSnapshot, now: Date, calendar: Calendar = .current) -> String {
        guard let occurrence = event.nextOccurrence(from: now, calendar: calendar) else { return "—" }
        weekdayDayMonth.calendar = calendar
        weekdayDayMonth.timeZone = calendar.timeZone
        return weekdayDayMonth.string(from: occurrence)
    }

    /// "Today", "Tomorrow", "In 12 days".
    static func daysUntil(_ event: EventSnapshot, now: Date, calendar: Calendar = .current) -> String {
        guard let days = event.daysUntil(from: now, calendar: calendar) else { return "—" }
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return "In \(days) days"
        }
    }

    /// The age or years elapsed, or nil when the year is unknown so nothing is shown (DATA-03).
    static func yearsBadge(_ event: EventSnapshot, now: Date, calendar: Calendar = .current) -> String? {
        guard let years = event.yearsElapsed(from: now, calendar: calendar) else { return nil }
        if event.type.countsAge {
            return "Turns \(years)"
        }
        return years == 1 ? "1 year" : "\(years) years"
    }

    /// The originating year, for the detail view.
    static func knownYear(_ event: EventSnapshot) -> String? {
        event.date.year.map(String.init)
    }

    /// One line for a milestone year, or nil in an ordinary year so nothing is shown.
    static func milestoneLine(_ event: EventSnapshot, now: Date, calendar: Calendar = .current) -> String? {
        guard let years = event.milestoneYears(from: now, calendar: calendar) else { return nil }
        if event.type.countsAge {
            return "Turns \(years) — a milestone birthday"
        }
        let unit = years == 1 ? "year" : "years"
        return "\(years) \(unit) — a milestone"
    }

    static func offsetsSummary(_ offsets: OffsetSelection) -> String {
        guard !offsets.isEmpty else { return "No alerts" }
        return offsets.displayOrderedOffsets.map(\.shortLabel).joined(separator: ", ")
    }

    static func notificationTime(_ time: TimeOfDay, calendar: Calendar = .current) -> String {
        guard let date = time.applied(to: Date(), calendar: calendar) else {
            return String(format: "%02d:%02d", time.hour, time.minute)
        }
        return timeOnly.string(from: date)
    }

    /// A single spoken sentence per row, so VoiceOver reads one coherent line rather than
    /// five disconnected fragments (A11Y-01 groundwork).
    static func accessibilityLabel(_ event: EventSnapshot, now: Date, calendar: Calendar = .current) -> String {
        var parts = [event.name, event.type.displayName, recurringDate(event, now: now, calendar: calendar)]
        parts.append(daysUntil(event, now: now, calendar: calendar))
        if let badge = yearsBadge(event, now: now, calendar: calendar) {
            parts.append(badge)
            if event.milestoneYears(from: now, calendar: calendar) != nil {
                parts.append("a milestone")
            }
        }
        parts.append("Group \(event.groupName)")
        return parts.joined(separator: ", ")
    }
}
