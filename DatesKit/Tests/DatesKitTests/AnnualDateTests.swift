import XCTest
@testable import DatesKit

/// Phase 01 — DATA-01, DATA-03, DATA-04, and the LIST-03 rollover boundary.
final class AnnualDateTests: XCTestCase {
    private let calendar = TestCalendar.london

    // MARK: - Construction (DATA-01)

    func testRejectsImpossibleComponents() {
        XCTAssertNil(AnnualDate(month: 0, day: 10))
        XCTAssertNil(AnnualDate(month: 13, day: 10))
        XCTAssertNil(AnnualDate(month: 1, day: 0))
        XCTAssertNil(AnnualDate(month: 1, day: 32))
        XCTAssertNil(AnnualDate(month: 2, day: 30))
        XCTAssertNil(AnnualDate(month: 4, day: 31))
    }

    func test29FebruaryIsValidWithoutAYearAndWithALeapYear() {
        XCTAssertNotNil(AnnualDate(month: 2, day: 29))
        XCTAssertNotNil(AnnualDate(month: 2, day: 29, year: 2000))
    }

    func test29FebruaryIsRejectedWhenPairedWithANonLeapYear() {
        XCTAssertNil(AnnualDate(month: 2, day: 29, year: 2001))
    }

    // MARK: - Leap day resolution (DATA-04)

    func test29FebruaryResolvesTo28FebruaryInANonLeapYear() {
        let leapDay = annual(2, 29, year: 2000)
        XCTAssertEqual(leapDay.resolvedDay(inYear: 2027, calendar: calendar), 28)
        XCTAssertEqual(
            leapDay.occurrence(inYear: 2027, calendar: calendar),
            calendar.startOfDay(for: makeDate(2027, 2, 28))
        )
    }

    func test29FebruaryStaysOn29FebruaryInALeapYear() {
        let leapDay = annual(2, 29, year: 2000)
        XCTAssertEqual(leapDay.resolvedDay(inYear: 2028, calendar: calendar), 29)
        XCTAssertEqual(
            leapDay.occurrence(inYear: 2028, calendar: calendar),
            calendar.startOfDay(for: makeDate(2028, 2, 29))
        )
    }

    func test29FebruaryNormalisesBackwardsNotForwards() {
        // The PRD picks 28 February over 1 March (§9). Assert the rejected option too,
        // because both are one day from the stored date and only one is correct.
        let leapDay = annual(2, 29)
        let resolved = leapDay.occurrence(inYear: 2027, calendar: calendar)
        XCTAssertEqual(resolved, calendar.startOfDay(for: makeDate(2027, 2, 28)))
        XCTAssertNotEqual(resolved, calendar.startOfDay(for: makeDate(2027, 3, 1)))
    }

    // MARK: - Next occurrence and the day boundary (LIST-03, D-12)

    func testAnEventLaterThisYearResolvesToThisYear() {
        let now = makeDate(2026, 8, 12, 9, 30)
        let date = annual(12, 25)
        XCTAssertEqual(date.nextOccurrence(from: now, calendar: calendar), calendar.startOfDay(for: makeDate(2026, 12, 25)))
        XCTAssertEqual(date.daysUntilNextOccurrence(from: now, calendar: calendar), 135)
    }

    func testAnEventEarlierThisYearRollsToNextYear() {
        let now = makeDate(2026, 8, 12, 9, 30)
        let date = annual(3, 15)
        XCTAssertEqual(date.nextOccurrence(from: now, calendar: calendar), calendar.startOfDay(for: makeDate(2027, 3, 15)))
    }

    func testAnEventDatedTodayCountsAsTodayAllDay() {
        let date = annual(8, 12)
        // Just after midnight, mid-morning, and one second before the next midnight all
        // report zero days until (LIST-03).
        for now in [makeDate(2026, 8, 12, 0, 0), makeDate(2026, 8, 12, 9, 30), makeDate(2026, 8, 12, 23, 59)] {
            XCTAssertEqual(date.daysUntilNextOccurrence(from: now, calendar: calendar), 0)
            XCTAssertEqual(date.nextOccurrence(from: now, calendar: calendar), calendar.startOfDay(for: makeDate(2026, 8, 12)))
        }
    }

    func testAnEventRollsOverAtLocalMidnightNotAtNotificationTime() {
        let date = annual(8, 12)
        let justAfterMidnight = makeDate(2026, 8, 13, 0, 0)
        XCTAssertEqual(
            date.nextOccurrence(from: justAfterMidnight, calendar: calendar),
            calendar.startOfDay(for: makeDate(2027, 8, 12))
        )
        XCTAssertEqual(date.daysUntilNextOccurrence(from: justAfterMidnight, calendar: calendar), 364)
    }

    func testDayCountingIsUnaffectedByADaylightSavingTransition() {
        // British Summer Time starts on 28 March 2027; that day is 23 hours long.
        let now = makeDate(2027, 3, 25, 12, 0)
        let date = annual(3, 30)
        XCTAssertEqual(date.daysUntilNextOccurrence(from: now, calendar: calendar), 5)
    }

    // MARK: - Age and years elapsed (DATA-03)

    func testAgeIsTheAgeReachedOnTheNextOccurrence() {
        let now = makeDate(2026, 8, 12)
        // Birthday already passed this year, so the next one is in 2027.
        XCTAssertEqual(annual(3, 15, year: 1990).yearsElapsedAtNextOccurrence(from: now, calendar: calendar), 37)
        // Birthday still to come this year.
        XCTAssertEqual(annual(12, 25, year: 1990).yearsElapsedAtNextOccurrence(from: now, calendar: calendar), 36)
        // Birthday is today: still counts as this year's occurrence.
        XCTAssertEqual(annual(8, 12, year: 1990).yearsElapsedAtNextOccurrence(from: now, calendar: calendar), 36)
    }

    func testNoNumberIsProducedWhenTheYearIsUnknown() {
        let now = makeDate(2026, 8, 12)
        XCTAssertNil(annual(3, 15).yearsElapsedAtNextOccurrence(from: now, calendar: calendar))
    }

    func testAgeForALeapDayBirthdayUsesTheResolvedOccurrenceYear() {
        let now = makeDate(2026, 8, 12)
        XCTAssertEqual(annual(2, 29, year: 2000).yearsElapsedAtNextOccurrence(from: now, calendar: calendar), 27)
    }

    func testAFutureStoredYearProducesNoNumberRatherThanANegativeOne() {
        let now = makeDate(2026, 8, 12)
        XCTAssertNil(annual(3, 15, year: 2030).yearsElapsedAtNextOccurrence(from: now, calendar: calendar))
    }

    func testAgeZeroIsProducedForAnEventStoredInTheCurrentYear() {
        let now = makeDate(2026, 8, 12)
        XCTAssertEqual(annual(12, 25, year: 2026).yearsElapsedAtNextOccurrence(from: now, calendar: calendar), 0)
    }

    // MARK: - Name validation (DATA-01)

    func testNameValidationEnforcesOneToOneHundredCharactersAfterTrimming() {
        XCTAssertFalse(EventValidation.isValidName(""))
        XCTAssertFalse(EventValidation.isValidName("   "))
        XCTAssertTrue(EventValidation.isValidName("A"))
        XCTAssertTrue(EventValidation.isValidName("  Sarah Chen  "))
        XCTAssertEqual(EventValidation.normalisedName("  Sarah Chen  "), "Sarah Chen")
        XCTAssertTrue(EventValidation.isValidName(String(repeating: "a", count: 100)))
        XCTAssertFalse(EventValidation.isValidName(String(repeating: "a", count: 101)))
    }
}
