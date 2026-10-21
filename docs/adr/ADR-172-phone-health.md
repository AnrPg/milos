# ADR-172: Phone health data (Apple Health and Health Connect)
Date: 2026-10-21
Status: Accepted

## Context
Plan P3-M10 (`docs/plans/redesign-phase-3-depth.md`, ADR candidate «ADR-172 Phone
health data»): the store apps from ADR-171 should bring in workouts, sleep, weight,
resting heart rate and steps from the phone's own health store, with a permissions
flow on «Εγώ › Συνδεδεμένες συσκευές», ingest, dedupe and a status row. ADR-171 left
the phone row as «Σύντομα» until a `MilosHealth` plugin is present; its capability
layer (`apps/web/src/lib/platform`) turns `healthKit` / `healthConnect` on when it is.

Garmin (ADR-161) already set the pattern: `device_connections`, `device_imports`
(dedupe on user, provider, kind and provider id), `device_activities`,
`daily_stats`, activity matching, «manual entry wins» for sleep and weight, imported
workouts private by default, and the ADR-158 health-data consent before any health
data is stored. Phase 2 D8/D11 require consent, delete and export for health data.

Unlike Garmin there is no server-to-server API: HealthKit and Health Connect can only
be read on the phone, by the app, while it runs.

## Decision
1. **One native plugin, `MilosHealth`, written in the app** (no third-party health
   plugin): Swift HealthKit (`ios/App/App/MilosHealthPlugin.swift`, registered by
   `MilosBridgeViewController`) and Kotlin Health Connect
   (`android/.../MilosHealthPlugin.kt`, registered in `MainActivity`), with the same
   read-only surface: `availability()`, `requestAuthorization({kinds})`,
   `read({kinds, from, to})`, plus `openInstaller()` on Android.
2. **The plugin returns raw records; one pure TS module shapes them**
   (`lib/platform/health-batch.ts`): instants get the wearer's offset back, sleep
   segments or sessions become one main sleep per local wake day, a day's resting
   HR and steps travel together, lists are cut at 500 records.
3. **Phone rows reuse `device_connections`** (providers `apple_health`,
   `health_connect`, no tokens) and the Garmin import pipeline, made
   provider-neutral: `ImportDeviceSummaries.import_batches/4` runs the same
   per-record dedupe, policies and journal effects for any provider through
   `SummaryReader` (Garmin summaries or `PhoneHealthSample`).
4. **API** under the member's own session, in the existing `/api/me` devices scope:
   `POST /devices/phone/:provider/connect`, `PATCH /devices/phone/:provider`,
   `POST /devices/phone/:provider/ingest`, `DELETE /devices/phone/:provider?delete_data=`,
   and `GET /devices/export` for every device's data.
5. **Sync runs in the foreground only**: right after connecting (last 30 days), on
   app start and on each resume (at most every 15 minutes), and from «Συγχρονισμός
   τώρα». The server owns the read window (`connection.read_from`).
6. **UI**: inside the app the phone's own row replaces «Σύντομα» with «Σύνδεση» (or
   why it can't: no health store, Health Connect missing or outdated with
   «Εγκατάσταση»); connected, it shows the last sync, what syncs, «Συγχρονισμός τώρα»,
   «Επεξεργασία» and «Αποσύνδεση» (keep or delete, the Garmin sheet made generic).
   In a browser a connected phone row says it «συγχρονίζεται από την εφαρμογή στο
   κινητό» and can still change choices or disconnect. A quiet «Λήψη δεδομένων
   συσκευών (JSON)» link appears once any device is connected.

## Rationale
- A plugin of our own keeps the surface to the five kinds we store, read-only, with
  no third-party SDK or licence in the health path, and both platforms answer one
  TS interface that is unit-tested.
- Shaping in TS rather than Swift and Kotlin means one tested implementation of the
  night and day rules instead of two untestable ones (native code can't be built in
  CI here).
- Reusing the Garmin pipeline gives phone data the same dedupe, «manual wins»,
  cross-device rules, private-by-default workouts and delete/export paths for free,
  and keeps one place to change them.
