import SwiftUI
import UserNotifications
import DatesKit

/// Global notification time plus a read-out of the pending queue (NOTIF-09, NOTIF-04).
struct SettingsView: View {
    let store: EventStore
    @Bindable var settings: AppSettings

    @Environment(\.dismiss) private var dismiss
    @State private var authorizationStatus: UNAuthorizationStatus?
    @State private var isExportingCSV = false
    @State private var exportResultMessage: String?
    @State private var importFlow = ImportFlow()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Notify me at",
                        selection: notificationTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                } header: {
                    Text("Reminder time")
                } footer: {
                    Text(reminderFooter)
                }

                if let authorizationStatus, authorizationStatus == .denied {
                    Section {
                        Label("Notifications are turned off", systemImage: "bell.slash")
                        Text("Your dates are all still here. Turn notifications on in the Settings app to get reminders.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let summary = store.queueSummary, summary.failedCount > 0 {
                    Section {
                        Label("\(summary.failedCount) reminders could not be scheduled", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        importFlow.fetchCalendarCandidates()
                    } label: {
                        Label("Import from Calendar", systemImage: "calendar")
                    }
                    .disabled(importFlow.isFetchingCalendar)

                    Button {
                        importFlow.isPickingCSV = true
                    } label: {
                        Label("Import a CSV", systemImage: "doc.text")
                    }

                    Button {
                        isExportingCSV = true
                    } label: {
                        Label("Export as CSV", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Importing shows a review first and skips the dates you already have. Export writes a file readable by any spreadsheet.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .importFlow(importFlow, store: store)
            // The review sheet closing means an import may have rebuilt the queue.
            .onChange(of: importFlow.payload) { _, payload in
                if payload == nil {
                    Task { await refreshDiagnostics() }
                }
            }
            .fileExporter(
                isPresented: $isExportingCSV,
                document: CSVExportDocument(text: EventCSV.encode(store.snapshots())),
                contentType: .commaSeparatedText,
                defaultFilename: "Dates"
            ) { result in
                if case .failure(let error) = result {
                    exportResultMessage = error.localizedDescription
                }
            }
            .alert("Export failed", isPresented: .constant(exportResultMessage != nil)) {
                Button("OK") { exportResultMessage = nil }
            } message: {
                Text(exportResultMessage ?? "")
            }
            .task { await refreshDiagnostics() }
            .onChange(of: settings.notificationTime) {
                // Changing the time invalidates every pending fire date (NOTIF-09).
                Task {
                    await store.rescheduleAll()
                    await refreshDiagnostics()
                }
            }
        }
    }

    private var notificationTimeBinding: Binding<Date> {
        Binding(
            get: {
                settings.notificationTime.applied(to: Date(), calendar: .current) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.notificationTime = TimeOfDay(
                    hour: components.hour ?? TimeOfDay.defaultNotificationTime.hour,
                    minute: components.minute ?? TimeOfDay.defaultNotificationTime.minute
                )
            }
        )
    }

    /// One quiet sentence in place of the old diagnostics table: what is scheduled and how
    /// far it reaches (NOTIF-04 stays observable), with the mechanics kept out of sight.
    private var reminderFooter: String {
        let base = "Applies to every reminder, on the day and in advance."
        guard let summary = store.queueSummary,
              summary.totalEventCount > 0,
              let horizon = summary.coverageHorizon
        else { return base }

        let through = horizon.formatted(date: .abbreviated, time: .omitted)
        if summary.wasTruncated {
            return base + " Your nearest \(summary.coveredEventCount) of \(summary.totalEventCount) dates have reminders scheduled, through \(through); the rest join as their day approaches."
        }
        if summary.totalEventCount == 1 {
            return base + " Your date has reminders scheduled through \(through)."
        }
        return base + " All \(summary.totalEventCount) dates have reminders scheduled through \(through)."
    }

    private func refreshDiagnostics() async {
        authorizationStatus = await NotificationScheduler.shared.authorizationStatus()
    }
}
