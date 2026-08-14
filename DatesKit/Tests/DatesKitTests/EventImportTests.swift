import XCTest
@testable import DatesKit

/// Phase 05 — the CSV reader/writer underneath import and export.
final class CSVTableTests: XCTestCase {

    func testParsesPlainRowsWithLFAndCRLFEndings() {
        XCTAssertEqual(CSVTable.parse("a,b\nc,d\n"), [["a", "b"], ["c", "d"]])
        XCTAssertEqual(CSVTable.parse("a,b\r\nc,d\r\n"), [["a", "b"], ["c", "d"]])
    }

    func testParsesQuotedFieldsContainingCommasNewlinesAndDoubledQuotes() {
        let text = "\"Smith, Anna\",\"line one\nline two\",\"say \"\"hi\"\"\"\n"
        XCTAssertEqual(CSVTable.parse(text), [["Smith, Anna", "line one\nline two", "say \"hi\""]])
    }

    func testStripsAByteOrderMarkAndIgnoresTrailingBlankLines() {
        let text = "\u{FEFF}a,b\n\n\nc,d\n\n"
        XCTAssertEqual(CSVTable.parse(text), [["a", "b"], ["c", "d"]])
    }

    func testAFileWithoutATrailingNewlineKeepsItsLastRow() {
        XCTAssertEqual(CSVTable.parse("a,b\nc,d"), [["a", "b"], ["c", "d"]])
    }

    func testEmptyFieldsSurvive() {
        XCTAssertEqual(CSVTable.parse("a,,c\n"), [["a", "", "c"]])
    }

    func testEncodeQuotesOnlyWhatNeedsQuoting() {
        let encoded = CSVTable.encode([["plain", "with,comma", "with \"quote\"", "with\nnewline"]])
        XCTAssertEqual(encoded, "plain,\"with,comma\",\"with \"\"quote\"\"\",\"with\nnewline\"\r\n")
    }

    func testEncodeThenParseRoundTrips() {
        let rows = [["Name", "Notes"], ["Smith, Anna", "says \"hello\"\noften"], ["Bob", ""]]
        XCTAssertEqual(CSVTable.parse(CSVTable.encode(rows)), rows)
    }
}

/// Phase 05 — the import schema: per-row validation with reasons (IMP-06), header handling,
/// duplicate screening, and the export round-trip.
final class EventImportTests: XCTestCase {

