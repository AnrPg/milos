# ADR-173: Widgets, the arrival reminder (geofence) and NFC door tags
Date: 2026-10-21
Status: Accepted

## Context
Plan P3-M11 (`docs/plans/redesign-phase-3-depth.md` §4 «ADR-173», §5) and
vision §7.5 / §8.4: three home-screen widgets («+1 νερό», today's WOD,
check-in) driven by a small signed widget token API; a geofenced check-in
reminder per location (ADR-141 point) that ends in the same `ResolveScan`
path; NFC door tags in the check-in settings. It builds on the Capacitor
shell and the platform capability layer (ADR-171), where `widgets`,
`geofence` and `nfc` light up when the `MilosWidgets`, `MilosGeofence` and
`MilosNfc` plugins are present, and on the QR check-in of ADR-155.

## Decision
1. **Widget token.** New personal table `widget_tokens` (id, user,
   platform; owner RLS, `@ready_personal_tables`). `POST
   /api/me/widget-tokens` (`platform`, optional `replaces_id`) answers 201
   with `{id, token, expires_at}`; `DELETE /api/me/widget-tokens/:id`
   revokes. The token is a `SignedToken` (`widget-v1`) naming the row, the
   person and their security version; it is valid while the row exists,
   the security version matches and it is younger than 180 days. A person
   keeps at most 10 installs. The web app renews the install's token after
   30 days and on a change of person, and revokes it on sign-out.
2. **Widget API** (`/api/widget/*`, pipeline `:widget`:
   `Plugs.AuthenticateWidget` + 30/min rate limit; the session JWT is not
   accepted here and the widget token is not accepted anywhere else).
   `GET /api/widget/snapshot?timezone=` returns `water` (ml, goal, glass,
   count, neutral status, `can_add`; null when water is hidden in Ευεξία),
   the first 3 items of «Σήμερα» across providers (ADR-162 `MyToday`) and
   `next_class` (the next approved booking until 15′ after its start).
   `POST /api/widget/water` adds one glass of the member's size through
   `LogWellnessEntry` (health-data consent, local day, private) and returns
   the new snapshot. Pure builder: `Widgets.Domain.WidgetSnapshot`.
