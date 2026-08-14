# Dates

Birthday, anniversary and key-date reminders for iOS. Native, offline-first, no backend.

This repository implements **phases 01 to 07 of the PRD**: the data model, groups and
offsets, the chronological list and detail views, the rolling-window notification engine
(Milestone 1, the first TestFlight-worthy build), calendar and CSV import/export (Phase 05),
private-database iCloud sync of the SwiftData store (Phase 06), and the Light/Dark
appearance setting with Light as the first-launch default (Phase 07).

## Layout

```
DatesKit/            Foundation-only Swift package. Every rule the app can get wrong.
  Sources/DatesKit/  AnnualDate, offsets, ordering, notification planner.
  Tests/             70 tests, runnable on any Swift toolchain — no Xcode needed.
Dates/               The iOS app: SwiftData models, notification scheduler, SwiftUI views.
DatesTests/          Tests that need SwiftData or UserNotifications. Xcode only.
DatesUITests/        XCUITest smoke of the acceptance flows, driving the real app.
project.yml          XcodeGen spec — the source of truth for the project.
Dates.xcodeproj/     Generated from project.yml and committed so the repo opens directly.
docs/verification.md   Requirement-by-requirement status.
docs/xcode-handover.md Read this first if you are picking the work up in Xcode.
```

### Why the split

`DatesKit` depends on Foundation and nothing else. Leap-day resolution, the day-rollover
boundary, age calculation, offset inheritance, list ordering, and the whole notification plan
live there as value types, so they are tested directly rather than through a simulator. The
SwiftUI and SwiftData layer stays thin: it stores components, maps models to snapshots, and
hands the resulting plan to `UNUserNotificationCenter`.

That split is also what made it possible to develop this on a machine without Xcode. CI now
covers both halves: the domain suite runs on Linux in a Swift container, and a macOS runner
builds the app and runs the simulator tests. See
[`docs/xcode-handover.md`](docs/xcode-handover.md) before making changes.

## Building

Requires Xcode 15 or newer (iOS 17 deployment target, D-01).

```sh
open Dates.xcodeproj      # then select an iPhone simulator and run
```

To regenerate the project after adding files — [XcodeGen](https://github.com/yonaskolb/XcodeGen),
`brew install xcodegen`:

```sh
xcodegen generate
```

The target globs `Dates/`, but XcodeGen resolves those globs when it runs — so **adding a
Swift file does require regenerating and committing the project**, as well as any change to
targets, settings, or Info.plist keys. CI enforces this: `Tools/check_project_sync.py` fails
the build if a source on disk is not referenced by `Dates.xcodeproj`.

### Signing

`CODE_SIGN_STYLE` is Automatic with no team set, so the project opens without a paid account.
Set your team in *Signing & Capabilities* to run on a physical device. The Apple Developer
Program membership is still a hard blocker for Phase 08 and for testing notifications on
device; the simulator covers most of Phase 04.

## Tests

The domain suite, with no Xcode involved:

```sh
cd DatesKit && swift test
```

The SwiftData and scheduler suite, which needs Xcode:

```sh
xcodebuild test -project Dates.xcodeproj -scheme Dates \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

Current state: **95 of 95 DatesKit tests pass, 30 of 30 DatesTests and 5 of 5
DatesUITests pass on an iPhone simulator.** All suites run on every pull request. The UI
suite launches the real app with `--uitest` (an empty in-memory store) and drives the
acceptance flows: first launch, creating a date, 29 February handling, and the reminder
queue read-out in Settings.

## Decisions worth knowing

Beyond the PRD's locked decisions, three judgement calls were made where the PRD left room.
All three are described with their reasoning in `docs/verification.md`:

- **The scheduler fills by event, not by fire date.** The nearest events get *all* of their
  offsets or none. Filling strictly by fire date would let the queue end on a 7-day gift
  warning whose day-of reminder did not fit, which is worse than no warning at all.
- **The rolling window is 400 days, not the 60 the PRD assumed.** The 60-request ceiling is
  the binding constraint for a large dataset, so a long window costs nothing there — and for
  a small dataset it means the queue covers everything for over a year, which is the real
  defence against the queue draining while the app goes unopened.
- **Seeded groups get different default offsets.** Only Close family gets the full 7/3/day-of
  set. The PRD's Job 2 is explicit that advance alerts must stay meaningful rather than
  becoming noise, and every group defaulting to all three would do the opposite.

## Import and export (Phase 05)

Both import routes go through one review screen: nothing is saved until the user has seen
what will be added, what already exists (skipped as duplicates), and — for CSV — which rows
could not be read, each with its line number and reason (IMP-06). Batch import is a single
save and a single notification reschedule, and re-importing the same file adds nothing.

- **CSV.** Header `Name,Type,Month,Day,Year,Group`, columns matched by name in any order;
  `Year` and `Group` optional. Rows naming an existing group join it (case-insensitively);
  unknown names fall back to a group picked at review time rather than silently creating
  groups. Export writes the same schema from Settings, so an exported file re-imports as
  pure duplicates.
- **Calendar.** Reads only the system Birthdays calendar and events with a yearly
  recurrence rule — meetings are not annual dates. Years are left unknown: an occurrence's
  year is not a birth year, and a wrong age is worse than none. Requires the iOS 17
  full-access calendar permission (EventKit has no read-only tier).

## iCloud sync (Phase 06)

The SwiftData store is CloudKit-backed (`.private("iCloud.com.cdtm88.Dates")`). The schema
was kept CloudKit-shaped from Phase 01 — defaults on every attribute, optional
relationships — so this was the entitlement plus one flag, with no migration. Without an
iCloud account everything stays local and the app is unaffected; Settings shows which of
the two states applies. The CloudKit attempt is gated on the account token: a
CloudKit-backed container init traps — it does not throw — in a process without the
iCloud entitlement, which is what an unsigned CI build is, and a process with no account
has nothing to sync anyway. Tests and `--uitest` opt out of CloudKit entirely.

What automation cannot verify: actual multi-device convergence, which needs two signed-in
devices.

## Not yet built

Phase 08 (release readiness) is untouched, and the app is still named "Dates" with bundle
id `com.cdtm88.Dates` — the PRD flags the name as needed before Phase 08.
