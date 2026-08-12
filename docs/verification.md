# Requirement verification — Milestone 1 (phases 01 to 04)

Three levels of evidence appear below.

- **Tested (Linux)** — a test in `DatesKit/Tests/` asserts it, and that test has been run and
  passes.
- **Tested (Xcode)** — a test in `DatesTests/` asserts it. These have been written but never
  executed, because they need SwiftData or UserNotifications.
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
| LIST-06 | Partial | `EmptyStateView` offers all three routes. Add-manually works; the two import routes are visible but disabled until Phase 05 |
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

### 5. 29 February resolves by clamping

Rather than special-casing the leap day, `resolvedDay(inYear:)` clamps the stored day to the
length of that month. For 29 February that produces 28 February, which is what §9 specifies,
and it is correct for every other month without a second code path.

## Known gaps in this milestone

- **UI-01 to UI-03 are Phase 07.** There is no appearance setting yet, so the app follows the
  system. The PRD wants Light as the first-launch default; that lands with the rest of Phase 07.
- **LIST-06 is partially satisfied.** Two of the three entry routes are disabled placeholders
  until Phase 05.
- **PERF-01 and PERF-02 are unverified.** Both are device measurements.
- **The `DatesTests` suite has never run.** It needs Xcode. Treat a first green run there as
  part of accepting this milestone.
- **The app layer has never been compiled.** Only the domain package has. Small compile
  errors on the first Xcode build are likely and expected.
