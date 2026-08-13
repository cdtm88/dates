import Foundation
import Observation
import DatesKit

/// User settings that are device-local rather than synced.
///
/// The notification time is deliberately not part of the SwiftData model: notifications are
/// scheduled per device, and a phone and an iPad should be free to differ.
///
/// The public properties are computed over private stored ones. `@Observable` tracks the
/// private storage, so reads still register a dependency and writes still notify, while the
/// UserDefaults write stays in the setter rather than in a `didSet` observer.
@Observable
final class AppSettings {
    private enum Key {
        static let notificationMinutes = "settings.notificationMinutesSinceMidnight"
        static let hasRequestedNotificationAuthorisation = "settings.hasRequestedNotificationAuthorisation"
    }

    /// Reads the stored time without constructing the observable object, so the background
    /// refresh task can get it without hopping to the main actor (NOTIF-06).
    static func storedNotificationTime(defaults: UserDefaults = .standard) -> TimeOfDay {
        guard let minutes = defaults.object(forKey: Key.notificationMinutes) as? Int else {
            return .defaultNotificationTime
        }
        return TimeOfDay(minutesSinceMidnight: minutes)
    }

    @ObservationIgnored private let defaults: UserDefaults

    private var notificationMinutes: Int
    private var didRequestNotificationAuthorisation: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.notificationMinutes = (defaults.object(forKey: Key.notificationMinutes) as? Int)
            ?? TimeOfDay.defaultNotificationTime.minutesSinceMidnight
        self.didRequestNotificationAuthorisation = defaults.bool(forKey: Key.hasRequestedNotificationAuthorisation)
    }

    /// The single global time all notifications fire at, defaulting to 09:00 (NOTIF-09).
    var notificationTime: TimeOfDay {
        get { TimeOfDay(minutesSinceMidnight: notificationMinutes) }
        set {
            guard newValue.minutesSinceMidnight != notificationMinutes else { return }
            notificationMinutes = newValue.minutesSinceMidnight
            defaults.set(newValue.minutesSinceMidnight, forKey: Key.notificationMinutes)
        }
    }

    /// Tracks whether the system prompt has been shown, so authorisation is requested once on
    /// first event save rather than on every save (NOTIF-01).
    var hasRequestedNotificationAuthorisation: Bool {
        get { didRequestNotificationAuthorisation }
        set {
            guard newValue != didRequestNotificationAuthorisation else { return }
            didRequestNotificationAuthorisation = newValue
            defaults.set(newValue, forKey: Key.hasRequestedNotificationAuthorisation)
        }
    }
}
