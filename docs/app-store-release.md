# App Store release checklist

What the code can't do. Everything in the repo is ready to archive: an opaque 1024 icon,
6.9" screenshots in `assets/screenshots/app-store/`, a privacy manifest, matching
app and widget versions, and Debug-only test hooks.

## Account and signing

- [ ] Join the Apple Developer Program. Personal teams can't provision iCloud or push, so
      the Release config can't be signed until then.
- [ ] Register App IDs `com.moorelabs.Dates` (iCloud/CloudKit, Push Notifications,
      App Groups) and `com.moorelabs.Dates.DatesWidget` (App Groups), the app group
      `group.com.moorelabs.Dates` and the container `iCloud.com.moorelabs.Dates`.
      Automatic signing does most of this once you're a member.
- [ ] After archiving, check that the exported entitlements say `aps-environment = production`:
      `codesign -d --entitlements :- Payload/Dates.app`. The committed file says
      `development`, and App Store export normally rewrites it.

## CloudKit

- [ ] Run a Release build on a device once so the schema is created in Development.
- [ ] In the CloudKit Console, **Deploy Schema Changes** to Production. Skip this and sync
      silently does nothing for App Store users.

## App Store Connect

- [ ] Privacy policy URL: `docs/privacy.md`, served at https://cdtm88.github.io/dates/privacy once GitHub Pages is on (main, /docs). This is required even though nothing is collected. It should
      cover reading contacts on the device, syncing through the user's own iCloud
      private database, and having no analytics.
- [ ] Support URL.
- [ ] App Privacy: **Data Not Collected**.
- [ ] Age rating questionnaire: all "None", which gives 4+.
- [ ] Listing:
  - Name: check that "Dates" is available.
  - Subtitle, description and keywords: `docs/app-store-listing.md`.
  - Category: Productivity or Lifestyle.
  - Copyright.
- [ ] Screenshots: upload `assets/screenshots/app-store/*-6.9in.png` (1320×2868, in
      order). To regenerate, capture the screens named in `Tools/compose_screenshots.py`
      and run it.
- [ ] Export compliance is already answered by `ITSAppUsesNonExemptEncryption = false`.
- [ ] Review notes: no login, contacts import is optional, and iCloud sync is automatic.

## Before submitting

- [ ] Bump `CURRENT_PROJECT_VERSION` for **both** targets in `project.yml` on every upload.
- [ ] Ship one internal TestFlight build first, and on a real device check:
  - notifications fire
  - background refresh tops up the queue
  - sync works between two devices against Production
  - the widget appears on the home screen and the lock screen
