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
    @State private var exportDocument: CSVExportDocument?
    @State private var exportResultMessage: String?
    @State private var importFlow = ImportFlow()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(Appearance.allCases) { appearance in
                            Text(appearance.displayName).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                }

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
                        importFlow.fetchContactCandidates()
                    } label: {
                        Label("Import from Contacts", systemImage: "person.crop.circle")
                    }
                    .disabled(importFlow.isFetchingContacts)

                    Button {
                        importFlow.isPickingCSV = true
                    } label: {
                        Label("Import a CSV", systemImage: "doc.text")
                    }

                    Button {
                        // Encoded once here, not in the `fileExporter` argument, which is
                        // re-evaluated on every body pass whether or not an export is on.
                        exportDocument = CSVExportDocument(text: EventCSV.encode(store.snapshots()))
                        isExportingCSV = true
                    } label: {
                        Label("Export as CSV", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Importing shows a review first and skips the dates you already have. Export writes a file readable by any spreadsheet.")
                }

                Section {
                    LabeledContent("iCloud sync", value: hasICloudAccount ? "On" : "Off")
                } footer: {
                    Text(hasICloudAccount
                         ? "Your dates sync privately through iCloud to your other devices."
                         : "Sign in to iCloud in the Settings app to sync your dates across your devices. Everything stays on this device until then.")
                }

                // The lockup is composed here rather than using the rendered wordmark PNGs,
                // whose baked-in backgrounds sit as an opaque slab on the grouped form
                // background. The mark PNG is transparent and the text takes the label
                // colour, so this blends in both appearances.
                Section {
                    EmptyView()
                } footer: {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image("BrandMark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 26, height: 26)
                            Text("Dates")
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                        .accessibilityHidden(true)
                        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                            Text("Version \(version)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
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
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "Dates"
            ) { result in
                exportDocument = nil
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

    /// Whether the device has an iCloud account at all — the user-fixable half of sync.
    /// The store handles the rest (SwiftData pauses sync without an account and catches
    /// up when one appears), so this row is a status hint, not a switch.
    private var hasICloudAccount: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private func refreshDiagnostics() async {
        authorizationStatus = await NotificationScheduler.shared.authorizationStatus()
    }
}
