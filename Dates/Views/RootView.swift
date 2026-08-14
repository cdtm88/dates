import SwiftUI
import SwiftData
import DatesKit

/// Wires the store, the day ticker, and the notification router, and owns the lifecycle work.
struct RootView: View {
    @Bindable var settings: AppSettings
    @Bindable var router: NotificationRouter

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var store: EventStore?
    @State private var ticker = DayTicker()

    var body: some View {
        Group {
            if let store {
                EventListView(store: store, settings: settings, router: router, now: ticker.now)
            } else {
                ProgressView()
            }
        }
        // Applied at the root so every sheet and alert follows; nil means the device decides.
        // Light is the first-launch default (UI-01, Phase 07).
        .preferredColorScheme(settings.appearance.colorScheme)
        .task {
            guard store == nil else { return }

            // Seeding happens before the first list render so a new user never sees an
            // event form with no groups to choose from (GROUP-01).
            _ = try? DatesModelContainer.seedIfNeeded(modelContext)

            let store = EventStore(context: modelContext, settings: settings)
            self.store = store

            ticker.start()

            await store.rescheduleAll()
            BackgroundRefresh.scheduleNextRefresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Foreground top-up: recalculate and refill the queue soonest-first (NOTIF-05).
                ticker.refresh()
                Task { await store?.rescheduleAll() }
            case .background:
                BackgroundRefresh.scheduleNextRefresh()
            default:
                break
            }
        }
    }
}
