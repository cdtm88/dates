import SwiftUI

/// The empty list state, offering the three entry routes (LIST-06).
struct EmptyStateView: View {
    var onAddManually: () -> Void
    var isImportingContacts = false
    var onImportContacts: () -> Void = {}
    var onImportCSV: () -> Void = {}

    var body: some View {
        // Scrolls only when it no longer fits, as at the largest accessibility sizes;
        // otherwise it fills the screen and stays centred.
        GeometryReader { proxy in
            ScrollView {
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

                        Button(action: onImportContacts) {
                            Label("Import from Contacts", systemImage: "person.crop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isImportingContacts)

                        Button(action: onImportCSV) {
                            Label("Import a CSV", systemImage: "doc.text")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: 320)
                }
                .padding(32)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
