# Requirement verification — phases 01 to 05

Three levels of evidence appear below. Both test suites run on every pull request:
`DatesKit` on a Linux container, `DatesTests` on a macOS runner against an iPhone simulator.

- **Tested (Linux)** — a test in `DatesKit/Tests/` asserts it, and that test has been run and
  passes.
- **Tested (Xcode)** — a test in `DatesTests/` asserts it. These need SwiftData or
  UserNotifications, and run on a macOS CI runner against an iPhone simulator.
- **Implemented** — code exists and was reviewed, but nothing automated asserts it. Mostly UI,
  which needs a device or simulator to judge.

## Phase 01 — data model

| ID | Status | Where |
|---|---|---|
| DATA-01 | Tested (Linux) | `AnnualDate.init?`, `EventValidation`; `AnnualDateTests.testRejectsImpossibleComponents`, `testNameValidationEnforces…` |
| DATA-02 | Tested (Xcode) | `PersistenceTests.testAnEventSurvivesClosingAndReopeningTheStore`, `testAnEditAndADeleteBothSurviveAReopen` — a real on-disk store, closed and reopened |
| DATA-03 | Tested (Linux) | `AnnualDate.yearsElapsedAtNextOccurrence`; five tests including age-zero and the nil-when-unknown case |
| DATA-04 | Tested (Linux) | `AnnualDate.resolvedDay`; `test29FebruaryResolvesTo28FebruaryInANonLeapYear` and `…NormalisesBackwardsNotForwards`, which also asserts it is *not* 1 March |
| DATA-05 | Tested (Xcode) | `PersistenceTests.testFiveHundredEventsInsertAndQueryWithoutError` |
| OFF-01 | Implemented | No network code exists anywhere in the target. Nothing to disable |

## Phase 02 — groups and offsets

| ID | Status | Where |
|---|---|---|
| GROUP-01 | Tested (Linux + Xcode) | `SeedGroups`; `OffsetResolutionTests`, plus `PersistenceTests.testSeedingCreatesFiveGroupsAndIsIdempotent` and `…RecreatesUngroupedIfItIsMissing` |
| GROUP-02 | Tested (Xcode) | `EventStore.deleteGroup`; `PersistenceTests.testDeletingAGroupMovesItsEventsToUngrouped…`, `testUngroupedCannotBeDeleted` |
| GROUP-03 | Tested (Linux) | `OffsetSelection` bitmask; round-trip and order-independence tests |
| GROUP-04 | Tested (Linux) | `OffsetResolver.effectiveOffsets`; four tests, including that an override on one event leaves its siblings alone |
| GROUP-05 | Tested (Xcode) | `EventStore.updateGroup` reschedules when the offsets changed; `SchedulerTests.testChangingAGroupDefaultReschedulesItsInheritingEvents` |

## Phase 03 — list and detail

| ID | Status | Where |
|---|---|---|
| LIST-01 | Tested (Linux) | `EventOrdering.sortedByNextOccurrence`; `testEventsSortAscendingByDaysUntilNextOccurrence` |
| LIST-02 | Implemented | `EventRowView` renders name, date, days-until, group, and the years badge |
| LIST-03 | Tested (Linux) | `testAnEventDatedTodaySortsFirstAndStaysThereAllDay` (00:00, 09:30, 18:30, 23:30) and `testAPassedEventMovesToItsNextYearPosition…`. `DayTicker` triggers the redraw at the local-midnight boundary in the running app |
| LIST-04 | Tested (Linux) | `EventOrdering.filteredAndSorted`; case- and diacritic-insensitive search, group filter, and a 500-event timing assertion |
| LIST-05 | Implemented | `EventDetailView` shows every stored field plus the effective offsets and whether they are inherited |
| LIST-06 | Implemented | `EmptyStateView` offers all three routes, all live since Phase 05; `testFirstLaunchShowsTheEmptyState` asserts the buttons are enabled |
| PERF-01 | Not verified | Needs an iPhone 12 or newer |
| PERF-02 | Not verified | Needs a device. Formatters are cached and rows do no date maths beyond the snapshot, which is the part under our control |
| SCALE-01 | Tested (Linux) | Sorting and searching 500 events measured well under budget; note these are Linux numbers, so they guard the algorithm, not the device figure |

