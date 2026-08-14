import SwiftUI
import SwiftData
import DatesKit

/// Create and edit an event (DATA-01, DATA-02, GROUP-04).
struct EventFormView: View {
    enum Mode: Equatable {
        case create
        case edit(DateEvent)

        var title: String {
            switch self {
            case .create: return "New date"
            case .edit: return "Edit date"
            }
        }
    }

    let mode: Mode
    let store: EventStore

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EventGroup.createdAt) private var groups: [EventGroup]

    @State private var name = ""
    @State private var type: EventType = .birthday
    @State private var month = 1
    @State private var day = 1
    /// Nil is the default: the year is optional, and no age is shown without one (DATA-03).
    @State private var year: Int?
    @State private var selectedGroupID: UUID?
    @State private var offsets: OffsetSelection = .dayOf

    @State private var errorMessage: String?
    @State private var isSaving = false

    private let yearRange = Array((1900...Calendar.current.component(.year, from: Date())).reversed())

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Type", selection: $type) {
                        ForEach(EventType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section {
                    Picker("Month", selection: $month) {
                        ForEach(1...12, id: \.self) { month in
                            Text(EventFormatting.monthName(month)).tag(month)
                        }
                    }

                    Picker("Day", selection: $day) {
                        ForEach(1...maxDay, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }

                    // The tag types must stay `Int?` to match the selection, or the picker
                    // silently renders with nothing selected (see docs/xcode-handover.md).
                    Picker("Year", selection: $year) {
                        Text("Not set").tag(Int?.none)
                        ForEach(yearRange, id: \.self) { year in
                            Text(String(year)).tag(Optional(year))
                        }
                    }
                } header: {
                    Text("Date")
                } footer: {
                    if year == nil {
                        Text("The year is optional. Without one, no age is shown.")
                    }
                }

                Section("Group") {
                    Picker("Group", selection: $selectedGroupID) {
                        ForEach(groups) { group in
                            Text(group.name).tag(Optional(group.uuid))
                        }
                    }
                }

                Section {
                    OffsetSelectionEditor(selection: $offsets)
                } header: {
                    Text("Alerts")
                } footer: {
                    Text(alertsFooter)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!EventValidation.isValidName(name) || isSaving)
                }
            }
            .onAppear(perform: loadInitialValues)
            .onChange(of: month) { clampDay() }
            .onChange(of: year) { clampDay() }
            // Untouched alerts follow the group: if the toggles still match the group the
            // user is leaving, they re-seed from the one they are joining. A selection the
            // user has diverged is theirs and is left alone.
            .onChange(of: selectedGroupID) { oldID, newID in
                let oldDefault = groups.first { $0.uuid == oldID }?.defaultOffsets
                if offsets == oldDefault, let newDefault = groups.first(where: { $0.uuid == newID })?.defaultOffsets {
                    offsets = newDefault
                }
            }
        }
    }

    // MARK: - Derived state

    /// The day picker adapts to the month, and to the year when one is known, so 29 February
    /// is offerable for a year-unknown date but not for a stored non-leap year (DATA-04).
    private var maxDay: Int {
        // 2000 is a leap year, so 29 February stays offerable while the year is unset.
        AnnualDate.daysInMonth(month, year: year ?? 2000, calendar: .current) ?? 31
    }

    private var selectedGroup: EventGroup? {
        groups.first { $0.uuid == selectedGroupID }
    }

    /// Says whether this selection is the group's default or the event's own, and warns
    /// when it means silence — the state the old master toggle used to carry.
    private var alertsFooter: String {
        guard let group = selectedGroup else { return "" }
        if offsets == group.defaultOffsets {
            return "\(group.name)'s default. If the group's alerts change, this date follows."
        }
        if offsets.isEmpty {
            return "This date will never notify you."
        }
        return "Set just for this date. \(group.name)'s default is \(EventFormatting.offsetsSummary(group.defaultOffsets).lowercased())."
    }

    private func clampDay() {
        if day > maxDay { day = maxDay }
    }

    // MARK: - Load and save

    private func loadInitialValues() {
        guard case let .edit(event) = mode else {
            selectedGroupID = selectedGroupID ?? groups.first(where: { !$0.isUngrouped })?.uuid ?? groups.first?.uuid
            offsets = selectedGroup?.defaultOffsets ?? .dayOf
            return
        }
        name = event.name
        type = event.type
        month = event.month
        day = event.day
        year = event.year
        selectedGroupID = event.group?.uuid ?? groups.first?.uuid
        offsets = event.effectiveOffsets
    }

    private func save() async {
        guard let date = AnnualDate(month: month, day: day, year: year) else {
            errorMessage = "That date does not exist."
            return
        }

        isSaving = true
        defer { isSaving = false }

        // A selection matching the group default is stored as "inherit", so a later change
        // to the group's alerts still flows through (GROUP-05). Only a divergent selection
        // becomes a per-event override — including empty, which means "never notify".
        let override: OffsetSelection? = offsets == selectedGroup?.defaultOffsets ? nil : offsets

        do {
            switch mode {
            case .create:
                try await store.createEvent(
                    name: name,
                    date: date,
                    type: type,
                    group: selectedGroup,
                    offsetOverride: override
                )
            case let .edit(event):
                try await store.updateEvent(
                    event,
                    name: name,
                    date: date,
                    type: type,
                    group: selectedGroup,
                    offsetOverride: override
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
