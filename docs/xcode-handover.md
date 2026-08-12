# Handover: picking this up in Xcode

You are inheriting Milestone 1 of the Dates PRD — phases 01 to 04 — built end to end on a
Linux container with no Xcode, no simulator, and no Apple SDKs. Read this before you build.

## The one thing that matters

**The domain layer is proven. The app layer has never been compiled.**

`DatesKit` is a Foundation-only Swift package holding every rule the app can be wrong about:
annual-date maths, leap-day resolution, the local-midnight rollover, age calculation, offset
inheritance, list ordering and search, and the entire notification plan. Its 70 tests were run
on Swift 6.1.2 for Linux and all pass.

`Dates/` — the SwiftUI views, SwiftData models, and the `UNUserNotificationCenter` wrapper —
was written against APIs that do not exist on Linux. Every file parses (`swiftc -frontend
-parse` is clean across all 23), but nothing was type-checked. Assume there are compile errors
and budget your first session for them. They should be shallow: wrong initialiser overloads,
concurrency diagnostics, macro expansion complaints. Nothing structural is expected.

Do not treat a compile error as evidence the design is wrong. Fix the call site.

## First moves

```sh
open Dates.xcodeproj          # iOS 17 target, iPhone only
# select any iPhone simulator, Cmd-B
```

Then, before touching anything else:

```sh
cd DatesKit && swift test     # must stay 70/70 green
```

If that suite breaks, you changed domain behaviour. Revert and reconsider — those tests encode
PRD requirements, not implementation details. See "Invariants" below.

Once the app builds:

