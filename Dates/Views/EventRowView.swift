import SwiftUI
import DatesKit

/// One row of the home list (LIST-02): name, date, days-until, group, and the age or years
/// elapsed where the year is known.
struct EventRowView: View {
    let event: EventSnapshot
    let now: Date
    var calendar: Calendar = .current

    private var isToday: Bool { event.isToday(now, calendar: calendar) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                // One concatenated Text, so at large sizes it wraps as a sentence rather
                // than squeezing each fragment into its own column.
                subtitle
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(EventFormatting.daysUntil(event, now: now, calendar: calendar))
                .font(.footnote.weight(isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EventFormatting.accessibilityLabel(event, now: now, calendar: calendar))
    }

    private var subtitle: Text {
        var text = Text("\(EventFormatting.recurringDate(event, now: now, calendar: calendar)) · \(event.groupName)")
        if let badge = EventFormatting.yearsBadge(event, now: now, calendar: calendar) {
            text = text + Text(" · ")
            if event.milestoneYears(from: now, calendar: calendar) != nil {
                // A milestone year gets the accent and a spark, nothing louder:
                // the row stays scannable and ordinary years stay quiet.
                text = text + Text("\(Image(systemName: "sparkles")) \(badge)")
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
            } else {
                text = text + Text(badge)
            }
        }
        return text
    }
}