3. **NFC door tags.** `facility_locations` gains `nfc_enabled`,
   `nfc_secret`, `nfc_secret_rotated_at` (the poster's twin, ADR-155 §5).
   The code is `HMAC(key, "nfc:v1" ‖ location)` with a key derived from the
   tag seed (`CheckInKeys.nfc_key`); the tag holds
   `<host>/c/<location>/n/<code>`. Admin: `GET|PUT
   /api/org/:slug/admin/check-in/door/:location/nfc` and `POST …/nfc/rotate`
   (capabilities as the poster's). `POST /api/check-in/scan` accepts
   `location_id` + `nfc_code`; method `door_nfc`.
4. **Arrival reminder.** Box rule `geofence_reminder` (default on) in
   `facility_check_in_settings`. `GET /api/me/check-in/geofences` returns,
   for every active box that allows it, the located places with a booking
   of the member whose check-in window has not closed (2 h back, 12 h
   ahead; `GeofencePlan`, radius 150 m, a class without a location belongs
   to every place), at most 20 regions (iOS's limit, soonest first), each
   with its windows and a `token` (`SignedToken` bound to member and
   location, 24 h). Tapping the reminder opens `/c/<location>/g/<token>`,
   which posts `geofence_token`; method `geofence`.
5. **One rule for static proof.** `ResolveScan.static_source?/1`: poster,
   NFC tag and reminder only ever check in a booking already in its window
   (`{:poster_no_booking, …}` otherwise; never open gym, suggestions or a
   trial). A reminder tapped by someone no longer a member records nothing
   and notifies no one. Migration `20261123100000_widgets_geofence_and_nfc`
   extends both check-in method constraints.
6. **Native plugins** (minimal, in the app target, registered next to
   `MilosHealth`: `MainActivity.registerPlugin`,
   `MilosBridgeViewController.registerPluginInstance`):
   - `MilosWidgets` `setSession({token, baseUrl, labels, paths})` / `clear()`.
     Android: three `AppWidgetProvider`s (Water with a «+1» broadcast,
     Today, Check-in), `HttpURLConnection` off the main thread, last
     snapshot cached, 30-minute refresh, 401 → «Άνοιξε το Milos». iOS: the
     plugin writes the App Group `group.app.milos.member` and reloads
     timelines; the WidgetKit extension sources live in
     `apps/mobile/ios/App/MilosWidgets/` (iOS 17, `AddWaterIntent` for the
     interactive «+1»).
   - `MilosGeofence` `checkPermissions` / `requestPermissions` /
     `setRegions({regions})` / `clear()`. Android: Play Services
     geofencing (`play-services-location` 21.3.0, `INITIAL_TRIGGER_ENTER`),
     a receiver that shows one reminder per open window, a boot/update
     receiver that re-registers. iOS: `MilosGeofenceMonitor`
     (`CLLocationManager`, started in `AppDelegate` so background relaunches
     reach it, `requestState` for "already inside"), local notifications;
     a tap posts `.capacitorOpenURL`, so the web app's existing
     `appUrlOpen` route handles it (Android opens the same URL as an App
     Link intent).
   - `MilosNfc` `isAvailable()` / `write({url})`. Android reader mode with
     `Ndef` / `NdefFormatable` (60 s); iOS `NFCNDEFReaderSession` writing a
     URI record. Reading needs no code: iOS opens universal links from NDEF
     tags; Android gets an `NDEF_DISCOVERED` filter for `https://<host>/c/`
     written by `scripts/configure.mjs` with the App Links block.
7. **Web wrappers** in `src/lib/platform/` (`widgets.ts`, `geofence.ts`,
   `nfc.ts`), lazily importing `@capacitor/core` like `health.ts`; Web NFC
   (`NDEFReader`, Chrome on Android) writes tags in a browser too.
   `WidgetsGeofenceBridge` (root layout) syncs widgets and regions when the
   app opens and on every resume; sign-out (`clearBrowserPushSubscription`
   in the app) revokes the widget token, blanks the widgets, stops the
   regions and turns the reminder off for the next person.
8. **iOS scene fix.** `SceneDelegate` built its window with a plain
   `CAPBridgeViewController()`, bypassing `Main.storyboard`, so no app
   plugin (MilosHealth either) was registered on iOS. It now uses
   `MilosBridgeViewController()`.

## Decisions
Product and UX choices made without a board (owner's standing instruction:
most robust, least clutter).
- **NFC and the reminder only check in bookings, like the poster:** both are
  static or device-reported proof (a tag link can be copied, a location can
  be faked); the rotating door QR stays the only way into open gym.
- **NFC tag lives in the location's check-in section, next to the poster:**
  tags are per door, and that section already holds the door screen and
  poster; no new page.
- **One NFC row: switch, «Γράψε σε ετικέτα», «Αντιγραφή συνδέσμου», «Νέος
  κωδικός ετικέτας»:** the write button shows only where this device can
  write (app or Web NFC); elsewhere one line says where to do it.
- **The tag link is shown while the tag is off:** tags can be written first
  and switched on after, as with the poster.
- **Reminder is opt-in per phone, off by default, in Box › Check-in, app
  only:** it needs "Always" location; the switch sits where check-in lives;
  browsers never see it.
- **The owner's rule is one switch, on by default:** members still opt in;
  the owner can turn reminders (and reminder check-ins) off for the box.
- **The location never leaves the phone:** the server hands out public box
  coordinates and booking windows; the phone decides on arrival.
- **Remind only with a booking whose window is open, once per window:** no
  nagging on every pass-by; no reminder for open gym.
- **Fixed 150 m radius, no setting:** reliable for region monitoring, near
  enough to mean "at the door", one setting fewer.
- **Widgets are three fixed, small cards:** water against the goal with
  «+1», the first three items of the day, the next class with a tap to the
  personal QR. No calories, no comparisons (§8.6); water disappears when
  hidden in Ευεξία.
- **«+1» without consent opens the app:** the consent is asked where it is
  explained, never from a widget.
- **Widget words come from the web app's i18n:** one source for 12 locales;
  native defaults only for the picker (English, Greek).
- **A widget token per install, revocable, 180 days:** widgets work offline
  from the cache and never hold the session; sign-out, a password change or
  «αποσύνδεση παντού» kills them.

## Rationale
A separate, narrow widget token keeps the session out of widget storage
(App Group / shared prefs) while still letting a widget add water. Treating
NFC and geofence as static sources reuses the poster's tested path in
`ResolveScan` and keeps one rule for weak proof. Region monitoring with
booking windows gives a useful reminder without any server-side location.

## Alternatives Considered
- **Session JWT in the widget:** short-lived and refresh needs the web
  view; storing a refresh token in widget storage is a larger risk.
- **Opaque random widget token with a SECURITY DEFINER lookup:** works, but
  the signed token already names its owner, so plain owner RLS suffices.
- **NFC as open-gym proof:** a copied tag URL would let anyone check in
  from anywhere.
- **Server-side geofencing (phone uploads location):** location data on the
  server for a convenience feature; rejected (§8.6 spirit).
- **Reuse the poster code for NFC:** rotating one would kill the other.
- **Generating the iOS widget target in `project.pbxproj` by hand:** an
  app-extension target (product, embed phase, signing, Info.plist) cannot
  be verified here without Xcode; the sources are committed and the target
  is a two-minute step in Xcode (owner action 4).

## Consequences
- New tables/columns: `widget_tokens`; `facility_locations.nfc_*`;
  `facility_check_in_settings.geofence_reminder`; methods `door_nfc`,
  `geofence`.
- Android: minSdk stays 26 (ADR-172); new permissions (fine/background
  location, notifications, boot, NFC); Play Console needs the background
  location declaration.
- Bookings made after the last sync get a reminder only after the app is
  opened again (sync on open/resume).
- iOS: App Group and NFC entitlements must exist on the App ID.

## Owner actions
1. Apple: enable **App Groups** (`group.app.milos.member`) and **NFC Tag
   Reading** on App ID `app.milos.member`; create a second App ID
   `app.milos.member.widgets` with App Groups.
2. Play Console: complete the **background location** declaration (video of
   the reminder) and the data-safety answers (location used on device only).
3. Store listings: mention widgets, the arrival reminder and NFC.
4. Xcode, once: File › New › Target › Widget Extension `MilosWidgets`
   (bundle id `app.milos.member.widgets`, iOS 17, no configuration intent),
   replace the generated files with `apps/mobile/ios/App/MilosWidgets/`,
   set its entitlements file, add the App Groups capability to both targets.
5. Buy NTAG213/215 stickers for the doors.

## Implementation Notes
- API: `Application.{WidgetAccess, WidgetSnapshots, CheckInGeofences}`,
  `Widgets` context (`WidgetTokenStore` in `@tenant_scoped_stores`),
  `Facility.Domain.GeofencePlan`, `DoorCode.nfc_code/2`,
  `DoorDisplay.nfc_tag/2`. Tests: `widgets_geofence_nfc_test.exs`,
  `geofence_plan_test.exs`, `widget_snapshot_test.exs`.
- Web: `api/widgets.ts`, `api/check-in.ts` (NFC, geofences),
  `components/check-in/{NfcTagRow, ArrivalReminderRow}.tsx`, pages
  `/c/[location]/n/[tag]` and `/c/[location]/g/[token]`; vitest
  `lib/platform/native-extras.test.ts`, `check-in.test.ts`.
- Mobile: `scripts/native-extras-plugins.test.mjs` checks wiring.
- Not compiled here (no Xcode / Android SDK); device testing open: widgets
  on both platforms (add, refresh, «+1», signed-out state, 401), geofence
  permissions flow (When In Use → Always; Android background prompt and
  notifications), reminder on arrival with app killed, reboot
  re-registration, tap → check-in, NFC write (NTAG213) on both platforms and
  tag read opening the app (iPhone background read, Android NDEF filter),
  App Link verification of the NDEF filter host.
- Playwright: no spec added; the screens are covered by unit tests and run
  in the end-of-phase suite.
