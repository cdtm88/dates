import Foundation
import SwiftData
import DatesKit

/// A user-editable grouping with its own default notification offsets (GROUP-01, GROUP-03).
///
/// Every stored property has a default value and the relationship is optional, which is what
/// CloudKit requires of a SwiftData schema. Phase 06 only has to turn the backing on, with no
/// model migration (D-03, D-04).
@Model
final class EventGroup {
    var uuid: UUID = UUID()
    var name: String = ""
    /// `OffsetSelection` bitmask. Stored as an Int so ordering never affects equality.
    var defaultOffsetsRaw: Int = OffsetSelection.dayOf.rawValue
    /// The single group that always exists and cannot be deleted (GROUP-01).
    var isUngrouped: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \DateEvent.group)
    var events: [DateEvent]? = []

    init(
        id: UUID = UUID(),
        name: String,
        defaultOffsets: OffsetSelection,
        isUngrouped: Bool = false,
        createdAt: Date = Date()
    ) {
        self.uuid = id
        self.name = name
        self.defaultOffsetsRaw = defaultOffsets.rawValue
        self.isUngrouped = isUngrouped
        self.createdAt = createdAt
        self.events = []
    }

    var defaultOffsets: OffsetSelection {
        get { OffsetSelection(rawValue: defaultOffsetsRaw) }
        set { defaultOffsetsRaw = newValue.rawValue }
    }

    /// Ungrouped is the fallback for every event, so removing it would leave events with no
    /// offsets to inherit (GROUP-01, GROUP-02).
    var isDeletable: Bool { !isUngrouped }

    var eventCount: Int { events?.count ?? 0 }

    var snapshot: GroupSnapshot {
        GroupSnapshot(id: uuid, name: name, defaultOffsets: defaultOffsets, isUngrouped: isUngrouped)
    }
}
