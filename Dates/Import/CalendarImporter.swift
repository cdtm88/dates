import Foundation
import EventKit
import DatesKit

/// Reads annual dates out of the user's calendars (Phase 05).
///
/// Only two kinds of calendar event are an annual date in this app's sense: entries in the
/// system Birthdays calendar, and events with a yearly recurrence rule. Everything else —
/// meetings, one-off appointments — is deliberately not offered, because importing it would
/// bury the dates the app exists for.
/// The candidates one calendar produced, so the user can choose whole calendars before
/// reviewing individual dates — a subscribed holiday calendar is one switch, not fifteen.
struct CalendarCandidates: Identifiable, Equatable, Sendable {
    /// EventKit's `calendarIdentifier`.
    let id: String
    let title: String
    /// Subscribed calendars (public holidays and the like) start deselected.
    let isSubscribed: Bool
    let candidates: [ImportCandidate]
}

enum CalendarImporter {

    enum ImportError: LocalizedError {
        case accessDenied

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Dates can't see your calendar. Allow calendar access in the Settings app to import."
            }
        }
    }

    /// Requests read access if needed, then returns candidates from the next year of
    /// calendar events, grouped by the calendar they came from. The year is left unknown:
    /// an occurrence's year says when it next happens, not when the person was born, and a
    /// wrong age is worse than none.
    static func fetchCandidatesByCalendar(now: Date = Date(), calendar: Calendar = .current) async throws -> [CalendarCandidates] {
        let eventStore = EKEventStore()
        guard try await eventStore.requestFullAccessToEvents() else {
            throw ImportError.accessDenied
        }

        guard let horizon = calendar.date(byAdding: .day, value: 366, to: now) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: now, end: horizon, calendars: nil)
        let events = eventStore.events(matching: predicate)

        var order: [String] = []
        var titles: [String: String] = [:]
        var subscribed: [String: Bool] = [:]
        var grouped: [String: [ImportCandidate]] = [:]
        // Deduplication is per-calendar here: the same recurring event appears once per
        // occurrence in a date-range query. Cross-calendar duplicates survive until the
        // user has picked calendars, then merge screens them out.
        var seen: [String: Set<String>] = [:]

        for event in events {
            guard let candidate = candidate(for: event, calendar: calendar) else { continue }
            let source = event.calendar
            let id = source?.calendarIdentifier ?? "unknown"
            if titles[id] == nil {
                order.append(id)
                titles[id] = source?.title ?? "Calendar"
                subscribed[id] = source?.type == .subscription
            }
            guard seen[id, default: []].insert(candidate.duplicateKey).inserted else { continue }
            grouped[id, default: []].append(candidate)
        }

        return order
            .map { id in
                CalendarCandidates(
                    id: id,
                    title: titles[id] ?? "Calendar",
                    isSubscribed: subscribed[id] ?? false,
                    candidates: grouped[id] ?? []
                )
            }
            .sorted { lhs, rhs in
                if lhs.isSubscribed != rhs.isSubscribed { return !lhs.isSubscribed }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private static func candidate(for event: EKEvent, calendar: Calendar) -> ImportCandidate? {
        let isBirthday = event.calendar?.type == .birthday
        let recursYearly = event.hasRecurrenceRules
            && event.recurrenceRules?.contains { $0.frequency == .yearly && $0.interval == 1 } == true
        guard isBirthday || recursYearly else { return nil }

        guard let start = event.startDate else { return nil }
        let components = calendar.dateComponents([.month, .day], from: start)
        guard let month = components.month, let day = components.day,
              let date = AnnualDate(month: month, day: day)
        else { return nil }

        let name = cleanedName(event.title ?? "", isBirthday: isBirthday)
        guard EventValidation.isValidName(name) else { return nil }

        return ImportCandidate(
            name: EventValidation.normalisedName(name),
            type: isBirthday ? .birthday : .other,
            date: date
        )
    }

    /// The Birthdays calendar titles entries like "Anna Smith’s Birthday"; the list wants
    /// the person, not the sentence. English-style possessive suffixes are stripped, and a
    /// title in any other shape is kept whole rather than guessed at.
    private static func cleanedName(_ title: String, isBirthday: Bool) -> String {
        guard isBirthday else { return title }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["’s Birthday", "'s Birthday", "’s birthday", "'s birthday"] {
            if trimmed.hasSuffix(suffix) {
                return String(trimmed.dropLast(suffix.count))
            }
        }
        return trimmed
    }
}
