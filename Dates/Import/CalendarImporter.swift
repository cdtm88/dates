import Foundation
import EventKit
import DatesKit

/// Reads annual dates out of the user's calendars (Phase 05).
///
/// Only two kinds of calendar event are an annual date in this app's sense: entries in the
/// system Birthdays calendar, and events with a yearly recurrence rule. Everything else —
/// meetings, one-off appointments — is deliberately not offered, because importing it would
/// bury the dates the app exists for.
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
    /// calendar events, soonest first. The year is left unknown: an occurrence's year says
    /// when it next happens, not when the person was born, and a wrong age is worse than none.
    static func fetchCandidates(now: Date = Date(), calendar: Calendar = .current) async throws -> [ImportCandidate] {
        let eventStore = EKEventStore()
        guard try await eventStore.requestFullAccessToEvents() else {
            throw ImportError.accessDenied
        }

        guard let horizon = calendar.date(byAdding: .day, value: 366, to: now) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: now, end: horizon, calendars: nil)
        let events = eventStore.events(matching: predicate)

        var seen = Set<String>()
        return events.compactMap { event -> ImportCandidate? in
            guard let candidate = candidate(for: event, calendar: calendar) else { return nil }
            // The same recurring event appears once per occurrence in a date-range query;
            // and two calendars can carry the same person's birthday.
            guard seen.insert(candidate.duplicateKey).inserted else { return nil }
            return candidate
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
