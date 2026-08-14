import Foundation

/// One importable event, whichever route it arrived by (CSV or Calendar).
///
/// Candidates are already valid — the name fits DATA-01 and the date is a real
/// `AnnualDate`. Anything that failed validation never becomes a candidate; it becomes a
/// rejection with a reason instead (IMP-06).
public struct ImportCandidate: Hashable, Sendable, Identifiable {
    public let name: String
    public let type: EventType
    public let date: AnnualDate
    /// Group named by the source, matched against existing groups at import time.
    /// Nil when the source carries no grouping (Calendar events, CSV without the column).
    public let groupName: String?

    public init(name: String, type: EventType, date: AnnualDate, groupName: String? = nil) {
        self.name = name
        self.type = type
        self.date = date
        self.groupName = groupName
    }

    /// Candidates are value types with no stored id; identity is the content itself, which
    /// also makes two identical rows in one file the same candidate.
    public var id: Self { self }

    /// Case- and diacritic-insensitive identity used for duplicate detection: the same
    /// person on the same day is the same date, whether or not one side knows the year.
    public var duplicateKey: String {
        // No locale: folding must give the same answer on every device, or the same
        // person could be a duplicate on one phone and fresh on another that syncs.
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return "\(folded)|\(date.month)|\(date.day)"
    }
}

/// Duplicate screening for an import (IMP: re-importing must not double every date).
public enum ImportScreening {
    /// Splits candidates into fresh ones and duplicates. A candidate is a duplicate when an
    /// existing event — or an earlier candidate in the same batch — shares its name
    /// (case- and diacritic-insensitively) and its month and day.
    public static func partition(
        _ candidates: [ImportCandidate],
        existing: [EventSnapshot]
    ) -> (fresh: [ImportCandidate], duplicates: [ImportCandidate]) {
        var seen = Set(existing.map { snapshot in
            ImportCandidate(name: snapshot.name, type: snapshot.type, date: snapshot.date).duplicateKey
        })
        var fresh: [ImportCandidate] = []
        var duplicates: [ImportCandidate] = []
        for candidate in candidates {
            if seen.insert(candidate.duplicateKey).inserted {
                fresh.append(candidate)
            } else {
                duplicates.append(candidate)
            }
        }
        return (fresh, duplicates)
    }
}

/// The CSV schema for import and export.
///
/// Columns are matched by header name, case-insensitively and in any order, so a file edited
/// in a spreadsheet keeps working after columns are shuffled. `Name`, `Month` and `Day` are
/// required; `Type`, `Year` and `Group` are optional. Export writes all six, so an exported
/// file re-imports as pure duplicates.
public enum EventCSV {

    public static let nameColumn = "Name"
    public static let typeColumn = "Type"
    public static let monthColumn = "Month"
    public static let dayColumn = "Day"
    public static let yearColumn = "Year"
    public static let groupColumn = "Group"

    private static let requiredColumns = [nameColumn, monthColumn, dayColumn]
    private static let allColumns = [nameColumn, typeColumn, monthColumn, dayColumn, yearColumn, groupColumn]

    // MARK: - Decoding

    /// Why a row was refused, phrased for display next to the row (IMP-06).
    /// `Error` conformance is only so it can sit in a `Result` during decoding.
    public enum RowRejectionReason: Hashable, Sendable, Error {
        case wrongFieldCount(expected: Int, found: Int)
        case invalidName
        case unknownType(String)
        case invalidNumber(column: String, value: String)
        case impossibleDate(month: Int, day: Int, year: Int?)

        public var message: String {
            switch self {
            case let .wrongFieldCount(expected, found):
                return "Expected \(expected) values but found \(found)."
            case .invalidName:
                return "The name must be 1 to 100 characters."
            case let .unknownType(value):
                return "\"\(value)\" is not a type. Use birthday, anniversary or other."
            case let .invalidNumber(column, value):
                return "\"\(value)\" is not a number for \(column)."
            case let .impossibleDate(month, day, year):
                if let year {
                    return "\(day)/\(month)/\(year) is not a real date."
                }
                return "Day \(day) does not exist in month \(month)."
            }
        }
    }

    /// A refused row, kept alongside its 1-based line number so the user can find it in
    /// the file they just picked (IMP-06).
    public struct RejectedRow: Hashable, Sendable, Identifiable {
        public let lineNumber: Int
        public let reason: RowRejectionReason
        public var id: Int { lineNumber }
    }

    public struct DecodeOutcome: Sendable {
        public let candidates: [ImportCandidate]
        public let rejectedRows: [RejectedRow]
    }

