import SwiftUI
import UniformTypeIdentifiers
import DatesKit

/// Drives an import from either source: fetch or read, then stage the result for review.
///
/// The home list and Settings each own one of these, so an import behaves identically
/// wherever it starts — same review sheet, same errors, same store path.
/// What the calendar-selection sheet shows: every calendar that produced candidates,
/// plus the fetch instant so the merged list sorts the same way the fetch did.
struct CalendarImportChoices: Identifiable, Equatable {
    let id = UUID()
    let calendars: [CalendarCandidates]
    let now: Date
}

@MainActor
@Observable
final class ImportFlow {
    var isPickingCSV = false
    var payload: ImportPayload?
    var calendarChoices: CalendarImportChoices?
    var errorMessage: String?
    private(set) var isFetchingCalendar = false

    /// Review payload staged while the selection sheet animates out; presented from the
    /// sheet's `onDismiss` so the two sheets never fight over the presentation slot.
    private var stagedPayload: ImportPayload?

    func fetchCalendarCandidates(now: Date = Date()) {
        guard !isFetchingCalendar else { return }
        isFetchingCalendar = true
        Task {
            defer { isFetchingCalendar = false }
            do {
                let calendars = try await CalendarImporter.fetchCandidatesByCalendar(now: now)
                if calendars.count > 1 {
                    calendarChoices = CalendarImportChoices(calendars: calendars, now: now)
                } else {
                    // One calendar (or none): a selection step would be a screen with
                    // nothing to decide.
                    payload = Self.mergedPayload(from: calendars, now: now)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func confirmCalendarSelection(_ selectedIDs: Set<String>) {
        guard let choices = calendarChoices else { return }
        let selected = choices.calendars.filter { selectedIDs.contains($0.id) }
        stagedPayload = Self.mergedPayload(from: selected, now: choices.now)
        calendarChoices = nil
    }

    func presentStagedPayload() {
        guard let staged = stagedPayload else { return }
        stagedPayload = nil
        payload = staged
    }

    /// Merges the chosen calendars back into one soonest-first candidate list, screening
    /// out cross-calendar duplicates (two calendars carrying the same person's birthday).
    private static func mergedPayload(from calendars: [CalendarCandidates], now: Date) -> ImportPayload {
        var seen = Set<String>()
        let merged = calendars
            .flatMap(\.candidates)
            .filter { seen.insert($0.duplicateKey).inserted }
            .sorted {
                ($0.date.daysUntilNextOccurrence(from: now) ?? .max)
                    < ($1.date.daysUntilNextOccurrence(from: now) ?? .max)
            }
        return ImportPayload(sourceName: "Calendar", candidates: merged, rejectedRows: [])
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
            .sheet(item: $flow.calendarChoices, onDismiss: flow.presentStagedPayload) { choices in
                CalendarSelectionView(choices: choices) { selectedIDs in
                    flow.confirmCalendarSelection(selectedIDs)
                }
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

/// The first step of a calendar import: choose which calendars to pull dates from, so a
/// subscribed holiday calendar can be excluded in one switch instead of date by date.
private struct CalendarSelectionView: View {
    let choices: CalendarImportChoices
    let onConfirm: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String>

    init(choices: CalendarImportChoices, onConfirm: @escaping (Set<String>) -> Void) {
        self.choices = choices
        self.onConfirm = onConfirm
        _selectedIDs = State(initialValue: Set(
            choices.calendars.filter { !$0.isSubscribed }.map(\.id)
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(choices.calendars) { source in
                        Toggle(isOn: binding(for: source.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title)
                                Text(source.candidates.count == 1 ? "1 date" : "\(source.candidates.count) dates")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Only calendars with birthdays or yearly events are listed. Subscribed calendars, like public holidays, start switched off.")
                }
            }
            .navigationTitle("Choose calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { onConfirm(selectedIDs) }
                        .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isOn in
                if isOn {
                    selectedIDs.insert(id)
                } else {
                    selectedIDs.remove(id)
                }
            }
        )
    }
}
