import XCTest
@testable import DatesKit

/// Dates with and without a year must read in the same order on one phone.
final class DisplayLocaleTests: XCTestCase {
    private let date: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 1991, month: 12, day: 3))!
    }()

    private func format(_ template: String, _ locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    func testRegionOverrideAppliesWithAndWithoutAYear() {
        let locale = Locale.dateDisplay(from: Locale(identifier: "en_US@rg=gbzzzz"))
        XCTAssertEqual(format("d MMMM", locale), "3 December")
        XCTAssertEqual(format("d MMMM y", locale), "3 December 1991")
    }

    func testPlainLocaleIsUnchanged() {
        let locale = Locale.dateDisplay(from: Locale(identifier: "en_US"))
        XCTAssertEqual(format("d MMMM", locale), "December 3")
        XCTAssertEqual(format("d MMMM y", locale), "December 3, 1991")
    }
}