- Foreground sync avoids background-delivery entitlements and battery budgets, and
  the 2-day overlap on each read is free thanks to dedupe.

## Alternatives Considered
- **Community plugins** (`capacitor-health`, `@perfood/capacitor-healthkit`, …):
  rejected; uneven Capacitor 8 support, broader permission sets than needed, and the
  shaping would still be ours.
- **`/api/integrations/phone-health/ingest`** as the plan sketched: rejected for
  `/api/me/devices/phone/:provider/*`, next to Garmin's routes and the devices page
  that owns them.
- **Background delivery** (HKObserverQuery, WorkManager): deferred; more entitlements
  and review questions for little gain while the app is opened daily.
- **Separate phone tables**: rejected; it would fork dedupe, delete and export.

## Consequences
- Apple Health can't tell the app what it may read, so iOS keeps the person's
  choices and refused kinds simply read as empty; Android switches refused kinds off.
- The first device to deliver a record wins: a Garmin night already imported makes
  the phone's copy «other device has it», and the other way round.
- Steps are a new `daily_stats` metric and count as health data, like sleep, weight
  and resting HR. Garmin keeps its four choices, so its consent rules don't change.
- Android needs minSdk 26 (Health Connect), Kotlin in the app module and a
  privacy-policy activity; iOS needs the HealthKit capability.

## Owner actions
- Apple: enable HealthKit on the App ID and in the provisioning profiles; App Store
  Connect privacy answers (health and fitness data, not linked to tracking).
- Google: Play Console Health Connect declaration for the seven read permissions,
  with the privacy-policy link and a short screencast of the flow.
- A public privacy-policy page that covers phone health data (Health Connect's
  rationale screen opens `/me/devices` in the app until it exists).

## Implementation Notes
### Decisions (made without asking, per the brief)
- Plugin in the app target, not an npm package: one consumer, fewer moving parts.
- `granted: null` on iOS instead of guessing from empty reads: HealthKit hides it.
- Kinds: activities, sleep, weight, resting_hr, steps; no calories or HRV: the
  journal has nowhere to show them yet.
- Steps stored on `daily_stats.steps` (migration `20261114100000_phone_health`), not
  a new table: same day key and replace-on-change rule as resting HR.
- Day and night kinds are replaceable (a re-sent day updates the import); workouts
  and weigh-ins are not: they dedupe by id.
- Read window from the server (`connected_at − 30 d`, then `last_synced_at − 2 d`):
  one rule for every install of the app.
- An empty read still posts `{}` so «last synced» moves on.
- Batches of at most 500 records per list, checked on both sides
  (`phone_health_batch_too_large`).
- Instants travel as strings with offset, not OpenAPI `date-time`, so the local day
  survives casting.
- Sleep: segments joined across gaps under 2 h; `in_bed` only when no asleep data;
  the longest span per wake day; under 30 min dropped.
- Connect/update ask for the health-data consent with the ADR-158 flow, shared with
  Garmin through `WellnessConsent.for_device/4`.
- The disconnect sheet became `DeviceDisconnectSheet`; Garmin's test ids stay.
- Export is one JSON download (`GET /api/me/devices/export`), nights and weigh-ins
  stay in the wellness and body exports where they already live.
- Capacitor's plugin proxy answers `then`, so a promise resolving to it never
  settles; `healthPlugin()` hands out a plain delegating object (caught by e2e).
- Workout types use Garmin-style `UPPER_SNAKE` names so `ActivityMatch` and the
  journal treat both sources alike.

### Open device testing (native code was reviewed, not compiled here)
- Build both shells in Xcode and Android Studio (Kotlin 2.1.21 plugin,
  connect-client 1.1.0, coroutines 1.10.2).
- HealthKit permission sheet, reads with real data, `HKMetadataKeyTimeZone` offsets,
  avg/max HR on iOS 16+.
- Health Connect permission contract, rationale screen and VIEW_PERMISSION_USAGE
  alias, «not installed» / «update required» and the Play Store hand-off.
- Resume-triggered sync and the 15-minute throttle on device.
- The JSON export's blob download inside the WebView (may need the share sheet).