```sh
xcodebuild test -project Dates.xcodeproj -scheme Dates \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

That runs `DatesTests/` — 15 tests covering DATA-02, DATA-05, GROUP-02, GROUP-05, NOTIF-01,
NOTIF-04, NOTIF-07. **They have never been executed.** Getting them green is the real
acceptance gate for this milestone, more than the build succeeding.

## Where I expect the compile errors

Ranked by how likely I think they are. These are the specific spots I could not verify.

1. **`EventGroup.events` relationship.** `Dates/Models/EventGroup.swift` declares
   `@Relationship(deleteRule: .nullify, inverse: \DateEvent.group) var events: [DateEvent]? = []`.
   Optional to-many with an explicit inverse is the CloudKit-compatible shape, but SwiftData is
   fussy here. If it complains, try a non-optional `[DateEvent]` first; only move the inverse
   to `DateEvent.group` if that fails, and if you do, re-check Phase 06's CloudKit constraints.

2. **`@ModelActor` on `EventSnapshotProvider`** in `Dates/Notifications/BackgroundRefresh.swift`.
   The macro should generate `init(modelContainer:)`. If it does not expand as expected, replace
   it with a plain actor that takes a `ModelContainer` and builds its own `ModelContext`.

3. **`Query(FetchDescriptor<DateEvent>(predicate:), animation:)`** in `EventDetailView.init`.
   I chose the descriptor overload deliberately over `Query(filter:)` because I was more
   confident it exists. If it is wrong, `@Query(filter: #Predicate<DateEvent> { $0.uuid == id })`
   is the alternative — but note you cannot capture an init parameter in a property wrapper
   default, which is why it is assigned in `init` at all.

4. **Concurrency diagnostics.** The project is Swift 5.9 language mode. `NotificationScheduler`
   is an actor holding `any NotificationCenterProtocol`, which is not `Sendable`. In 5.9 that is
   at most a warning. **If you raise the project to Swift 6 mode, expect real errors here** —
   and the retroactive `extension UNUserNotificationCenter: NotificationCenterProtocol` will want
   `@retroactive`. Do not raise the language mode as part of fixing the build; that is its own
   piece of work.

5. **`AppSettings` observation.** Its public properties are computed over private stored ones
   specifically to avoid `didSet` on `@Observable` storage, which is unreliable. If the Settings
   screen fails to react to a time change, this is the suspect — not the view.

## Runtime issues that will not show up as compile errors

- **Picker tag types.** `EventListView` tags with `UUID?.none` and `Optional(group.uuid)`
  against a `UUID?` selection; `EventFormView` does the same. If a picker renders with nothing
  selected, the tag type has drifted from the selection type. This fails silently.
- **Cold-launch notification taps.** `NotificationRouter.register()` is called from
  `DatesApp.init()`, before any scene connects, precisely so a tap that launches the app is not
  dropped. If you move it into a view's `.task`, cold-start deep links (NOTIF-10) will break
  intermittently and you will not notice in the simulator.
- **`DayTicker`.** Sleeps until one second past local midnight, then republishes `now`. Its
  `Task` may be suspended across backgrounding, which is why `RootView` also calls `refresh()`
  on `.active`. If an event dated today stops holding the top of the list overnight (LIST-03),
  look here.
- **AppIcon is an empty placeholder.** Expect a build warning. It blocks App Store submission
  but not TestFlight-internal or simulator runs. Phase 08 problem.

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

Two more that are structural rather than tested:

- **All writes go through `EventStore`.** That is the only reason NOTIF-07 holds — one place
  saves, one place reschedules, and the reschedule is awaited before the call returns. If you
  add a mutation path in a view, that guarantee is gone.
- **Views never do date maths.** They call `EventSnapshot` / `EventFormatting`. Anything a view
  computes about dates is a rule that escaped the tested layer.

## Manual acceptance, once it builds

The PRD's phase done-criteria, as a script. Simulator is fine except where noted.

**Phase 01/02.** Add a date with year unknown → no age shown anywhere. Add one with a year →
age appears on row and detail. Add 29 February with no year → detail shows 28 February in a
non-leap year. Kill and relaunch → everything still there. Create a group, put a date in it,
delete the group → the date survives in Ungrouped.

**Phase 03.** Add a date for today → it sits at the top. Change the device clock to tomorrow →
it moves to the bottom. Search by a partial name, with and without accents. Filter by group.

**Phase 04.** First save should trigger the permission prompt — not launch. Grant it, then open
Settings and check the queue read-out ("Scheduled *n* of 60"). Change the notification time and
confirm the read-out rebuilds. Edit a date's day and confirm nothing still fires on the old day
(the `DatesTests` NOTIF-07 tests cover this properly; the manual check is a sanity pass).
Deny permission on a fresh install and confirm the app is still fully usable.

**On device only:** actual notification delivery, and background refresh (NOTIF-06), which iOS
schedules at its own discretion and may never run when you want it to.

## What is deliberately absent

- **Phases 05 to 08.** No import, no export, no CloudKit, no appearance setting, no release
  work.
- **UI-01 to UI-03 are Phase 07,** so there is no Light/Dark setting yet and the app follows the
  system. The PRD wants Light as the first-launch default.
- **LIST-06 is partial.** The empty state shows all three entry routes, but Calendar and CSV
  import are disabled buttons. They are present so that screen does not need redesigning when
  Phase 05 lands.
- **PERF-01 and PERF-02 are unverified** — both are device measurements on an iPhone 12 or
  newer. The Linux timings in the test suite guard the algorithm, not the device figure.

## Groundwork already done for later phases

- **Phase 06 (CloudKit).** The schema is already CloudKit-shaped: every attribute has a default
  value, relationships are optional, and there are no unique constraints. Turning it on should
  be a `cloudKitDatabase:` argument in `DatesModelContainer.makeContainer` plus the capability,
  with no model migration. Keep it that way — adding a non-defaulted attribute now costs a
  migration later.
- **Phase 05 (import).** `AnnualDate.init?` already rejects impossible dates including 29
  February against a non-leap year, which is exactly the per-row rejection reason CSV import
  needs for IMP-06. Import should build snapshots and go through `EventStore`, not write to the
  context directly.

## Project mechanics

`project.yml` is the source of truth; `Dates.xcodeproj` is generated from it and committed so
the repo opens without tooling. The app target globs `Dates/`, so **adding a Swift file needs no
project change**. Regenerate only when targets, build settings, or Info.plist keys change:

```sh
brew install xcodegen && xcodegen generate
```

Signing is Automatic with no team set, so it opens without a paid account. The Apple Developer
Program membership is still unpurchased — a hard blocker for Phase 08 and for on-device
notification testing.

## Open with the user before going further

1. The seeded group defaults (only Close family gets all three offsets) are my judgement call
   from Job 2, not something the PRD specified. Worth confirming.
2. The 400-day scheduling window replaces the PRD's assumed 60 days. §9 explicitly said to tune
   it in Phase 04, and the reasoning is in `docs/verification.md`, but it is a visible change to
   a stated assumption.
3. The app is still named "Dates" with bundle id `com.cdtm88.Dates`. The PRD flags the name as
   needed before Phase 08 and ideally before the bundle id was set. Renaming is cheap now and
   expensive after the first TestFlight build.
