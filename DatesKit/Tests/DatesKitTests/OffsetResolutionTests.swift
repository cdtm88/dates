import XCTest
@testable import DatesKit

/// Phase 02 — GROUP-01, GROUP-03, GROUP-04, GROUP-05.
final class OffsetResolutionTests: XCTestCase {

    // MARK: - Seeded groups (GROUP-01)

    func testFourUserFacingGroupsAreSeededPlusANonDeletableUngrouped() {
        let names = SeedGroups.definitions.map(\.name)
        XCTAssertEqual(names, ["Close family", "Wider family", "Friends", "Work", "Ungrouped"])
        XCTAssertEqual(SeedGroups.userFacingDefinitions.count, 4)

        let ungrouped = SeedGroups.definitions.filter(\.isUngrouped)
        XCTAssertEqual(ungrouped.count, 1)
        XCTAssertEqual(ungrouped.first?.name, SeedGroups.ungroupedName)
    }

    func testUngroupedCannotBeDeletedAndEveryOtherGroupCan() {
        let ungrouped = GroupSnapshot(id: UUID(), name: "Ungrouped", defaultOffsets: [.dayOf], isUngrouped: true)
        let friends = GroupSnapshot(id: UUID(), name: "Friends", defaultOffsets: [.dayOf])
        XCTAssertFalse(ungrouped.isDeletable)
        XCTAssertTrue(friends.isDeletable)
    }

    func testEverySeededGroupHasAtLeastADayOfAlert() {
        // A group whose default is empty would silently produce an event that never
        // notifies, which is the one outcome the app exists to prevent.
        for definition in SeedGroups.definitions {
            XCTAssertTrue(definition.defaultOffsets.contains(.dayOf), "\(definition.name) has no day-of alert")
        }
    }

    // MARK: - Offset sets (GROUP-03)

    func testOffsetSelectionRoundTripsThroughItsBitmask() {
        let pair: OffsetSelection = [.dayOf, .sevenDays]
        XCTAssertEqual(pair.offsets, [.sevenDays, .dayOf])
        XCTAssertEqual(OffsetSelection.all.count, 3)
        XCTAssertTrue(OffsetSelection.empty.isEmpty)
        XCTAssertEqual(OffsetSelection([NotificationOffset.threeDays]).rawValue, OffsetSelection.threeDays.rawValue)
        XCTAssertEqual(OffsetSelection(NotificationOffset.allCases), .all)
    }

    func testOffsetsAreOrderedByWhenTheyFire() {
        // The 7-day alert fires before the 3-day, which fires before the day-of.
        XCTAssertEqual(OffsetSelection.all.offsets, [.sevenDays, .threeDays, .dayOf])
        // Display order is the other way round: nearest first.
        XCTAssertEqual(OffsetSelection.all.displayOrderedOffsets, [.dayOf, .threeDays, .sevenDays])
    }

    func testOffsetSelectionEqualityIsOrderIndependent() {
        let ascending: OffsetSelection = [.dayOf, .sevenDays]
        let descending: OffsetSelection = [.sevenDays, .dayOf]
        XCTAssertEqual(ascending, descending)
    }

    // MARK: - Inheritance and override (GROUP-04)

    func testAnEventWithNoOverrideInheritsItsGroupDefaults() {
        let event = makeEvent(date: annual(6, 1), groupDefaultOffsets: [.dayOf, .sevenDays], offsetOverride: nil)
        XCTAssertEqual(event.effectiveOffsets, [.dayOf, .sevenDays])
        XCTAssertTrue(event.inheritsGroupOffsets)
    }

    func testAnOverrideReplacesTheGroupDefaultEntirely() {
        let event = makeEvent(date: annual(6, 1), groupDefaultOffsets: [.dayOf, .sevenDays], offsetOverride: [.dayOf])
        XCTAssertEqual(event.effectiveOffsets, [.dayOf])
        XCTAssertFalse(event.inheritsGroupOffsets)
    }

