import Foundation
import OSLog
import SwiftData
import DatesKit

/// A stored date (DATA-01).
///
/// The date lives as discrete month/day/optional-year components rather than a `Date`,
/// because a recurring annual event has no single instant (D-11). All the maths over those
/// components lives in `DatesKit.AnnualDate`, which is unit-tested without a simulator.
@Model
final class DateEvent {
    var uuid: UUID = UUID()
    var name: String = ""
    var month: Int = 1
    var day: Int = 1
    /// Nil when the year is unknown, in which case no age is ever shown (DATA-03).
    var year: Int?
    var typeRaw: String = EventType.other.rawValue
    /// `OffsetSelection` bitmask, or nil to inherit the group default (GROUP-04).
    /// Nil and "empty set" are deliberately different: the second means "never notify me
    /// about this one".
    var offsetOverrideRaw: Int?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Optional for CloudKit's benefit only; the app always assigns a group, falling back
    /// to Ungrouped (DATA-01).
    var group: EventGroup?

    init(
        id: UUID = UUID(),
        name: String,
        date: AnnualDate,
        type: EventType,
        group: EventGroup?,
        offsetOverride: OffsetSelection? = nil,
        createdAt: Date = Date()
    ) {
        self.uuid = id
        self.name = name
        self.month = date.month
        self.day = date.day
        self.year = date.year
        self.typeRaw = type.rawValue
        self.offsetOverrideRaw = offsetOverride?.rawValue
        self.group = group
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    // MARK: - Typed accessors

    var type: EventType {
        get { EventType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    /// Falls back to 1 January only if the stored components are somehow unrepresentable,
    /// which validation on the way in should prevent. The fault log is the tell that the
    /// store — or, come Phase 06, a CloudKit sync — handed back corrupt components.
    var annualDate: AnnualDate {
        if let date = AnnualDate(month: month, day: day, year: year) {
            return date
        }
        Self.logger.fault("Stored components \(self.month)/\(self.day) for event \(self.uuid) are invalid; showing 1 January")
        return AnnualDate(month: 1, day: 1)!
    }

    func setAnnualDate(_ date: AnnualDate) {
        month = date.month
        day = date.day
        year = date.year
    }

    var offsetOverride: OffsetSelection? {
        get { offsetOverrideRaw.map(OffsetSelection.init(rawValue:)) }
        set { offsetOverrideRaw = newValue?.rawValue }
    }

    var inheritsGroupOffsets: Bool { offsetOverrideRaw == nil }

    var effectiveOffsets: OffsetSelection {
        OffsetResolver.effectiveOffsets(
            override: offsetOverride,
            groupDefault: group?.defaultOffsets ?? .dayOf
        )
    }

    // MARK: - Bridge to the tested domain layer

    /// The value type every rule operates on: ordering, offset resolution, and notification
    /// planning all consume snapshots rather than models.
    var snapshot: EventSnapshot {
        EventSnapshot(
            id: uuid,
            name: name,
            type: type,
            date: annualDate,
            groupID: group?.uuid ?? DateEvent.orphanGroupID,
            groupName: group?.name ?? SeedGroups.ungroupedName,
            groupDefaultOffsets: group?.defaultOffsets ?? .dayOf,
            offsetOverride: offsetOverride
        )
    }

    /// Stand-in id for an event whose group relationship has not resolved yet, so that
    /// grouping logic never has to deal with a nil id.
    static let orphanGroupID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private static let logger = Logger(subsystem: "com.moorelabs.Dates", category: "model")

    func touch(_ date: Date = Date()) {
        updatedAt = date
    }
}
