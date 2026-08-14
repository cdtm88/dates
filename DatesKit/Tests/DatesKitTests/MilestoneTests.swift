import XCTest
@testable import DatesKit

/// Milestone years: which ages and anniversaries get marked in the list and detail views.
final class MilestoneTests: XCTestCase {

    func testEveryDecadeIsAMilestoneForEveryType() {
        for years in [10, 20, 30, 40, 50, 90, 100] {
            XCTAssertTrue(Milestone.isMilestone(type: .birthday, yearsElapsed: years))
            XCTAssertTrue(Milestone.isMilestone(type: .anniversary, yearsElapsed: years))
            XCTAssertTrue(Milestone.isMilestone(type: .other, yearsElapsed: years))
        }
    }

    func testComingOfAgeBirthdaysAreMilestones() {
        for years in [1, 13, 16, 18, 21] {
            XCTAssertTrue(Milestone.isMilestone(type: .birthday, yearsElapsed: years))
        }
    }

    func testNotableAnniversariesAreMilestones() {
        for years in [1, 5, 15, 25] {
            XCTAssertTrue(Milestone.isMilestone(type: .anniversary, yearsElapsed: years))
        }
    }

    func testOrdinaryYearsAreNot() {
        for years in [2, 12, 29, 31, 99] {
            XCTAssertFalse(Milestone.isMilestone(type: .birthday, yearsElapsed: years), "\(years)")
        }
        for years in [13, 16, 18, 21, 24] {
            XCTAssertFalse(Milestone.isMilestone(type: .anniversary, yearsElapsed: years), "\(years)")
        }
    }

    func testYearZeroAndNegativeYearsAreNever() {
        XCTAssertFalse(Milestone.isMilestone(type: .birthday, yearsElapsed: 0))
        XCTAssertFalse(Milestone.isMilestone(type: .anniversary, yearsElapsed: -10))
    }

    func testASnapshotSurfacesItsMilestoneYearsOnlyWhenTheYearIsKnown() {
        let now = makeDate(2026, 8, 14)

        let turningThirty = makeEvent(name: "Anna", type: .birthday, date: annual(9, 1, year: 1996))
        XCTAssertEqual(turningThirty.milestoneYears(from: now, calendar: TestCalendar.london), 30)

        let turningTwentyNine = makeEvent(name: "Ben", type: .birthday, date: annual(9, 1, year: 1997))
        XCTAssertNil(turningTwentyNine.milestoneYears(from: now, calendar: TestCalendar.london))

        let yearUnknown = makeEvent(name: "Chi", type: .birthday, date: annual(9, 1))
        XCTAssertNil(yearUnknown.milestoneYears(from: now, calendar: TestCalendar.london))
    }
}