    func testAnOverrideOnOneEventLeavesSiblingsInTheSameGroupUnchanged() {
        let groupDefault: OffsetSelection = [.dayOf, .threeDays, .sevenDays]
        let overridden = makeEvent(name: "Overridden", date: annual(6, 1), groupDefaultOffsets: groupDefault, offsetOverride: [.dayOf])
        let sibling = makeEvent(name: "Sibling", date: annual(6, 2), groupDefaultOffsets: groupDefault, offsetOverride: nil)

        XCTAssertEqual(overridden.effectiveOffsets, [.dayOf])
        XCTAssertEqual(sibling.effectiveOffsets, groupDefault)
    }

    func testAnEmptyOverrideIsDistinctFromNoOverride() {
        // "Notify me about nothing for this one person" has to be expressible, and must not
        // collapse into "inherit the group default".
        let silenced = makeEvent(date: annual(6, 1), groupDefaultOffsets: .all, offsetOverride: .empty)
        let inheriting = makeEvent(date: annual(6, 1), groupDefaultOffsets: .all, offsetOverride: nil)
        XCTAssertTrue(silenced.effectiveOffsets.isEmpty)
        XCTAssertEqual(inheriting.effectiveOffsets, .all)
    }

    // MARK: - Changing a group default (GROUP-05)

    func testChangingAGroupDefaultMovesEveryInheritingEventAndNoOverriddenOne() {
        let inheriting = makeEvent(name: "Inherits", date: annual(6, 1), groupDefaultOffsets: [.dayOf], offsetOverride: nil)
        let overridden = makeEvent(name: "Overrides", date: annual(6, 2), groupDefaultOffsets: [.dayOf], offsetOverride: [.sevenDays])

        // Simulate the group default changing, which is what the app does when it rewrites
        // snapshots after a group edit.
        let newDefault: OffsetSelection = [.dayOf, .threeDays, .sevenDays]
        let inheritingAfter = makeEvent(name: inheriting.name, date: inheriting.date, groupDefaultOffsets: newDefault, offsetOverride: inheriting.offsetOverride)
        let overriddenAfter = makeEvent(name: overridden.name, date: overridden.date, groupDefaultOffsets: newDefault, offsetOverride: overridden.offsetOverride)

        XCTAssertEqual(inheritingAfter.effectiveOffsets, newDefault)
        XCTAssertEqual(overriddenAfter.effectiveOffsets, [.sevenDays])
    }

    // MARK: - Group deletion (GROUP-02)

    func testAnEventReassignedToUngroupedStillResolvesToAValidOffsetSet() {
        let ungroupedDefaults = SeedGroups.definitions.first(where: \.isUngrouped)?.defaultOffsets ?? [.dayOf]
        let reassigned = makeEvent(
            date: annual(6, 1),
            groupName: SeedGroups.ungroupedName,
            groupDefaultOffsets: ungroupedDefaults,
            offsetOverride: nil
        )
        XCTAssertFalse(reassigned.effectiveOffsets.isEmpty)
        XCTAssertTrue(reassigned.effectiveOffsets.contains(.dayOf))
    }

    func testAnEventKeepsItsOwnOverrideWhenItsGroupIsDeleted() {
        // Deleting a group must not quietly widen or narrow the alerts a user set by hand.
        let override: OffsetSelection = [.dayOf, .sevenDays]
        let beforeDeletion = makeEvent(date: annual(6, 1), groupDefaultOffsets: [.dayOf], offsetOverride: override)
        let afterDeletion = makeEvent(
            date: beforeDeletion.date,
            groupName: SeedGroups.ungroupedName,
            groupDefaultOffsets: [.dayOf],
            offsetOverride: beforeDeletion.offsetOverride
        )
        XCTAssertEqual(afterDeletion.effectiveOffsets, override)
    }
}
