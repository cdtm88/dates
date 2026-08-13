import Foundation

/// A plain-value view of a stored group, so group rules are testable without SwiftData.
public struct GroupSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let defaultOffsets: OffsetSelection
    /// The Ungrouped group cannot be deleted and always exists (GROUP-01).
    public let isUngrouped: Bool

    public init(id: UUID, name: String, defaultOffsets: OffsetSelection, isUngrouped: Bool = false) {
        self.id = id
        self.name = name
        self.defaultOffsets = defaultOffsets
        self.isUngrouped = isUngrouped
    }

    public var isDeletable: Bool { !isUngrouped }
}

/// Resolves the offsets that actually apply to an event (GROUP-04).
public enum OffsetResolver {
    /// An event inherits its group's defaults unless it carries its own override.
    ///
    /// The override is stored separately from the group default, so setting one on an
    /// event leaves every other event in that group untouched, and clearing it restores
    /// inheritance (GROUP-04, GROUP-05).
    public static func effectiveOffsets(override: OffsetSelection?, groupDefault: OffsetSelection) -> OffsetSelection {
        override ?? groupDefault
    }
}
