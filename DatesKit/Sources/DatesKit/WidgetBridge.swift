import Foundation

/// One event as the widget sees it: just enough to show a name, a date and a countdown.
///
/// The widget cannot open the SwiftData store — CloudKit-backed containers do not share
/// across processes cheaply — so the app writes this plain-JSON contract into the shared
/// app-group container after every change, and the widget reads it at timeline time.
public struct WidgetEvent: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let type: EventType
    public let date: AnnualDate

    public init(id: UUID, name: String, type: EventType, date: AnnualDate) {
        self.id = id
        self.name = name
        self.type = type
        self.date = date
    }

    public init(snapshot: EventSnapshot) {
        self.init(id: snapshot.id, name: snapshot.name, type: snapshot.type, date: snapshot.date)
    }

    /// The years figure the next occurrence reaches when it is a milestone, mirroring the
    /// app's list so the widget sparkles on the same rows.
    public func milestoneYears(from now: Date, calendar: Calendar = .current) -> Int? {
        guard let years = date.yearsElapsedAtNextOccurrence(from: now, calendar: calendar),
              Milestone.isMilestone(type: type, yearsElapsed: years) else { return nil }
        return years
    }
}

/// The app-group file the app writes and the widget reads.
///
/// Both sides fail soft: no app group (unit tests, a build without the entitlement) means
/// writes are dropped and reads return empty, never an error the caller must handle.
public enum WidgetBridge {
    public static let appGroupID = "group.com.moorelabs.Dates"
    private static let fileName = "widget-events.json"

    public static func fileURL(fileManager: FileManager = .default) -> URL? {
        // The app-group container is a Darwin concept; on Linux (DatesKit's CI) there is
        // nowhere to put the file and nothing to read it.
        #if canImport(Darwin)
        return fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
        #else
        return nil
        #endif
    }

    public static func write(_ events: [WidgetEvent], fileManager: FileManager = .default) {
        guard let url = fileURL(fileManager: fileManager),
              let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func read(fileManager: FileManager = .default) -> [WidgetEvent] {
        guard let url = fileURL(fileManager: fileManager),
              let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder().decode([WidgetEvent].self, from: data)
        else { return [] }
        return events
    }

    /// The soonest-first slice a widget shows, computed at timeline time so the order is
    /// right even when the app has not run for months.
    public static func upcoming(
        _ events: [WidgetEvent],
        limit: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [WidgetEvent] {
        Array(
            events
                .sorted {
                    let lhs = $0.date.daysUntilNextOccurrence(from: now, calendar: calendar) ?? .max
                    let rhs = $1.date.daysUntilNextOccurrence(from: now, calendar: calendar) ?? .max
                    if lhs != rhs { return lhs < rhs }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                .prefix(limit)
        )
    }
}
