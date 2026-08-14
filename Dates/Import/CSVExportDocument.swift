import SwiftUI
import UniformTypeIdentifiers
import DatesKit

/// The exported CSV, wrapped for `fileExporter` (Phase 05).
///
/// The content is built by `EventCSV.encode`, which writes the same schema the importer
/// reads — the tested guarantee is that an exported file re-imports as pure duplicates.
struct CSVExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