## Phase 04 — notification engine

| ID | Status | Where |
|---|---|---|
| NOTIF-01 | Tested (Xcode) | `EventStore.requestAuthorisationOnFirstSave`; `SchedulerTests.testAuthorisationIsRequestedOnceOnTheFirstSaveNotAtLaunch` and `testDenialLeavesTheAppFullyUsableAndSchedulesNothing` |
| NOTIF-02 | Tested (Linux) | `NotificationPlannerTests.testEachEnabledOffsetProducesAFireDateAtTheConfiguredTime` |
| NOTIF-03 | Tested (Linux) | Same test asserts the exact 3-day and 7-day fire dates |
| NOTIF-04 | Tested (Linux + Xcode) | `testTheCeilingIsNeverExceededAtFiveHundredEvents`; `SchedulerTests.testThePendingQueueNeverExceedsSixtyAtFiveHundredEvents` |
| NOTIF-05 | Tested (Linux) | `RootView` reschedules on `.active`; ordering asserted by `testNotificationsAreReturnedSoonestFirst` and `testTheSoonestTwentyEventsEachGetAllOfTheirConfiguredOffsets` |
| NOTIF-06 | Implemented | `BackgroundRefresh` plus `.backgroundTask(.appRefresh(…))` and the Info.plist identifier. Cannot be tested off-device; iOS decides when it runs |
| NOTIF-07 | Tested (Xcode) | `SchedulerTests.testEditingAnEventsDateLeavesNoStaleRequestsForIt`, `testRemovingAnOffsetCancelsItsRequest`, `testDeletingAnEventRemovesEveryRequestItOwned` |
| NOTIF-08 | Tested (Linux) | `NotificationContentBuilder`; body copy asserted for every type, with and without a known year |
| NOTIF-09 | Tested (Linux) | `testChangingTheGlobalNotificationTimeMovesEveryFireDate`; `SettingsView` reschedules on change |
| NOTIF-10 | Implemented | `NotificationRouter` parses the identifier and pushes the detail view. Nothing else happens on tap |
| PERF-03 | Tested (Linux) | Planning 500 events measured under budget, and the scheduler is an actor so the work is off the main thread |

## Phase 05 — import and export

The PRD's IMP requirements are stated by behaviour here; IMP-06 (a per-row rejection reason)
is the one referenced by id in the handover notes.

| Behaviour | Status | Where |
|---|---|---|
| CSV parsing survives what spreadsheets produce: quoted commas and newlines, doubled quotes, CRLF, a UTF-8 BOM | Tested (Linux) | `CSVTable`; `CSVTableTests` |
| Every unreadable CSV row is refused with its line number and a displayable reason (IMP-06), without blocking the readable rows | Tested (Linux) | `EventCSV.decode`; `testEachBadRowIsRejectedWithItsLineNumberAndReasonWhileGoodRowsSurvive` |
| A candidate matching an existing event by name (case- and diacritic-insensitive) and day is a duplicate and is skipped | Tested (Linux + Xcode) | `ImportScreening`; `testReimportingTheSameBatchAddsNothing` |
| A batch import is one save, one reschedule, one permission prompt — never one per row | Tested (Xcode) | `EventStore.importEvents`; `ImportTests` |
| A row naming an existing group joins it; an unknown name falls back rather than creating a group | Tested (Xcode) | `testACandidateNamingAnExistingGroupJoinsItAndTheRestUseTheFallback` |
| An exported file re-imports as pure duplicates | Tested (Linux + Xcode) | `testExportedEventsReimportAsPureDuplicates`, and again through a real store in `ImportTests` |
| Calendar import offers only Birthdays-calendar entries and yearly-recurring events | Implemented | `CalendarImporter` — EventKit cannot run in a unit test; needs a simulator with calendar data |
| Nothing is saved before the user reviews what will be added, skipped and refused | Implemented | `ImportReviewView` |

