import Foundation

/// Which occurrences count as milestones — the years people most regret missing.
///
/// Pure year arithmetic, kept out of the views so the sets are assertable and the list,
/// detail and any future notification copy cannot disagree about what a milestone is.
public enum Milestone {

    /// Birthday ages marked beyond the round decades: firsts, coming-of-age years, and
    /// every decade from 10 up.
    private static let notableBirthdays: Set<Int> = [1, 13, 16, 18, 21]

    /// Anniversary (and other years-elapsed) milestones: the firsts and fives early on,
    /// then every decade and the silver anniversary.
    private static let notableAnniversaries: Set<Int> = [1, 5, 15, 25]

    /// Whether reaching `yearsElapsed` is a milestone for this event type.
    public static func isMilestone(type: EventType, yearsElapsed: Int) -> Bool {
        guard yearsElapsed > 0 else { return false }
        if yearsElapsed % 10 == 0 { return true }
        return type.countsAge
            ? notableBirthdays.contains(yearsElapsed)
            : notableAnniversaries.contains(yearsElapsed)
    }
}

extension EventSnapshot {
    /// The years figure the next occurrence reaches, when that figure is a milestone.
    /// Nil when the year is unknown (no age exists to celebrate) or the year is ordinary.
    public func milestoneYears(from now: Date, calendar: Calendar = .current) -> Int? {
        guard let years = yearsElapsed(from: now, calendar: calendar),
              Milestone.isMilestone(type: type, yearsElapsed: years) else { return nil }
        return years
    }
}
