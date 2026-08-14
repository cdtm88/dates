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
        do {
            container = try DatesModelContainer.makeContainer(inMemory: isUITesting)
        } catch {
            // Falling back to memory keeps the app usable for the session rather than
            // crashing on launch. The user sees their data missing, which is bad, but a
            // hard crash on every launch is worse and unrecoverable without a reinstall.
            do {
                container = try DatesModelContainer.makeContainer(inMemory: true)
            } catch {
                fatalError("Could not create a model container: \(error)")
            }
        }

        // Every stored property is initialised by this point, which `self` needs.
        router.register()
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
