import SwiftUI
import SwiftData
import DatesKit

/// What an import source produced, handed to the review sheet (Phase 05).
struct ImportPayload: Identifiable, Equatable {
    let id = UUID()
    /// "Calendar" or the file's name — the review title says where the rows came from.
    let sourceName: String
    let candidates: [ImportCandidate]
    /// CSV rows that failed validation, each with its line number and reason (IMP-06).
    /// Always empty for the calendar route, which has no rows to reject.
    let rejectedRows: [EventCSV.RejectedRow]
}

/// The staging step between an import source and the store: nothing is saved until the
/// user has seen what will be added, what already exists, and what could not be read.
struct ImportReviewView: View {
    let store: EventStore
    let payload: ImportPayload

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EventGroup.createdAt) private var groups: [EventGroup]

    @State private var fresh: [ImportCandidate] = []
    @State private var duplicates: [ImportCandidate] = []
    @State private var deselected: Set<ImportCandidate> = []
    @State private var fallbackGroupID: UUID?
    @State private var isImporting = false
    @State private var importError: String?

    private var selectedCount: Int { fresh.count - deselected.count }

    var body: some View {
        NavigationStack {
            Form {
                if fresh.isEmpty && duplicates.isEmpty {
                    nothingToImportSection
                } else {
                    if !fresh.isEmpty {
                        groupSection
                        candidatesSection
                    }
                    if !duplicates.isEmpty {
                        duplicatesSection
                    }
                }
                if !payload.rejectedRows.isEmpty {
                    rejectedSection
                }
            }
            .navigationTitle("Import from \(payload.sourceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedCount == 1 ? "Add 1 date" : "Add \(selectedCount) dates") {
                        importSelected()
                    }
                    .disabled(selectedCount == 0 || isImporting)
                }
            }
            .onAppear(perform: screen)
            .alert("Import failed", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .interactiveDismissDisabled(isImporting)
        }
    }

    // MARK: - Sections

    private var nothingToImportSection: some View {
        Section {
            Text("Nothing to import")
                .foregroundStyle(.secondary)
        } footer: {
            if payload.rejectedRows.isEmpty {
                Text("No birthdays or yearly events were found.")
            }
        }
    }

    private var groupSection: some View {
        Section {
            Picker("Add to group", selection: $fallbackGroupID) {
                ForEach(groups) { group in
                    Text(group.name).tag(Optional(group.uuid))
                }
            }
        } footer: {
            if fresh.contains(where: { $0.groupName != nil }) {
                Text("Rows that name one of your groups keep it; the rest go to this one.")
            }
        }
    }

    private var candidatesSection: some View {
        Section {
            ForEach(fresh) { candidate in
                Toggle(isOn: selectionBinding(for: candidate)) {
                    candidateLabel(candidate)
                }
            }
        } header: {
            Text("New dates")
        }
    }

    private var duplicatesSection: some View {
        Section {
            ForEach(duplicates) { candidate in
                candidateLabel(candidate)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Already in your list")
        } footer: {
            Text("These match a date you already have, so they will be skipped.")
        }
    }

    private var rejectedSection: some View {
        Section {
            ForEach(payload.rejectedRows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Line \(row.lineNumber)")
                        .font(.subheadline.weight(.medium))
                    Text(row.reason.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Couldn't be read")
        } footer: {
            Text("Fix these rows in the file and import it again; the dates above import as duplicates and are skipped.")
        }
    }

    private func candidateLabel(_ candidate: ImportCandidate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.name)
            Text(subtitle(for: candidate))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func subtitle(for candidate: ImportCandidate) -> String {
        var date = "\(candidate.date.day) \(EventFormatting.monthName(candidate.date.month))"
        if let year = candidate.date.year {
            date += " \(year)"
        }
        var parts = [candidate.type.displayName, date]
        if let groupName = candidate.groupName {
            parts.append(groupName)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private func screen() {
        guard fresh.isEmpty && duplicates.isEmpty else { return }
        (fresh, duplicates) = ImportScreening.partition(payload.candidates, existing: store.snapshots())
        fallbackGroupID = groups.first { $0.isUngrouped }?.uuid ?? groups.first?.uuid
    }

    private func selectionBinding(for candidate: ImportCandidate) -> Binding<Bool> {
        Binding(
            get: { !deselected.contains(candidate) },
            set: { isOn in
                if isOn {
                    deselected.remove(candidate)
                } else {
                    deselected.insert(candidate)
                }
            }
        )
    }

    private func importSelected() {
        let selected = fresh.filter { !deselected.contains($0) }
        let fallbackGroup = groups.first { $0.uuid == fallbackGroupID }
        isImporting = true
        Task {
            do {
                try await store.importEvents(selected, fallbackGroup: fallbackGroup)
                dismiss()
            } catch {
                importError = error.localizedDescription
                isImporting = false
            }
        }
    }
}
