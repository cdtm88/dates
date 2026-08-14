import Foundation

/// A minimal RFC 4180 CSV reader and writer.
///
/// Import files come from spreadsheets the app does not control, so the parser accepts the
/// things those actually produce: CRLF or LF line endings, a UTF-8 byte-order mark, quoted
/// fields containing commas, newlines and doubled quotes, and trailing blank lines. It is
/// deliberately not configurable — the delimiter is a comma and the encoding is UTF-8,
/// matching what the export writes.
public enum CSVTable {

    /// Parses `text` into rows of fields. Never fails: a malformed quote sequence is read
    /// literally rather than aborting the whole file, so one bad row cannot block an import
    /// (per-row validation happens later, with reasons — IMP-06).
    public static func parse(_ text: String) -> [[String]] {
        var input = Substring(text)
        // Strip a UTF-8 BOM, which Excel and Numbers prepend to exported CSV.
        if input.first == "\u{FEFF}" { input = input.dropFirst() }

        var rows: [[String]] = []
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var index = input.startIndex

        func endField() {
            fields.append(field)
            field = ""
        }
        func endRow() {
            endField()
            rows.append(fields)
            fields = []
        }

        while index < input.endIndex {
            let character = input[index]
            if inQuotes {
                if character == "\"" {
                    let next = input.index(after: index)
                    if next < input.endIndex, input[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"" where field.isEmpty:
                    inQuotes = true
                case ",":
                    endField()
                // A CRLF pair is a single `Character` in Swift — one grapheme cluster —
                // so it needs its own case; it would match neither "\r" nor "\n".
                case "\n", "\r", "\r\n":
                    endRow()
                default:
                    field.append(character)
                }
            }
            index = input.index(after: index)
        }
        // A file that does not end in a newline still ends its last row.
        if !field.isEmpty || !fields.isEmpty || inQuotes {
            endRow()
        }
        // Trailing blank lines parse as single empty fields; they are not rows.
        return rows.filter { $0 != [""] }
    }

    /// Encodes rows as CRLF-delimited CSV, quoting only the fields that need it.
    public static func encode(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map(escaped).joined(separator: ",")
        }
        .joined(separator: "\r\n")
        .appending(rows.isEmpty ? "" : "\r\n")
    }

    private static func escaped(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