## Judgement calls

The PRD left these open. Each is a decision, not an oversight — change any of them and the
tests asserting them will tell you what else moves.

### 1. The queue fills by event, not by fire date

NOTIF-05 says "prioritising soonest-firing notifications first". Read literally — sort all
candidate notifications by fire date and take the first 60 — the queue can end mid-event: a
7-day gift warning is scheduled but the day-of reminder that follows it does not fit. That is
the one outcome worse than no advance warning, because it actively misleads.

So the planner takes *events* in order of next occurrence and adds each one's full set of
schedulable offsets, stopping at the first event that does not fit whole. The nearest events
are completely covered, which is what the Phase 04 done-criterion asks for ("the soonest 20
events each have all their configured offsets scheduled"). The cost is at most two unused
slots out of 60. Asserted by `testNoEventIsEverPartiallyScheduled`.

### 2. The window is 400 days, not 60

PRD §9 assumed "roughly the next 60 days … tuned during Phase 04 against the 60-request
ceiling". Tuning it upward: at 500 events the ceiling binds after about two weeks, so the
window is irrelevant there. At 20 events or fewer, 60 requests covers *every* event's every
offset for a full year — and the §8 risk is precisely that the queue drains while the app goes
unopened. A short window would throw that coverage away for no benefit. Asserted by
`testASmallDatasetIsCoveredMoreThanAYearAhead`.

### 3. Seeded groups do not all get the same defaults

The PRD names the four groups but not their offsets. Close family gets 7-day, 3-day and
day-of; Wider family gets 7-day and day-of; Friends and Work get day-of only. Job 2 states
that advance alerts must stay meaningful "rather than becoming noise", and defaulting every
group to all three would produce exactly the noise it warns about. It also triples queue
pressure for no user benefit. All of them are editable in the app.

### 4. An empty override is not the same as no override

`offsetOverride == nil` means "inherit the group default". `offsetOverride == []` means "never
notify me about this one". Collapsing them would make "silence this person" unexpressible.
Asserted by `testAnEmptyOverrideIsDistinctFromNoOverride`.

The form does not expose this distinction as a toggle. It always shows the three alert
switches, seeded from the group default; on save, a selection equal to the group default is
stored as inherit (so a later change to the group still flows through, GROUP-05) and anything
else — including all three off — becomes the override.

### 5. Import never creates groups, and calendar import never guesses a year

A CSV `Group` value that matches no existing group falls back to a group chosen on the
review screen, rather than silently creating one — a typo in a 200-row file should not
produce a "Close famly" group. And a calendar occurrence's year says when the event next
happens, not when the person was born, so calendar candidates always arrive year-unknown; a
wrong age on every imported birthday would be worse than none. Both are editable after
import like any hand-entered date.

### 6. Duplicates cannot be force-imported

The review screen shows duplicates but does not let them be selected, and
`EventStore.importEvents` screens them again. Collapsing "import this file twice" into a
no-op is the entire defence against doubling the list, so there is deliberately no
override. Someone who genuinely has two people with the same name sharing a birthday can
add the second by hand.

### 7. 29 February resolves by clamping

Rather than special-casing the leap day, `resolvedDay(inYear:)` clamps the stored day to the
length of that month. For 29 February that produces 28 February, which is what §9 specifies,
and it is correct for every other month without a second code path.

## Known gaps

- **UI-01 to UI-03 are Phase 07.** There is no appearance setting yet, so the app follows the
  system. The PRD wants Light as the first-launch default; that lands with the rest of Phase 07.
- **PERF-01 and PERF-02 are unverified.** Both are device measurements.
- **The calendar import path is untested by automation.** EventKit needs a device or
  simulator with calendar data and a granted permission; the mapping rules it feeds
  (`ImportCandidate`, screening, the store path) are all tested.
- **The interface itself is unreviewed.** Behaviour is tested and the app builds, but no one
  has looked at a running screen. Layout, spacing, and Dynamic Type behaviour are unverified.
