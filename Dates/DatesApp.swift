import SwiftUI
import SwiftData
import DatesKit

@main
struct DatesApp: App {
    // Created once for the process. Both are `@Observable`, so views still track them, and
    // holding them here means the notification delegate is in place before any scene
    // connects — a tap that cold-launches the app would otherwise be delivered before a
    // view had a chance to register (NOTIF-10).
    private let settings: AppSettings
    private let router = NotificationRouter()

    private let container: ModelContainer

    init() {
        // UI tests pass `--uitest` so every run starts from an empty in-memory store
        // rather than whatever the previous run left on disk. Settings get the same
        // treatment: a throwaway suite, so a first-launch assertion (say, the default
        // appearance) cannot be broken by whatever was last chosen on that simulator.
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitest")
        if isUITesting {
            let suiteName = "uitest.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
            settings = AppSettings(defaults: defaults)
        } else {
            settings = AppSettings()
        }
        container = Self.makeBestContainer(isUITesting: isUITesting)

        // Every stored property is initialised by this point, which `self` needs.
        router.register()
    }

    /// CloudKit-backed first (Phase 06); local-only when that init throws — typically a
    /// build without the iCloud entitlement — because losing sync is recoverable and
    /// losing the on-disk data is not. Memory is the last resort: bad, but better than
    /// crashing on every launch, which is unrecoverable without a reinstall.
    private static func makeBestContainer(isUITesting: Bool) -> ModelContainer {
        if isUITesting {
            // Empty in-memory store, no CloudKit: every UI test run starts clean, and the
            // unsigned CI build has no entitlement to satisfy a CloudKit-backed init.
            if let container = try? DatesModelContainer.makeContainer(inMemory: true, syncsWithCloudKit: false) {
                return container
            }
        }
        do {
            return try DatesModelContainer.makeContainer()
        } catch {
            do {
                return try DatesModelContainer.makeContainer(syncsWithCloudKit: false)
            } catch {
                do {
                    return try DatesModelContainer.makeContainer(inMemory: true, syncsWithCloudKit: false)
                } catch {
                    fatalError("Could not create a model container: \(error)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(settings: settings, router: router)
        }
        .modelContainer(container)
        // Best-effort queue top-up while the app is closed (NOTIF-06, D-09).
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            await BackgroundRefresh.performRefresh(
                container: container,
                notificationTime: AppSettings.storedNotificationTime()
            )
        }
    }
}
