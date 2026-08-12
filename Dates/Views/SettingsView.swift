import SwiftUI
import UserNotifications
import DatesKit

/// Global notification time plus a read-out of the pending queue (NOTIF-09, NOTIF-04).
struct SettingsView: View {
    let store: EventStore
    @Bindable var settings: AppSettings

    @Environment(\.dismiss) private var dismiss
    @State private var authorizationStatus: UNAuthorizationStatus?
    @State private var pendingCount: Int?

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
                    Text("Applies to every reminder, on the day and in advance.")
                }

                if let authorizationStatus, authorizationStatus == .denied {
                    Section {
                        Label("Notifications are turned off", systemImage: "bell.slash")
                        Text("Your dates are all still here. Turn notifications on in the Settings app to get reminders.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if let summary = store.queueSummary {
                        LabeledContent("Scheduled", value: "\(summary.scheduledCount) of \(summary.ceiling)")
                        LabeledContent("Dates covered", value: "\(summary.coveredEventCount) of \(summary.totalEventCount)")
                        if let horizon = summary.coverageHorizon {
                            LabeledContent("Covered until", value: horizon.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    if let pendingCount {
                        LabeledContent("Pending on device", value: "\(pendingCount)")
                    }
                } header: {
                    Text("Reminder queue")
                } footer: {
                    Text("iOS allows 64 pending reminders at once, so the nearest dates are scheduled first and the queue is topped up each time you open the app.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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

    private func refreshDiagnostics() async {
        authorizationStatus = await NotificationScheduler.shared.authorizationStatus()
        pendingCount = await NotificationScheduler.shared.pendingEventNotificationCount()
    }
}
