import SwiftUI
import DatesKit

/// Three toggles for the three fixed offsets (GROUP-03, PRD §9).
struct OffsetSelectionEditor: View {
    @Binding var selection: OffsetSelection

    var body: some View {
        ForEach(NotificationOffset.allCases.sorted(), id: \.self) { offset in
            Toggle(offset.shortLabel, isOn: binding(for: offset))
        }
    }

    private func binding(for offset: NotificationOffset) -> Binding<Bool> {
        Binding(
            get: { selection.contains(offset) },
            set: { isOn in
                let flag = OffsetSelection.flag(for: offset)
                if isOn {
                    selection.insert(flag)
                } else {
                    selection.remove(flag)
                }
            }
        )
    }
}

/// The read-only summary used on detail screens (LIST-05).
struct OffsetSummaryView: View {
    let offsets: OffsetSelection
    let isInherited: Bool
    let groupName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(EventFormatting.offsetsSummary(offsets))
            Text(isInherited ? "Inherited from \(groupName)" : "Set for this event")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
