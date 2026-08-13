import Foundation

/// A date that recurs every year, stored as discrete month/day/optional-year components
/// rather than a single `Date` (D-11). A recurring annual event has no single instant,
/// so component storage avoids timezone drift and makes the 29 February rule explicit.
public struct AnnualDate: Hashable, Codable, Sendable {
    public let month: Int
    public let day: Int
    /// The originating year (year of birth, year of the wedding). `nil` when unknown,
    /// in which case no age or years-elapsed is ever displayed (DATA-03).
    public let year: Int?

    /// A leap year, used to validate a day-of-month when no year is stored, so that
    /// 29 February is accepted as a year-unknown date.
    private static let referenceLeapYear = 2000

    /// Fixed calendar for validation so that constructing an `AnnualDate` gives the same
    /// answer regardless of the device's current calendar or timezone.
    private static let validationCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    /// Fails when the components do not describe a real date, including 29 February
    /// paired with a stored non-leap year.
    public init?(month: Int, day: Int, year: Int? = nil) {
        guard (1...12).contains(month) else { return nil }
        let validationYear = year ?? Self.referenceLeapYear
        guard let maxDay = Self.daysInMonth(month, year: validationYear, calendar: Self.validationCalendar),
              (1...maxDay).contains(day)
        else { return nil }
        if let year, year < 1 || year > 9999 { return nil }
        self.month = month
        self.day = day
        self.year = year
    }

    public var hasKnownYear: Bool { year != nil }

    // MARK: - Occurrences

    /// Number of days in `month` of `year`, or nil for a calendar that cannot represent it.
    public static func daysInMonth(_ month: Int, year: Int, calendar: Calendar) -> Int? {
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else { return nil }
        return range.count
    }

    /// The day-of-month this date resolves to in `targetYear`.
    ///
    /// A 29 February date resolves to 28 February in a non-leap year rather than rolling
    /// forward to 1 March (DATA-04, PRD §9). Implemented as a clamp to the month's length,
    /// which produces exactly that behaviour and is correct for every other month too.
    public func resolvedDay(inYear targetYear: Int, calendar: Calendar = .current) -> Int? {
        guard let maxDay = Self.daysInMonth(month, year: targetYear, calendar: calendar) else { return nil }
        return min(day, maxDay)
    }

    /// Local midnight at the start of this date's occurrence in `targetYear`.
    public func occurrence(inYear targetYear: Int, calendar: Calendar = .current) -> Date? {
        guard let resolvedDay = resolvedDay(inYear: targetYear, calendar: calendar) else { return nil }
        var components = DateComponents()
        components.year = targetYear
        components.month = month
        components.day = resolvedDay
        guard let date = calendar.date(from: components) else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// The calendar year of the next occurrence, counting today as the occurrence (D-12).
    public func nextOccurrenceYear(from now: Date, calendar: Calendar = .current) -> Int? {
        let today = calendar.startOfDay(for: now)
        let currentYear = calendar.component(.year, from: today)
        if let thisYear = occurrence(inYear: currentYear, calendar: calendar), thisYear >= today {
            return currentYear
        }
        guard occurrence(inYear: currentYear + 1, calendar: calendar) != nil else { return nil }
        return currentYear + 1
    }

    /// Local midnight of the next occurrence.
    ///
    /// An event dated today returns today, not next year: it stays at the top of the list
    /// for the whole day and only rolls over at the local-midnight boundary (LIST-03, D-12).
    public func nextOccurrence(from now: Date, calendar: Calendar = .current) -> Date? {
        guard let year = nextOccurrenceYear(from: now, calendar: calendar) else { return nil }
        return occurrence(inYear: year, calendar: calendar)
    }

    /// Whole days from today until the next occurrence. `0` means today.
    public func daysUntilNextOccurrence(from now: Date, calendar: Calendar = .current) -> Int? {
        guard let next = nextOccurrence(from: now, calendar: calendar) else { return nil }
        let today = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: today, to: next).day
    }

    /// The age, or years elapsed, this date will reach on its next occurrence.
    ///
    /// Returns nil when no year is stored, so the UI displays no number (DATA-03).
    /// Also returns nil for a stored year later than the next occurrence, which is only
    /// reachable via bad data and has no sensible number to show.
    public func yearsElapsedAtNextOccurrence(from now: Date, calendar: Calendar = .current) -> Int? {
        guard let year, let occurrenceYear = nextOccurrenceYear(from: now, calendar: calendar) else { return nil }
        let elapsed = occurrenceYear - year
        return elapsed >= 0 ? elapsed : nil
    }
}

extension AnnualDate: CustomStringConvertible {
    public var description: String {
        let base = String(format: "%02d-%02d", month, day)
        guard let year else { return base }
        return "\(year)-\(base)"
    }
}
