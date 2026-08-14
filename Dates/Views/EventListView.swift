import SwiftUI
import SwiftData
import DatesKit

/// The home screen: one chronological list of every date, soonest first (LIST-01 to LIST-06).
struct EventListView: View {
    let store: EventStore
    let settings: AppSettings
    @Bindable var router: NotificationRouter
    let now: Date

    @Query private var events: [DateEvent]
    @Query(sort: \EventGroup.createdAt) private var groups: [EventGroup]

    @State private var path: [UUID] = []
    @State private var searchText = ""
    @State private var selectedGroupID: UUID?
    @State private var isAddingEvent = false
    @State private var isShowingGroups = false
    @State private var isShowingSettings = false
    @State private var importFlow = ImportFlow()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Dates")
                .searchable(text: $searchText, prompt: "Search names")
                .toolbar { toolbarContent }
                .navigationDestination(for: UUID.self) { eventID in
                    EventDetailView(eventID: eventID, store: store, now: now)
                }
                .sheet(isPresented: $isAddingEvent) {
                    EventFormView(mode: .create, store: store)
                }
                .sheet(isPresented: $isShowingGroups) {
                    GroupsView(store: store)
                }
                .sheet(isPresented: $isShowingSettings) {
                    SettingsView(store: store, settings: settings)
                }
                .importFlow(importFlow, store: store)
        }
        // A notification tap opens that event's detail view and does nothing else (NOTIF-10).
        .onChange(of: router.pendingEventID) {
            guard let eventID = router.consumePendingEventID() else { return }
            guard events.contains(where: { $0.uuid == eventID }) else { return }
            path = [eventID]
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if events.isEmpty {
            EmptyStateView(
                onAddManually: { isAddingEvent = true },
                importAvailable: true,
                onImportCalendar: { importFlow.fetchCalendarCandidates(now: now) },
                onImportCSV: { importFlow.isPickingCSV = true }
            )
        } else if rows.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List {
                ForEach(rows) { row in
                    NavigationLink(value: row.id) {
                        EventRowView(event: row, now: now)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    /// Filtering and sorting run here rather than in the SwiftData query, because
    /// days-until-next-occurrence is derived from month/day components and is not a stored
    /// property a `SortDescriptor` could reach (D-11).
    ///
    /// This is a view body, not a per-frame cost: SwiftUI re-evaluates it when the query,
    /// the search text, the group filter, or the day changes. Sorting 500 events measures
    /// well inside a millisecond, so scrolling stays on the row rendering budget (PERF-02).
    private var rows: [EventSnapshot] {
        EventOrdering.filteredAndSorted(
            events.map(\.snapshot),
            groupID: selectedGroupID,
            query: searchText,
            now: now
        )
    }

    private var selectedGroupName: String? {
        groups.first { $0.uuid == selectedGroupID }?.name
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Group", selection: $selectedGroupID) {
                    Text("All groups").tag(UUID?.none)
                    ForEach(groups) { group in
                        Text(group.name).tag(Optional(group.uuid))
                    }
                }

                Divider()

                Button {
                    isShowingGroups = true
                } label: {
                    Label("Manage groups", systemImage: "folder")
                }

                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            } label: {
                Label(
                    selectedGroupName ?? "All groups",
                    systemImage: selectedGroupID == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
                )
            }
            .accessibilityLabel("Filter and settings. Showing \(selectedGroupName ?? "all groups").")
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    isAddingEvent = true
                } label: {
                    Label("Add a date", systemImage: "plus")
                }

                Divider()

                Button {
                    importFlow.fetchCalendarCandidates(now: now)
                } label: {
                    Label("Import from Calendar", systemImage: "calendar")
                }
                .disabled(importFlow.isFetchingCalendar)

                Button {
                    importFlow.isPickingCSV = true
                } label: {
                    Label("Import a CSV", systemImage: "doc.text")
                }
            } label: {
                Label("Add a date", systemImage: "plus")
            } primaryAction: {
                isAddingEvent = true
            }
        }
    }
}
