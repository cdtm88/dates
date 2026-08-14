# Handover: picking this up in Xcode

You are inheriting phases 01 to 05 of the Dates PRD. Phases 01 to 04 (Milestone 1) were
built first; Phase 05 — calendar and CSV import/export — landed after, developed in Xcode
with all suites run on a simulator. Some counts below predate Phase 05; the README has the
current ones.

## Status

Milestone 1 was written on a Linux container with no Xcode and no Apple SDKs, so for a while
the app layer was unverified. **That is no longer true.** CI now builds the app on a macOS
runner and runs the full test suite on a simulator:

- `DatesKit` — 70 tests, run on Linux in a Swift container. Green.
- `Dates/` + `DatesTests/` — builds under Xcode, and 20 tests pass on an iPhone simulator.
- `DatesUITests/` — 5 XCUITest smoke tests drive the built app in the simulator: the empty
  state, event creation end-to-end (including the notification permission prompt), 29
  February handling in the form, and the Settings queue read-out. The app launches with
  `--uitest`, which swaps in an empty in-memory store so every run starts clean.

All of it runs on every pull request via `.github/workflows/ci.yml`. So the codebase
compiles, its behavioural tests pass, and the core interaction flows are exercised against
the real UI; what remains unverified by automation is visual quality — layout, spacing, and
Dynamic Type still need eyes on a simulator or device.

This document was originally a list of predicted compile errors. Every one of them turned out
to be fine — the optional to-many `@Relationship` with an explicit inverse, the `@ModelActor`
macro, and the `Query(FetchDescriptor:animation:)` overload all worked as written. What
follows is what is actually still worth knowing.

## Where the logic lives, and why

`DatesKit` is a Foundation-only package holding every rule the app can be wrong about: annual
date maths, leap-day resolution, the local-midnight rollover, age calculation, offset
inheritance, list ordering and search, and the entire notification plan. It has no dependency
on SwiftUI, SwiftData or UserNotifications, which is why it tests in under a second on any
machine.

The app layer is deliberately thin: SwiftData models storing discrete date components, an
`EventStore` that funnels every mutation through one place, an actor wrapping
`UNUserNotificationCenter`, and the SwiftUI screens. Keep it that way. Anything a view computes
about dates is a rule that escaped the tested layer.

## Running it

