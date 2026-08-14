<p align="center">
  <img src="assets/lockups/lockup-horizontal-light.png#gh-light-mode-only" alt="Dates" width="320">
  <img src="assets/lockups/lockup-horizontal-dark.png#gh-dark-mode-only" alt="Dates" width="320">
</p>

<p align="center">Never miss a birthday, with enough warning to do something about it.</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2017%2B-000000?logo=apple&logoColor=white" alt="Platform: iOS 17+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
  <a href="https://github.com/cdtm88/dates/actions/workflows/ci.yml"><img src="https://github.com/cdtm88/dates/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/status-pre--release-orange" alt="Status: pre-release">
</p>

<!-- TODO: add two or three simulator screenshots here. This is the single biggest
     gap in the README; a date-tracking app is judged on whether the list looks good. -->

## Overview

Dates is an iPhone app for birthdays, anniversaries and the other annual dates that are
easy to forget. It shows what is coming up in one chronological list and sends reminders
early enough to be useful: a week ahead when you need to buy something, or just a nudge on
the morning itself when a message will do.

It runs entirely on your phone. There is no account, no backend and no analytics, and it
works with no connection at all. If you are signed in to iCloud your dates sync privately
across your own devices, and if you are not, everything simply stays local.

Built for personal use first, with an App Store release intended.

## Status

Pre-release. Every feature below is built and tested, but the app has not shipped: it is
not on the App Store or TestFlight, and device notification testing is still blocked on a
paid Apple Developer Program membership. Expect the data model to be stable and the release
plumbing to be absent.

Test coverage is real: 130 automated tests across the domain logic, the persistence and
scheduling layer, and the UI flows, all run on every pull request.

## Built with

Swift 5.9 and SwiftUI on iOS 17 or later, iPhone only. SwiftData for storage, CloudKit for
private sync, EventKit for calendar import, and UserNotifications for reminders. The Xcode
project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Features

- **One list, in the order things happen.** Upcoming dates first, with ages shown where the
  birth year is known, and passed dates rolling to the bottom for next year.
- **Reminders that match how much notice you need.** Seven days, three days, on the day, or
  any combination, set per date or inherited from its group.
- **Groups with sensible defaults.** Close family gets the full run of advance warnings;
  wider circles get a single day-of nudge, so the alerts stay worth reading.
- **A queue that does not run dry.** Reminders are topped up on launch and in the
  background, covering more than a year ahead within iOS's scheduling limits.
- **Bring your dates with you.** Import from the iOS Birthdays calendar or a CSV, with a
  review screen showing what will be added, what is a duplicate and what could not be read.
  Nothing is saved until you approve it. Export back to CSV at any time.
- **Fully offline, optionally synced.** No account required. iCloud sync is private and
  automatic when you have an account, and invisible when you do not.
- **Light and dark**, following the system or pinned to either.

## Building

Requires Xcode 15 or newer.

```sh
git clone https://github.com/cdtm88/dates.git
cd dates
open Dates.xcodeproj
```

Pick an iPhone simulator and run. Signing is set to Automatic with no team, so the project
opens without a paid account; set your own team under Signing and Capabilities to run on a
physical device.

The Xcode project is generated, so adding a source file means running `xcodegen generate`
and committing the result. CI fails the build if the two fall out of sync. Read
[`docs/xcode-handover.md`](docs/xcode-handover.md) before making changes.

## Tests

The domain logic runs on any Swift toolchain, no Xcode needed:

```sh
cd DatesKit && swift test
```

The persistence, scheduling and UI suites need a simulator:

```sh
xcodebuild test -project Dates.xcodeproj -scheme Dates \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Documentation

- [`docs/xcode-handover.md`](docs/xcode-handover.md) for working on the project
- [`docs/verification.md`](docs/verification.md) for requirement-by-requirement status and
  the reasoning behind the notable design calls

## Contributing

A personal project, so issues and pull requests are not being actively taken. You are
welcome to fork it.

<!-- TODO: no LICENSE file exists, which makes this all-rights-reserved by default and
     means nobody can legally reuse it. Add one and replace this comment with a
     License section. MIT is the usual choice if you do not mind. -->
