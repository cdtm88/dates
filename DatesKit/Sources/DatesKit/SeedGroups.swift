import Foundation

/// The groups created on first launch (GROUP-01).
///
/// The default offset sets are a judgement call the PRD leaves open. They are set so that
/// advance alerts stay meaningful rather than becoming noise (Job 2): only Close family
/// gets the full gift-buying lead time by default, everyone else gets a day-of nudge that
/// is enough to send a message. Any of them can be changed in the app.
public enum SeedGroups {
    public struct Definition: Hashable, Sendable {
        public let name: String
        public let defaultOffsets: OffsetSelection
        public let isUngrouped: Bool

        public init(name: String, defaultOffsets: OffsetSelection, isUngrouped: Bool = false) {
            self.name = name
            self.defaultOffsets = defaultOffsets
            self.isUngrouped = isUngrouped
        }
    }

    /// Reserved name for the group that always exists and cannot be deleted (GROUP-01).
    public static let ungroupedName = "Ungrouped"

    public static let definitions: [Definition] = [
        Definition(name: "Close family", defaultOffsets: [.dayOf, .threeDays, .sevenDays]),
        Definition(name: "Wider family", defaultOffsets: [.dayOf, .sevenDays]),
        Definition(name: "Friends", defaultOffsets: [.dayOf]),
        Definition(name: "Work", defaultOffsets: [.dayOf]),
        Definition(name: ungroupedName, defaultOffsets: [.dayOf], isUngrouped: true),
    ]

    /// The four user-facing seeded groups, excluding Ungrouped.
    public static var userFacingDefinitions: [Definition] {
        definitions.filter { !$0.isUngrouped }
    }
}
