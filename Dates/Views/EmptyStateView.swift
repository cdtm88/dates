import SwiftUI

/// The empty list state, offering the three entry routes (LIST-06).
///
/// Calendar and CSV import are Phase 05. They appear here from the start because the empty
/// state is where a new user decides how to populate the app, and hiding them until later
/// would mean redesigning this screen twice. They are disabled rather than absent so nobody
/// taps into a dead end.
struct EmptyStateView: View {
    var onAddManually: () -> Void
    var importAvailable: Bool = false
    var onImportCalendar: () -> Void = {}
    var onImportCSV: () -> Void = {}

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)

                Text("No dates yet")
                    .font(.title3.weight(.semibold))

                Text("Add the birthdays, anniversaries and key dates you want to be reminded about.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Button(action: onAddManually) {
                    Label("Add a date", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onImportCalendar) {
                    Label("Import from Calendar", systemImage: "calendar")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!importAvailable)

                Button(action: onImportCSV) {
                    Label("Import a CSV", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!importAvailable)

                if !importAvailable {
                    Text("Importing arrives in a later release.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 320)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
