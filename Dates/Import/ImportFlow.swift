import SwiftUI
import UniformTypeIdentifiers
import DatesKit

/// Drives an import from either source: fetch or read, then stage the result for review.
///
/// The home list and Settings each own one of these, so an import behaves identically
/// wherever it starts — same review sheet, same errors, same store path.
@MainActor
@Observable
final class ImportFlow {
    var isPickingCSV = false
    var payload: ImportPayload?
    var errorMessage: String?
    private(set) var isFetchingCalendar = false

    func fetchCalendarCandidates(now: Date = Date()) {
        guard !isFetchingCalendar else { return }
        isFetchingCalendar = true
        Task {
            defer { isFetchingCalendar = false }
            do {
                let candidates = try await CalendarImporter.fetchCandidates(now: now)
                payload = ImportPayload(sourceName: "Calendar", candidates: candidates, rejectedRows: [])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func readCSV(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            // The picked URL lives outside the sandbox; without the scoped-access pair
            // the read fails on device even though it works in the simulator.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            let outcome = try EventCSV.decode(text)
            payload = ImportPayload(
                sourceName: url.lastPathComponent,
                candidates: outcome.candidates,
                rejectedRows: outcome.rejectedRows
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Attaches everything a flow needs to present: the review sheet, the file picker,
/// and the error alert.
private struct ImportFlowModifier: ViewModifier {
    @Bindable var flow: ImportFlow
    let store: EventStore

    func body(content: Content) -> some View {
        content
            .sheet(item: $flow.payload) { payload in
                ImportReviewView(store: store, payload: payload)
            }
            .fileImporter(
                isPresented: $flow.isPickingCSV,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                onCompletion: flow.readCSV
            )
            .alert("Can't import", isPresented: .constant(flow.errorMessage != nil)) {
                Button("OK") { flow.errorMessage = nil }
            } message: {
                Text(flow.errorMessage ?? "")
            }
    }
}

extension View {
    func importFlow(_ flow: ImportFlow, store: EventStore) -> some View {
        modifier(ImportFlowModifier(flow: flow, store: store))
    }
}