    private func decode(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> EventCSV.DecodeOutcome {
        do {
            return try EventCSV.decode(text)
        } catch {
            XCTFail("Decode threw \(error)", file: file, line: line)
            return EventCSV.DecodeOutcome(candidates: [], rejectedRows: [])
        }
    }

    // MARK: - Header

    func testAnEmptyFileAndAMissingRequiredColumnAreFileLevelErrors() {
        XCTAssertThrowsError(try EventCSV.decode("")) { error in
            XCTAssertEqual(error as? EventCSV.FileError, .empty)
        }
        XCTAssertThrowsError(try EventCSV.decode("Name,Type\nAnna,birthday\n")) { error in
            XCTAssertEqual(error as? EventCSV.FileError, .missingColumns(["Month", "Day"]))
        }
    }

    func testColumnsMatchByNameCaseInsensitivelyAndInAnyOrder() {
        let outcome = decode("day,NAME,month\n14,Anna,3\n")
        XCTAssertEqual(outcome.candidates, [
            ImportCandidate(name: "Anna", type: .other, date: annual(3, 14)),
        ])
        XCTAssertTrue(outcome.rejectedRows.isEmpty)
    }

    func testUnknownExtraColumnsAreIgnored() {
        let outcome = decode("Name,Month,Day,Favourite colour\nAnna,3,14,teal\n")
        XCTAssertEqual(outcome.candidates.count, 1)
    }

    // MARK: - Valid rows

    func testAFullRowDecodesEveryField() {
        let outcome = decode("Name,Type,Month,Day,Year,Group\nAnna,birthday,3,14,1990,Close family\n")
        XCTAssertEqual(outcome.candidates, [
            ImportCandidate(name: "Anna", type: .birthday, date: annual(3, 14, year: 1990), groupName: "Close family"),
        ])
    }

    func testTypeYearAndGroupAreOptionalAndTypeDefaultsToOther() {
        let outcome = decode("Name,Type,Month,Day,Year,Group\nAnna,,3,14,,\n")
        let candidate = try? XCTUnwrap(outcome.candidates.first)
        XCTAssertEqual(candidate?.type, .other)
        XCTAssertNil(candidate?.date.year)
        XCTAssertNil(candidate?.groupName)
    }

    func testTypeParsingAcceptsDisplayNamesAndIsCaseInsensitive() {
        XCTAssertEqual(EventType(importedValue: "Birthday"), .birthday)
        XCTAssertEqual(EventType(importedValue: "ANNIVERSARY"), .anniversary)
        XCTAssertEqual(EventType(importedValue: "Key date"), .other)
        XCTAssertEqual(EventType(importedValue: "other"), .other)
        XCTAssertNil(EventType(importedValue: "wedding"))
    }

    func testNamesAreTrimmedAndQuotedNamesKeepTheirCommas() {
        let outcome = decode("Name,Month,Day\n  Anna  ,3,14\n\"Smith, Anna\",4,1\n")
        XCTAssertEqual(outcome.candidates.map(\.name), ["Anna", "Smith, Anna"])
    }

    func test29FebruaryWithoutAYearIsAccepted() {
        let outcome = decode("Name,Month,Day\nLeap,2,29\n")
        XCTAssertEqual(outcome.candidates.first?.date, annual(2, 29))
    }

    // MARK: - Rejected rows (IMP-06)

    func testEachBadRowIsRejectedWithItsLineNumberAndReasonWhileGoodRowsSurvive() {
        let text = """
        Name,Type,Month,Day,Year
        Anna,birthday,3,14,1990
        ,birthday,3,14,
        Bob,wedding,5,1,
        Carol,other,13,1,
        Dan,other,2,30,
        Eve,other,2,29,2001
        Frank,other,two,1,
        Grace,other,4,1,soon
        Hana,anniversary,6,21,2010
        """
        let outcome = decode(text)

        XCTAssertEqual(outcome.candidates.map(\.name), ["Anna", "Hana"])
        XCTAssertEqual(outcome.rejectedRows, [
            EventCSV.RejectedRow(lineNumber: 3, reason: .invalidName),
            EventCSV.RejectedRow(lineNumber: 4, reason: .unknownType("wedding")),
            EventCSV.RejectedRow(lineNumber: 5, reason: .impossibleDate(month: 13, day: 1, year: nil)),
            EventCSV.RejectedRow(lineNumber: 6, reason: .impossibleDate(month: 2, day: 30, year: nil)),
            EventCSV.RejectedRow(lineNumber: 7, reason: .impossibleDate(month: 2, day: 29, year: 2001)),
            EventCSV.RejectedRow(lineNumber: 8, reason: .invalidNumber(column: "Month", value: "two")),
            EventCSV.RejectedRow(lineNumber: 9, reason: .invalidNumber(column: "Year", value: "soon")),
        ])
    }

    func testARowWithTooFewFieldsIsRejectedNotMisaligned() {
        let outcome = decode("Name,Month,Day\nAnna,3\n")
        XCTAssertTrue(outcome.candidates.isEmpty)
        XCTAssertEqual(outcome.rejectedRows.first?.reason, .wrongFieldCount(expected: 3, found: 2))
    }

    func testANameLongerThanAHundredCharactersIsRejected() {
        let longName = String(repeating: "a", count: 101)
        let outcome = decode("Name,Month,Day\n\(longName),3,14\n")
        XCTAssertEqual(outcome.rejectedRows.first?.reason, .invalidName)
    }

    func testEveryRejectionReasonHasADisplayMessage() {
        let reasons: [EventCSV.RowRejectionReason] = [
            .wrongFieldCount(expected: 3, found: 2),
            .invalidName,
            .unknownType("wedding"),
            .invalidNumber(column: "Month", value: "two"),
            .impossibleDate(month: 2, day: 30, year: nil),
            .impossibleDate(month: 2, day: 29, year: 2001),
        ]
        for reason in reasons {
            XCTAssertFalse(reason.message.isEmpty)
        }
    }

    // MARK: - Duplicate screening

    func testACandidateMatchingAnExistingEventByNameAndDayIsADuplicate() {
        let existing = [makeEvent(name: "Anna", date: annual(3, 14, year: 1990))]
        let candidates = [
            ImportCandidate(name: "anna", type: .birthday, date: annual(3, 14)),
            ImportCandidate(name: "Bob", type: .birthday, date: annual(3, 14)),
        ]
        let (fresh, duplicates) = ImportScreening.partition(candidates, existing: existing)
        XCTAssertEqual(fresh.map(\.name), ["Bob"])
        XCTAssertEqual(duplicates.map(\.name), ["anna"])
    }

    func testDuplicateMatchingIgnoresDiacriticsAndYears() {
        let existing = [makeEvent(name: "Zoë", date: annual(7, 2))]
        let candidate = ImportCandidate(name: "Zoe", type: .birthday, date: annual(7, 2, year: 1988))
        let (fresh, duplicates) = ImportScreening.partition([candidate], existing: existing)
        XCTAssertTrue(fresh.isEmpty)
        XCTAssertEqual(duplicates.count, 1)
    }

    func testTheSecondIdenticalRowInOneFileIsADuplicateOfTheFirst() {
        let candidate = ImportCandidate(name: "Anna", type: .birthday, date: annual(3, 14))
        let (fresh, duplicates) = ImportScreening.partition([candidate, candidate], existing: [])
        XCTAssertEqual(fresh.count, 1)
        XCTAssertEqual(duplicates.count, 1)
    }

    func testSamePersonOnADifferentDayIsNotADuplicate() {
        let existing = [makeEvent(name: "Anna", date: annual(3, 14))]
        let candidate = ImportCandidate(name: "Anna", type: .anniversary, date: annual(9, 2))
        let (fresh, _) = ImportScreening.partition([candidate], existing: existing)
        XCTAssertEqual(fresh.count, 1)
    }

    // MARK: - Export round-trip

    func testExportedEventsReimportAsPureDuplicates() throws {
        let events = [
            makeEvent(name: "Smith, Anna", type: .birthday, date: annual(3, 14, year: 1990), groupName: "Close family"),
            makeEvent(name: "Zoë", type: .anniversary, date: annual(2, 29, year: 2000), groupName: "Friends"),
            makeEvent(name: "Bob", type: .other, date: annual(12, 25), groupName: "Work"),
        ]
        let outcome = try EventCSV.decode(EventCSV.encode(events))

        XCTAssertTrue(outcome.rejectedRows.isEmpty)
        XCTAssertEqual(outcome.candidates.map(\.name), events.map(\.name))
        XCTAssertEqual(outcome.candidates.map(\.date), events.map(\.date))
        XCTAssertEqual(outcome.candidates.map(\.type), events.map(\.type))
        XCTAssertEqual(outcome.candidates.map(\.groupName), events.map(\.groupName))

        let (fresh, duplicates) = ImportScreening.partition(outcome.candidates, existing: events)
        XCTAssertTrue(fresh.isEmpty)
        XCTAssertEqual(duplicates.count, events.count)
    }

    func testExportOfNoEventsIsJustTheHeader() {
        XCTAssertEqual(EventCSV.encode([]), "Name,Type,Month,Day,Year,Group\r\n")
    }

    // MARK: - CSV injection

    func testExportDefusesFormulaShapedFieldsWithAnApostrophe() {
        let events = [
            makeEvent(name: "=SUM(A1:A9)", date: annual(3, 14), groupName: "@work"),
            makeEvent(name: "+44 Pat", date: annual(4, 1), groupName: "-Friends"),
        ]
        let text = EventCSV.encode(events)
        XCTAssertTrue(text.contains("'=SUM(A1:A9)"))
        XCTAssertTrue(text.contains("'@work"))
        XCTAssertTrue(text.contains("'+44 Pat"))
        XCTAssertTrue(text.contains("'-Friends"))
        XCTAssertFalse(text.contains("\r\n=")) // No line starts with a live formula.
    }

    func testDefusedFieldsRestoreOnImportAndStillScreenAsDuplicates() throws {
        let events = [makeEvent(name: "=SUM(A1:A9)", date: annual(3, 14), groupName: "@work")]
        let outcome = try EventCSV.decode(EventCSV.encode(events))

        XCTAssertTrue(outcome.rejectedRows.isEmpty)
        XCTAssertEqual(outcome.candidates.map(\.name), ["=SUM(A1:A9)"])
        XCTAssertEqual(outcome.candidates.map(\.groupName), ["@work"])

        let (fresh, duplicates) = ImportScreening.partition(outcome.candidates, existing: events)
        XCTAssertTrue(fresh.isEmpty)
        XCTAssertEqual(duplicates.count, 1)
    }

    func testAnOrdinaryApostropheNameSurvivesImportUntouched() {
        let outcome = decode("Name,Month,Day\n'Awa,3,14\n")
        XCTAssertEqual(outcome.candidates.map(\.name), ["'Awa"])
    }
}