    /// The whole file is unusable — as opposed to individual rows being refused.
    public enum FileError: Error, Hashable, LocalizedError {
        case empty
        case missingColumns([String])

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "The file has no rows."
            case .missingColumns(let columns):
                return "The header row is missing: \(columns.joined(separator: ", "))."
            }
        }
    }

    public static func decode(_ text: String) throws -> DecodeOutcome {
        let rows = CSVTable.parse(text)
        guard let header = rows.first else { throw FileError.empty }

        let columnIndex = Dictionary(
            header.enumerated().map { ($1.trimmingCharacters(in: .whitespaces).lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let missing = requiredColumns.filter { columnIndex[$0.lowercased()] == nil }
        guard missing.isEmpty else { throw FileError.missingColumns(missing) }

        var candidates: [ImportCandidate] = []
        var rejected: [RejectedRow] = []

        for (offset, row) in rows.dropFirst().enumerated() {
            let lineNumber = offset + 2 // 1-based, counting the header line.
            switch decodeRow(row, columnIndex: columnIndex, headerWidth: header.count) {
            case .success(let candidate):
                candidates.append(candidate)
            case .failure(let reason):
                rejected.append(RejectedRow(lineNumber: lineNumber, reason: reason))
            }
        }
        return DecodeOutcome(candidates: candidates, rejectedRows: rejected)
    }

    private static func decodeRow(
        _ row: [String],
        columnIndex: [String: Int],
        headerWidth: Int
    ) -> Result<ImportCandidate, RowRejectionReason> {
        func field(_ column: String) -> String? {
            guard let index = columnIndex[column.lowercased()], index < row.count else { return nil }
            let value = row[index].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }

        // A row shorter than the header has lost fields to a missing comma; matching the
        // remainder by position would silently attach values to the wrong columns.
        let lastRequiredIndex = requiredColumns.compactMap { columnIndex[$0.lowercased()] }.max() ?? 0
        guard row.count > lastRequiredIndex else {
            return .failure(.wrongFieldCount(expected: headerWidth, found: row.count))
        }

        guard let rawName = field(nameColumn).map(restoredFromSpreadsheet),
              EventValidation.isValidName(rawName) else {
            return .failure(.invalidName)
        }

        let type: EventType
        if let rawType = field(typeColumn) {
            guard let parsed = EventType(importedValue: rawType) else {
                return .failure(.unknownType(rawType))
            }
            type = parsed
        } else {
            type = .other
        }

        func number(_ column: String, _ raw: String) -> Result<Int, RowRejectionReason> {
            guard let value = Int(raw) else {
                return .failure(.invalidNumber(column: column, value: raw))
            }
            return .success(value)
        }

        guard let rawMonth = field(monthColumn), let rawDay = field(dayColumn) else {
            return .failure(.wrongFieldCount(expected: headerWidth, found: row.count))
        }

        let month: Int, day: Int
        switch number(monthColumn, rawMonth) {
        case .success(let value): month = value
        case .failure(let reason): return .failure(reason)
        }
        switch number(dayColumn, rawDay) {
        case .success(let value): day = value
        case .failure(let reason): return .failure(reason)
        }

        var year: Int?
        if let rawYear = field(yearColumn) {
            switch number(yearColumn, rawYear) {
            case .success(let value): year = value
            case .failure(let reason): return .failure(reason)
            }
        }

        guard let date = AnnualDate(month: month, day: day, year: year) else {
            return .failure(.impossibleDate(month: month, day: day, year: year))
        }

        return .success(ImportCandidate(
            name: EventValidation.normalisedName(rawName),
            type: type,
            date: date,
            groupName: field(groupColumn).map(restoredFromSpreadsheet)
        ))
    }

    // MARK: - Spreadsheet safety

    /// Spreadsheets treat a cell starting with one of these as a formula, so a name like
    /// "=1+1" in an exported file would execute when opened in Excel (CSV injection).
    private static let formulaStarters: Set<Character> = ["=", "+", "-", "@", "\t"]

    /// Defuses a formula-shaped field with a leading apostrophe — the convention Excel and
    /// Sheets themselves use for "this cell is text". Only the free-text columns (Name,
    /// Group) go through this; numeric columns never start with a formula character.
    private static func defusedForSpreadsheet(_ field: String) -> String {
        guard let first = field.first, formulaStarters.contains(first) else { return field }
        return "'" + field
    }

    /// Strips the apostrophe `defusedForSpreadsheet` added, so an exported file still
    /// re-imports as pure duplicates.
    private static func restoredFromSpreadsheet(_ field: String) -> String {
        guard field.first == "'",
              let second = field.dropFirst().first,
              formulaStarters.contains(second) else { return field }
        return String(field.dropFirst())
    }

    // MARK: - Encoding

    /// Exports every event with all six columns, so the file both survives a spreadsheet
    /// round-trip and re-imports as pure duplicates.
    public static func encode(_ snapshots: [EventSnapshot]) -> String {
        var rows: [[String]] = [allColumns]
        for snapshot in snapshots {
            rows.append([
                defusedForSpreadsheet(snapshot.name),
                snapshot.type.rawValue,
                String(snapshot.date.month),
                String(snapshot.date.day),
                snapshot.date.year.map(String.init) ?? "",
                defusedForSpreadsheet(snapshot.groupName),
            ])
        }
        return CSVTable.encode(rows)
    }
}

extension EventType {
    /// Parses a user-supplied type string: the raw value, the display name, or a couple of
    /// obvious spellings, case-insensitively. Import is the only caller — the UI uses pickers.
    public init?(importedValue: String) {
        let folded = importedValue.trimmingCharacters(in: .whitespaces).lowercased()
        switch folded {
        case "birthday", "bday":
            self = .birthday
        case "anniversary":
            self = .anniversary
        case "other", "key date", "keydate", "date":
            self = .other
        default:
            return nil
        }
    }
}
