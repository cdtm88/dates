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
    @State private var isYearKnown = false
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var selectedGroupID: UUID?
    @State private var overridesOffsets = false
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

                Section("Date") {
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

                    Toggle("I know the year", isOn: $isYearKnown)

                    if isYearKnown {
                        Picker("Year", selection: $year) {
                            ForEach(yearRange, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                    } else {
                        Text("Without a year, no age is shown.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Group") {
                    Picker("Group", selection: $selectedGroupID) {
                        ForEach(groups) { group in
                            Text(group.name).tag(Optional(group.uuid))
                        }
                    }
                }

                Section("Alerts") {
                    Toggle("Set alerts for this date", isOn: $overridesOffsets)

                    if overridesOffsets {
                        OffsetSelectionEditor(selection: $offsets)
                        if offsets.isEmpty {
                            Text("This date will never notify you.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(inheritedSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            .onChange(of: isYearKnown) { clampDay() }
        }
    }

    // MARK: - Derived state

    /// The day picker adapts to the month, and to the year when one is known, so 29 February
    /// is offerable for a year-unknown date but not for a stored non-leap year (DATA-04).
    private var maxDay: Int {
        let referenceYear = isYearKnown ? year : 2000
        return AnnualDate.daysInMonth(month, year: referenceYear, calendar: .current) ?? 31
    }

    private var selectedGroup: EventGroup? {
        groups.first { $0.uuid == selectedGroupID }
    }

    private var inheritedSummary: String {
        guard let group = selectedGroup else { return "Inherits the group default." }
        return "Inherits \(EventFormatting.offsetsSummary(group.defaultOffsets).lowercased()) from \(group.name)."
    }

    private func clampDay() {
        if day > maxDay { day = maxDay }
    }

    // MARK: - Load and save

    private func loadInitialValues() {
        guard case let .edit(event) = mode else {
            selectedGroupID = selectedGroupID ?? groups.first(where: { !$0.isUngrouped })?.uuid ?? groups.first?.uuid
            return
        }
        name = event.name
        type = event.type
        month = event.month
        day = event.day
        if let storedYear = event.year {
            isYearKnown = true
            year = storedYear
        } else {
            isYearKnown = false
        }
        selectedGroupID = event.group?.uuid ?? groups.first?.uuid
        if let override = event.offsetOverride {
            overridesOffsets = true
            offsets = override
        } else {
            overridesOffsets = false
            offsets = event.group?.defaultOffsets ?? .dayOf
        }
    }

    private func save() async {
        guard let date = AnnualDate(month: month, day: day, year: isYearKnown ? year : nil) else {
            errorMessage = "That date does not exist."
            return
        }

        isSaving = true
        defer { isSaving = false }

        let override: OffsetSelection? = overridesOffsets ? offsets : nil

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
