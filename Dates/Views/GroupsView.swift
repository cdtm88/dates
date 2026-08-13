import SwiftUI
import SwiftData
import DatesKit

/// Create, rename, and delete groups, and set each one's default offsets
/// (GROUP-01 to GROUP-03, GROUP-05).
struct GroupsView: View {
    let store: EventStore

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EventGroup.createdAt) private var groups: [EventGroup]
    @State private var editingGroup: EventGroup?
    @State private var isAddingGroup = false
    @State private var groupPendingDeletion: EventGroup?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(groups) { group in
                        Button {
                            editingGroup = group
                        } label: {
                            row(for: group)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if group.isDeletable {
                                Button("Delete", role: .destructive) {
                                    groupPendingDeletion = group
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Deleting a group moves its dates to \(SeedGroups.ungroupedName). It never deletes them.")
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingGroup = true
                    } label: {
                        Label("Add group", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingGroup) {
                GroupFormView(mode: .create, store: store)
            }
            .sheet(item: $editingGroup) { group in
                GroupFormView(mode: .edit(group), store: store)
            }
            .confirmationDialog(
                groupPendingDeletion.map { "Delete \($0.name)?" } ?? "Delete group?",
                isPresented: Binding(
                    get: { groupPendingDeletion != nil },
                    set: { if !$0 { groupPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let group = groupPendingDeletion else { return }
                    groupPendingDeletion = nil
                    Task { try? await store.deleteGroup(group) }
                }
                Button("Cancel", role: .cancel) { groupPendingDeletion = nil }
            } message: {
                Text("Its dates move to \(SeedGroups.ungroupedName).")
            }
        }
    }

    private func row(for group: EventGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(group.name)
                Spacer()
                Text("\(group.eventCount)")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
            Text(EventFormatting.offsetsSummary(group.defaultOffsets))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name), \(group.eventCount) dates, \(EventFormatting.offsetsSummary(group.defaultOffsets))")
    }
}

/// Create or rename a group and set its default offsets.
struct GroupFormView: View {
    enum Mode: Equatable {
        case create
        case edit(EventGroup)

        var title: String {
            switch self {
            case .create: return "New group"
            case .edit: return "Edit group"
            }
        }
    }

    let mode: Mode
    let store: EventStore

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var offsets: OffsetSelection = .dayOf
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    OffsetSelectionEditor(selection: $offsets)
                } header: {
                    Text("Default alerts")
                } footer: {
                    Text("Applies to every date in this group that does not set its own alerts.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
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
                        .disabled(!EventValidation.isValidName(name))
                }
            }
            .onAppear {
                if case let .edit(group) = mode {
                    name = group.name
                    offsets = group.defaultOffsets
                }
            }
        }
    }

    private func save() async {
        do {
            switch mode {
            case .create:
                try store.createGroup(name: name, defaultOffsets: offsets)
            case let .edit(group):
                try await store.updateGroup(group, name: name, defaultOffsets: offsets)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
