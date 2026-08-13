import Foundation
import Observation

/// Publishes "now", refreshed when the local day changes.
///
/// LIST-03 requires an event dated today to hold the top of the list until 23:59:59 and then
/// move to its next-year position. Without this the list would only reorder when something
/// else happened to redraw it, and a phone left open overnight would show yesterday's event
/// at the top all morning (D-12).
@MainActor
@Observable
final class DayTicker {
    private(set) var now: Date = Date()
    @ObservationIgnored private var task: Task<Void, Never>?

    func start(calendar: Calendar = .current) {
        stop()
        now = Date()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = Self.secondsUntilNextMidnight(from: Date(), calendar: calendar) else { return }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.now = Date()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Called when the app returns to the foreground, where the sleep above may have been
    /// suspended across the boundary.
    func refresh() {
        now = Date()
    }

    private static func secondsUntilNextMidnight(from date: Date, calendar: Calendar) -> TimeInterval? {
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else {
            return nil
        }
        // A second past the boundary, so the new day has definitely started.
        return max(nextMidnight.timeIntervalSince(date) + 1, 1)
    }
}
