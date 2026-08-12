import SwiftUI
import SwiftData
import DatesKit

/// All stored fields plus the effective notification offsets, with an edit affordance (LIST-05).
struct EventDetailView: View {
    let eventID: UUID
    let store: EventStore
    let now: Date

    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [DateEvent]
    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    init(eventID: UUID, store: EventStore, now: Date) {
        self.eventID = eventID
        self.store = store
        self.now = now
        _matches = Query(
            FetchDescriptor<DateEvent>(predicate: #Predicate { $0.uuid == eventID }),
            animation: .default
        )
    }

    private var event: DateEvent? { matches.first }

    var body: some View {
        Group {
            if let event {
                content(for: event, snapshot: event.snapshot)
            } else {
                // Reachable if the event is deleted on another device while open (Phase 06).
                ContentUnavailableView("Date not found", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle(event?.name ?? "Date")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let event {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { isEditing = true }
                        .accessibilityLabel("Edit \(event.name)")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let event {
                EventFormView(mode: .edit(event), store: store)
            }
        }
    }

    @ViewBuilder
    private func content(for event: DateEvent, snapshot: EventSnapshot) -> some View {
        List {
            Section {
                LabeledContent("Next", value: EventFormatting.nextOccurrenceLong(snapshot, now: now))
                LabeledContent("When", value: EventFormatting.daysUntil(snapshot, now: now))
                LabeledContent("Date", value: EventFormatting.recurringDate(snapshot, now: now))
                if let year = EventFormatting.knownYear(snapshot) {
                    LabeledContent("Year", value: year)
                }
                if let badge = EventFormatting.yearsBadge(snapshot, now: now) {
                    LabeledContent(snapshot.type.countsAge ? "Age" : "Years", value: badge)
                }
            }

            Section {
                LabeledContent("Type", value: snapshot.type.displayName)
                LabeledContent("Group", value: snapshot.groupName)
            }

            Section("Alerts") {
                OffsetSummaryView(
                    offsets: snapshot.effectiveOffsets,
                    isInherited: snapshot.inheritsGroupOffsets,
                    groupName: snapshot.groupName
                )
            }

            Section {
                Button("Delete date", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .confirmationDialog(
            "Delete \(event.name)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await store.deleteEvent(event)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the date and its reminders.")
        }
    }
}
