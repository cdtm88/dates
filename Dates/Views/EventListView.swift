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

    /// The list's three modal destinations, driven by one item so only one sheet modifier
    /// hangs off the content node and only one can ever be asked for at a time.
    private enum ActiveSheet: String, Identifiable {
        case addEvent, groups, settings
        var id: String { rawValue }
    }

    @State private var path: [UUID] = []
    @State private var searchText = ""
    @State private var selectedGroupID: UUID?
    @State private var activeSheet: ActiveSheet?
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
                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case .addEvent:
                        EventFormView(mode: .create, store: store)
                    case .groups:
                        GroupsView(store: store)
                    case .settings:
                        SettingsView(store: store, settings: settings)
                    }
                }
        }
        // On the stack rather than the content, so the import presenters (a sheet, the file
        // picker and an alert) never share a node with the sheet above.
        .importFlow(importFlow, store: store)
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
                onAddManually: { activeSheet = .addEvent },
                importAvailable: true,
                onImportCalendar: { importFlow.fetchCalendarCandidates(now: now) },
                onImportCSV: { importFlow.isPickingCSV = true }
            )
        } else if rows.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            let sections = monthSections
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.events) { row in
                            NavigationLink(value: row.id) {
                                EventRowView(event: row, now: now)
                            }
                            // Rows within a month run unbroken; the only line is the
                            // month divider drawn in the next header below.
                            .listRowSeparator(.hidden)
                            .listSectionSeparator(.hidden)
                        }
                    } header: {
                        // The divider closes the previous month, so it belongs to this
                        // header rather than a footer — a footer adds a tall empty band.
                        VStack(alignment: .leading, spacing: 12) {
                            if section.id != sections.first?.id {
                                Divider()
                            }
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                        .listSectionSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    /// A run of consecutive rows whose next occurrence falls in the same month.
    private struct MonthSection: Identifiable {
        let id: String
        let title: String
        var events: [EventSnapshot]
    }

    /// Rows are already sorted soonest-first, so slicing them at month boundaries yields
    /// sections in chronological order — this month first, wrapping into next year at the
    /// end. Months beyond December carry their year ("January 2027") to mark the wrap.
    private var monthSections: [MonthSection] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        var sections: [MonthSection] = []
        for row in rows {
            let id: String
            let title: String
            if let next = row.nextOccurrence(from: now, calendar: calendar) {
                let month = calendar.component(.month, from: next)
                let year = calendar.component(.year, from: next)
                id = "\(year)-\(month)"
                title = year == currentYear
                    ? EventFormatting.monthName(month)
                    : "\(EventFormatting.monthName(month)) \(year)"
            } else {
                // Unrepresentable dates sort last; they get a section rather than vanishing.
                id = "unknown"
                title = "No date"
            }
            if sections.last?.id == id {
                sections[sections.count - 1].events.append(row)
            } else {
                sections.append(MonthSection(id: id, title: title, events: [row]))
            }
        }
        return sections
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
                    activeSheet = .groups
                } label: {
                    Label("Manage groups", systemImage: "folder")
                }

                Button {
                    activeSheet = .settings
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
                    activeSheet = .addEvent
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
                activeSheet = .addEvent
            }
        }
    }
}
