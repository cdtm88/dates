import Foundation

/// Ordering and filtering for the home list (LIST-01, LIST-03, LIST-04).
public enum EventOrdering {

    /// Events sorted ascending by days-until-next-occurrence.
    ///
    /// An event dated today sorts first and stays there for the whole day, because
    /// `daysUntil` counts today as zero. It only moves to its next-year position once the
    /// device clock crosses local midnight (LIST-03, D-12).
    ///
    /// Ties break on name then id so the order is stable across launches rather than
    /// reshuffling two people who share a date.
    public static func sortedByNextOccurrence(
        _ events: [EventSnapshot],
        now: Date,
        calendar: Calendar = .current
    ) -> [EventSnapshot] {
        events
            .map { (event: $0, days: $0.daysUntil(from: now, calendar: calendar)) }
            .sorted { lhs, rhs in
                // An unrepresentable date sorts last rather than disappearing.
                switch (lhs.days, rhs.days) {
                case let (l?, r?) where l != r:
                    return l < r
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                default:
                    break
                }
                let nameOrder = lhs.event.name.localizedCaseInsensitiveCompare(rhs.event.name)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return lhs.event.id.uuidString < rhs.event.id.uuidString
            }
            .map(\.event)
    }

    /// Case- and diacritic-insensitive match on name only (PRD §9: search covers name only).
    public static func matches(_ event: EventSnapshot, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let name = event.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return name.contains(folded)
    }

    /// Applies the group filter and the search query, then sorts (LIST-04).
    ///
    /// Filtering happens before sorting so the expensive occurrence maths only runs over
    /// rows that survive, which is what keeps search under the 300ms budget at 500 events.
    public static func filteredAndSorted(
        _ events: [EventSnapshot],
        groupID: UUID? = nil,
        query: String = "",
        now: Date,
        calendar: Calendar = .current
    ) -> [EventSnapshot] {
        var filtered = events
        if let groupID {
            filtered = filtered.filter { $0.groupID == groupID }
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            filtered = filtered.filter { matches($0, query: trimmed) }
        }
        return sortedByNextOccurrence(filtered, now: now, calendar: calendar)
    }
}
