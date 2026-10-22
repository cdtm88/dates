import SwiftUI
import SwiftData
import UserNotifications
import DatesKit

/// Global notification time plus a read-out of the pending queue (NOTIF-09, NOTIF-04).
struct SettingsView: View {
    let store: EventStore
    @Bindable var settings: AppSettings

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorizationStatus: UNAuthorizationStatus?
    @State private var hasICloudAccount = FileManager.default.ubiquityIdentityToken != nil
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

                if authorizationStatus == .notDetermined, store.queueSummary?.totalEventCount ?? 0 > 0 {
                    Section {
                        Label("Reminders aren't on yet", systemImage: "bell.badge")
                        Button("Turn On Reminders") {
                            Task {
                                await store.requestNotificationAuthorisation()
                                await refreshDiagnostics()
                            }
                        }
                    }
                }

                if let authorizationStatus, authorizationStatus == .denied {
                    Section {
                        Label("Notifications are turned off", systemImage: "bell.slash")
                        Text("Your dates are all still here. Turn notifications on in the Settings app to get reminders.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                }

                if let summary = store.queueSummary, summary.failedCount > 0 {
                    Section {
                        Label("^[\(summary.failedCount) reminder](inflect: true) could not be scheduled", systemImage: "exclamationmark.triangle")
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
                    LabeledContent("iCloud sync", value: isSyncing ? "On" : "Off")
                } footer: {
                    Text(syncFooter)
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
                                .font(.title2.bold())
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
            .horizontalBarsOnly()
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
            // Back from the Settings app, where the user may just have turned notifications on.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshDiagnostics() } }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSUbiquityIdentityDidChange)
                    .receive(on: DispatchQueue.main)
            ) { _ in
                hasICloudAccount = FileManager.default.ubiquityIdentityToken != nil
            }
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

        let through = horizon.formatted(.dateTime.day().month(.abbreviated).year().locale(.dateDisplay()))
        if summary.wasTruncated {
            return base + " Your nearest \(summary.coveredEventCount) of \(summary.totalEventCount) dates have reminders scheduled, through \(through); the rest join as their day approaches."
        }
        if summary.totalEventCount == 1 {
            return base + " Your date has reminders scheduled through \(through)."
        }
        return base + " All \(summary.totalEventCount) dates have reminders scheduled through \(through)."
    }

    /// Whether the open store is the CloudKit-backed one and there is still an account to
    /// sync with. The container is chosen at launch, so an account added since then, or a
    /// CloudKit store that failed to open, leaves this session local-only; signing out
    /// mid-session pauses a CloudKit store that is open.
    private var isSyncing: Bool {
        hasICloudAccount
            && modelContext.container.configurations.contains { $0.cloudKitContainerIdentifier != nil }
    }

    private var syncFooter: String {
        if isSyncing {
            return "Your dates sync privately through iCloud to your other devices."
        }
        #if DEBUG
        // Debug builds never open the CloudKit store (see DatesApp.makeBestContainer).
        return "iCloud sync is off in development builds."
        #else
        if hasICloudAccount {
            return "Close Dates and open it again to start syncing with iCloud."
        }
        return "Sign in to iCloud in the Settings app to sync your dates across your devices. Everything stays on this device until then."
        #endif
    }

    private func refreshDiagnostics() async {
        authorizationStatus = await NotificationScheduler.shared.authorizationStatus()
        hasICloudAccount = FileManager.default.ubiquityIdentityToken != nil
    }
}
