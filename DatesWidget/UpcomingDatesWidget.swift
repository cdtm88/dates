import WidgetKit
import SwiftUI
import DatesKit

/// The next few dates, on the home screen and the lock screen.
///
/// The timeline holds one entry per local midnight for the coming week: nothing in the
/// data changes mid-day, and pre-computed entries tick every countdown over exactly when
/// the day does, rather than whenever WidgetKit gets round to a reload. Edits inside the
/// app arrive sooner than that — the store reloads the timelines after every save.
struct UpcomingDatesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpcomingDates", provider: UpcomingProvider()) { entry in
            UpcomingDatesView(entry: entry)
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
        let today = calendar.startOfDay(for: now)
        let midnights = (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let entries = [entry(now: now, preview: false)] + midnights.map { entry(now: $0, preview: false) }
        completion(Timeline(entries: entries, policy: .atEnd))
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
        let calendar = Calendar.current.gregorian
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
        content
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var content: some View {
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

    /// The same pair every stock widget uses — white in light mode, the elevated grey
    /// (not pure black) in dark. A clear background here renders as black and makes the
    /// widget look unlike its neighbours. The lock screen stays clear: the system draws
    /// its own material behind accessory families.
    @ViewBuilder
    private var background: some View {
        if family == .accessoryRectangular {
            Color.clear
        } else {
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark ? .secondarySystemBackground : .systemBackground
            })
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
                    milestoneGlyph
                        .font(.footnote)
                        .foregroundStyle(.tint)
                }
            }
            Spacer(minLength: 0)
            Text(event.name)
                .font(.headline)
                .lineLimit(2)
                .privacySensitive()
            Text(WidgetFormatting.subtitle(event, now: entry.date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
                                .privacySensitive()
                            if event.milestoneYears(from: entry.date) != nil {
                                milestoneGlyph
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
                .accessibilityElement(children: .combine)
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
                    .privacySensitive()
                if event.milestoneYears(from: entry.date) != nil {
                    milestoneGlyph
                        .font(.caption2)
                }
            }
            Text("\(WidgetFormatting.daysUntil(event, now: entry.date)) · \(WidgetFormatting.shortDate(event, now: entry.date))")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Spoken as "milestone" rather than the symbol's name.
    private var milestoneGlyph: some View {
        Image(systemName: "sparkles")
            .accessibilityLabel("Milestone")
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
        return occurrence.formatted(.dateTime.day().month(.abbreviated).locale(.dateDisplay()))
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