```sh
open Dates.xcodeproj          # iOS 17 target, iPhone only
cd DatesKit && swift test     # domain suite, no Xcode needed

xcodebuild test -project Dates.xcodeproj -scheme Dates \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Signing is Automatic with no team set, so it opens without a paid account. The Apple Developer
Program membership is still unpurchased — a hard blocker for Phase 08 and for on-device
notification testing.

## Things that will not show up as a failing build

- **Picker tag types.** `EventListView` tags with `UUID?.none` and `Optional(group.uuid)`
  against a `UUID?` selection; `EventFormView` does the same. If a picker renders with nothing
  selected, the tag type has drifted from the selection type. This fails *silently* — no
  warning, no crash.
- **Cold-launch notification taps.** `NotificationRouter.register()` is called from
  `DatesApp.init()`, before any scene connects, so that a tap which launches the app is not
  dropped. Moving it into a view's `.task` breaks cold-start deep links (NOTIF-10)
  intermittently, and you will not notice in the simulator.
- **`DayTicker`.** Sleeps until one second past local midnight, then republishes `now`. Its
  `Task` may be suspended across backgrounding, which is why `RootView` also calls `refresh()`
  on `.active`. If an event dated today stops holding the top of the list overnight (LIST-03),
  look here.
- **`AppSettings` observation.** Its public properties are computed over private stored ones
  specifically to avoid `didSet` on `@Observable` storage, which is unreliable. If the Settings
  screen stops reacting to a time change, this is the suspect — not the view.
- **A benign CoreData log line.** On a fresh install the test host logs
  `addPersistentStore … Failed to create file; code = 2` followed by
  `Recovery attempt … was successful!`. The parent directory does not exist yet and CoreData
  creates it. It is noise, not a bug — do not chase it.
- **AppIcon is an empty placeholder.** Expect a build warning. It blocks App Store submission
  but not TestFlight or simulator runs. Phase 08 problem.

## Invariants — do not "fix" these

Each is a decision with a test behind it. Changing the behaviour means changing the test, which
means you are changing the product. `docs/verification.md` has the full reasoning.

| Behaviour | Test that enforces it |
|---|---|
| The queue fills by **event**, not by fire date — nearest events get all their offsets or none | `testNoEventIsEverPartiallyScheduled` |
| 29 February resolves to **28 February**, never 1 March | `test29FebruaryNormalisesBackwardsNotForwards` |
| An event dated today stays at position 1 until local midnight | `testAnEventDatedTodaySortsFirstAndStaysThereAllDay` |
| `offsetOverride == nil` (inherit) is **not** the same as `== []` (never notify) | `testAnEmptyOverrideIsDistinctFromNoOverride` |
| Pending app-owned requests never exceed 60 | `testTheCeilingIsNeverExceededAtFiveHundredEvents` |
| Cancellation matches on the `evt-{uuid}-` prefix, never on an enumerated offset list | `testEveryIdentifierForAnEventSharesItsCancellationPrefix` |
| The scheduler never removes a request it did not schedule | `testTheSchedulerNeverTouchesRequestsItDoesNotOwn` |

One more that is structural rather than tested: **all writes go through `EventStore`.** That is
the only reason NOTIF-07 holds — one place saves, one place reschedules, and the reschedule is
awaited before the call returns. Add a mutation path in a view and that guarantee is gone.

## Do not raise the Swift language mode as part of other work

The project is Swift 5.9 mode. `NotificationScheduler` is an actor holding a non-`Sendable`
`any NotificationCenterProtocol`, and `extension UNUserNotificationCenter:
NotificationCenterProtocol` is a retroactive conformance. Both are fine in 5.9 and both become
real errors in Swift 6, where the conformance also wants `@retroactive`. Moving to Swift 6 is
its own piece of work with its own PR.

## Manual acceptance — the part CI cannot do

The behaviour is tested. The interface is not. Run this on a simulator:

**Phase 01/02.** Add a date with year unknown → no age anywhere. Add one with a year → age on
row and detail. Add 29 February with no year → detail shows 28 February in a non-leap year.
Kill and relaunch → everything still there. Create a group, put a date in it, delete the group
→ the date survives in Ungrouped.

**Phase 03.** Add a date for today → it sits at the top. Advance the device clock past midnight
→ it moves to the bottom. Search a partial name, with and without accents. Filter by group.
Check Dynamic Type at XXXL while you are here, even though that is Phase 07 — it is cheaper to
find layout breaks now.

**Phase 04.** First save should trigger the permission prompt, not launch. Grant it, open
Settings, check the Reminder time footer says how many dates are scheduled and through when.
Change the notification time and confirm the footer rebuilds. Deny permission on a fresh install and confirm the app is still
fully usable.

**On device only:** actual notification delivery, and background refresh (NOTIF-06), which iOS
schedules at its own discretion and may never run when you want it to.

## What is deliberately absent

- **Phases 06 to 08.** No CloudKit, no appearance setting, no release work.
- **UI-01 to UI-03 are Phase 07,** so there is no Light/Dark setting and the app follows the
  system. The PRD wants Light as the first-launch default.
- **PERF-01 and PERF-02 are unverified** — device measurements on an iPhone 12 or newer. The
  timings in the test suites guard the algorithm, not the device figure.

## Groundwork already in place

- **Phase 06 (CloudKit).** The schema is already CloudKit-shaped: every attribute has a default,
  relationships are optional, no unique constraints. Turning it on should be a `cloudKitDatabase:`
  argument in `DatesModelContainer.makeContainer` plus the capability, with no migration. Keep it
  that way — adding a non-defaulted attribute now costs a migration later.
- **Phase 05 (import) is built.** CSV and Calendar import both stage through
  `ImportReviewView` and land via `EventStore.importEvents` — one save, one reschedule,
  duplicates screened twice (review and store). The CSV schema lives in
  `DatesKit/EventImport.swift`, the EventKit mapping in `Dates/Import/CalendarImporter.swift`,
  export in Settings. Manual acceptance: import a CSV with a bad row and check the reason
  shows with its line number; import it twice and check the second pass adds nothing.

## Project mechanics

`project.yml` is the source of truth; `Dates.xcodeproj` is generated from it and committed so
the repo opens without tooling.

The app target globs `Dates/`, but **XcodeGen resolves those globs when it runs**, writing
explicit file references into the pbxproj. So adding a Swift file *does* require regenerating
and committing the project. This is easy to miss, because a file added through Xcode's own UI
builds fine on your machine and is simply absent for everyone else:

```sh
brew install xcodegen && xcodegen generate
```

CI catches it — `Tools/check_project_sync.py` fails if a source on disk is not referenced by the
committed project, or if the project references a file that no longer exists. Run it locally
with `python3 Tools/check_project_sync.py`.

## Open with the user before going further

1. The seeded group defaults (only Close family gets all three offsets) are a judgement call
   from Job 2, not something the PRD specified.
2. The 400-day scheduling window replaces the PRD's assumed 60 days. §9 explicitly said to tune
   it in Phase 04, and the reasoning is in `docs/verification.md`, but it is a visible change to
   a stated assumption.
3. The app is still named "Dates" with bundle id `com.cdtm88.Dates`. The PRD flags the name as
   needed before Phase 08 and ideally before the bundle id was set. Renaming is cheap now and
   expensive after the first TestFlight build.
