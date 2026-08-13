import Foundation
import XCTest
@testable import DatesKit

/// A fixed calendar so every assertion is independent of the machine running the tests.
/// Europe/London is chosen deliberately: it observes DST, so day-counting bugs that a
/// UTC-only calendar would hide show up here.
enum TestCalendar {
    static let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()
}

func makeDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int = 12,
    _ minute: Int = 0,
    calendar: Calendar = TestCalendar.london,
    file: StaticString = #filePath,
    line: UInt = #line
) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    guard let date = calendar.date(from: components) else {
        XCTFail("Could not build \(year)-\(month)-\(day)", file: file, line: line)
        return Date(timeIntervalSince1970: 0)
    }
    return date
}

func annual(
    _ month: Int,
    _ day: Int,
    year: Int? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) -> AnnualDate {
    guard let date = AnnualDate(month: month, day: day, year: year) else {
        XCTFail("Expected \(month)/\(day)/\(year.map(String.init) ?? "-") to be a valid annual date", file: file, line: line)
        return AnnualDate(month: 1, day: 1)!
    }
    return date
}

let testGroupID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

func makeEvent(
    name: String = "Test Person",
    type: EventType = .birthday,
    date: AnnualDate,
    id: UUID = UUID(),
    groupID: UUID = testGroupID,
    groupName: String = "Friends",
    groupDefaultOffsets: OffsetSelection = .all,
    offsetOverride: OffsetSelection? = nil
) -> EventSnapshot {
    EventSnapshot(
        id: id,
        name: name,
        type: type,
        date: date,
        groupID: groupID,
        groupName: groupName,
        groupDefaultOffsets: groupDefaultOffsets,
        offsetOverride: offsetOverride
    )
}

/// Builds `count` events spread across distinct upcoming days, starting `startingInDays`
/// out, so ordering and coverage assertions are unambiguous.
func makeEvents(
    count: Int,
    from now: Date,
    startingInDays: Int = 30,
    spreadOverDays: Int = 300,
    offsets: OffsetSelection = .all,
    calendar: Calendar = TestCalendar.london
) -> [EventSnapshot] {
    (0..<count).compactMap { index -> EventSnapshot? in
        let dayOffset = startingInDays + (index % spreadOverDays)
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) else {
            return nil
        }
        let components = calendar.dateComponents([.month, .day], from: day)
        guard let month = components.month,
              let dayOfMonth = components.day,
              // A leap year, so a 29 February slot in the spread is still a valid date.
              let annualDate = AnnualDate(month: month, day: dayOfMonth, year: 2000)
        else { return nil }
        return makeEvent(
            name: String(format: "Person %04d", index),
            date: annualDate,
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
            groupDefaultOffsets: offsets
        )
    }
}

/// Runs `body` and returns how long it took, for the PRD's numeric performance budgets.
/// These are Linux measurements, not device measurements — they catch algorithmic
/// regressions, not the on-device figures PERF-01 to PERF-03 actually specify.
func measureDuration(_ body: () throws -> Void) rethrows -> TimeInterval {
    let start = Date()
    try body()
    return Date().timeIntervalSince(start)
}
