import WidgetKit
import SwiftUI
import DatesKit

/// The next few dates, on the home screen and the lock screen.
///
/// The timeline is one entry refreshed at local midnight: nothing in the data changes
/// mid-day, and every countdown ticks over exactly when the day does. Edits inside the
/// app arrive sooner than that — the store reloads the timelines after every save.
struct UpcomingDatesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpcomingDates", provider: UpcomingProvider()) { entry in
            UpcomingDatesView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Upcoming dates")
        .description("The next birthdays and anniversaries from your list.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct UpcomingEntry: TimelineEntry {
    let date: Date
    let events: [WidgetEvent]
}

struct UpcomingProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingEntry {
        UpcomingEntry(date: Date(), events: UpcomingEntry.sampleEvents)
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingEntry) -> Void) {
        completion(entry(now: Date(), preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let nextMidnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        )
        completion(Timeline(entries: [entry(now: now, preview: false)], policy: .after(nextMidnight)))
    }

    private func entry(now: Date, preview: Bool) -> UpcomingEntry {
        let stored = WidgetBridge.read()
        if stored.isEmpty && preview {
            return UpcomingEntry(date: now, events: UpcomingEntry.sampleEvents)
        }
        return UpcomingEntry(date: now, events: WidgetBridge.upcoming(stored, limit: 3, now: now))
    }
}

extension UpcomingEntry {
    /// Gallery and placeholder content, dated relative to now so the countdowns read well.
    static var sampleEvents: [WidgetEvent] {
        let calendar = Calendar.current
        let now = Date()
        func sample(_ name: String, daysAhead: Int, type: EventType) -> WidgetEvent? {
            guard let day = calendar.date(byAdding: .day, value: daysAhead, to: now) else { return nil }
            let components = calendar.dateComponents([.month, .day], from: day)
            guard let month = components.month, let dayOfMonth = components.day,
                  let date = AnnualDate(month: month, day: dayOfMonth) else { return nil }
            return WidgetEvent(id: UUID(), name: name, type: type, date: date)
        }
        return [
            sample("Mum", daysAhead: 2, type: .birthday),
            sample("Priya & Sam", daysAhead: 9, type: .anniversary),
            sample("Grandpa Joe", daysAhead: 16, type: .birthday),
        ].compactMap { $0 }
    }
}

// MARK: - Views

struct UpcomingDatesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingEntry

    var body: some View {
        if entry.events.isEmpty {
            emptyState
        } else {
            switch family {
            case .accessoryRectangular:
                accessoryRow(entry.events[0])
            case .systemSmall:
                nextEvent(entry.events[0])
            default:
                eventList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "calendar.badge.plus")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No dates yet")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// systemSmall: the single next date, countdown first because that is the question a
    /// glance is asking.
    private func nextEvent(_ event: WidgetEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(WidgetFormatting.daysUntil(event, now: entry.date))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                if event.milestoneYears(from: entry.date) != nil {
                    Image(systemName: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.tint)
                }
            }
            Spacer(minLength: 0)
            Text(event.name)
                .font(.headline)
                .lineLimit(2)
            Text(WidgetFormatting.subtitle(event, now: entry.date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// systemMedium: up to three rows, the same shape as the app's list.
    private var eventList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entry.events) { event in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(event.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            if event.milestoneYears(from: entry.date) != nil {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(.tint)
                            }
                        }
                        Text(WidgetFormatting.subtitle(event, now: entry.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(WidgetFormatting.daysUntil(event, now: entry.date))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Lock screen: one line of name, one of countdown and date.
    private func accessoryRow(_ event: WidgetEvent) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(event.name)
                    .font(.headline)
                    .lineLimit(1)
                if event.milestoneYears(from: entry.date) != nil {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                }
            }
            Text("\(WidgetFormatting.daysUntil(event, now: entry.date)) · \(WidgetFormatting.shortDate(event, now: entry.date))")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Display strings for the widget. Deliberately tiny — the app's `EventFormatting` carries
/// cached formatters and list-specific shapes the widget does not need.
enum WidgetFormatting {
    static func daysUntil(_ event: WidgetEvent, now: Date, calendar: Calendar = .current) -> String {
        switch event.date.daysUntilNextOccurrence(from: now, calendar: calendar) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case let .some(days): return "In \(days) days"
        case nil: return "—"
        }
    }

    static func shortDate(_ event: WidgetEvent, now: Date, calendar: Calendar = .current) -> String {
        guard let occurrence = event.date.nextOccurrence(from: now, calendar: calendar) else {
            return "\(event.date.day)/\(event.date.month)"
        }
        return occurrence.formatted(.dateTime.day().month(.abbreviated))
    }

    static func subtitle(_ event: WidgetEvent, now: Date, calendar: Calendar = .current) -> String {
        var parts = [shortDate(event, now: now, calendar: calendar)]
        if let years = event.date.yearsElapsedAtNextOccurrence(from: now, calendar: calendar) {
            if event.type.countsAge {
                parts.append("turns \(years)")
            } else {
                parts.append(years == 1 ? "1 year" : "\(years) years")
            }
        }
        return parts.joined(separator: " · ")
    }
}
