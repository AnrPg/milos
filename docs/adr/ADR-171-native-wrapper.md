# ADR-171: Native wrapper (store apps around the web app)
Date: 2026-10-21
Status: Accepted

## Context
Plan §5 P3-M9 and decision D8 (`docs/plans/redesign-phase-3-depth.md`): store
apps for iOS and Android around the existing Next.js app, same code and same
deploy, with native plugins only for what the web can't do. P3-M10 (Apple
Health / Health Connect) and P3-M11 (widgets, geofence, NFC) build on this
shell. Vision §8.4 lists the native capabilities; §4 asks for no clutter.

The web app is not a static site: `apps/web/next.config.ts` builds
`output: "standalone"` with rewrites (`/org/:slug/*`, `/api/*`), redirects
(ADR-137 route moves, buddy links) and server routes (`manifest.ts`, the
public box page, `.well-known`), and `src/proxy.ts` issues a per-request CSP
nonce and the retired-slug redirects (ADR-122). A `next export` bundle would
lose all of that.

## Decision
1. **Capacitor 8 shell in `apps/mobile/`** with exact versions:
   `@capacitor/core|cli|ios|android` 8.5.3, `app` 8.1.2,
   `push-notifications` 8.1.3, `browser` 8.0.5, `preferences` 8.0.1,
   `splash-screen` 8.0.2, `status-bar` 8.0.4, `haptics` 8.0.2. App id
   `app.milos.member` (no bundle id existed in the repo), name «Milos».
2. **The shell loads the deployed web app** (`server.url`), chosen per build
   by `MILOS_APP_ENV` (`production` → `https://milos.4kq.net`, `staging` →
   `MILOS_APP_URL` required, `development` → `http://localhost:18080`;
   `MILOS_APP_URL` overrides any of them; production refuses http).
   `apps/mobile/config/environments.json` + `config/resolve.cjs` hold this;
   `capacitor.config.ts` and the scripts both read it.
3. **Navigation allow-list:** the app's host plus `connect.garmin.com`
   (Garmin's OAuth page, ADR-161, so the redirect back stays in the app).
   Every other host opens in the system browser (Capacitor's behaviour for
   hosts outside `server.allowNavigation`). The same hosts are the iOS
   app-bound domains.
4. **Offline:** the shell has one local page, `www/offline.html`
   (`server.errorPath`), shown when the web app can't be reached at a cold
   start; «Δοκίμασε ξανά» and the `online` event reload the web app. Once
   loaded, the app behaves as the web does offline: the command outbox and
   message outbox in IndexedDB queue writes and send them on reconnect, and
   the service worker keeps the workout cache. iOS keeps service workers in
   a WKWebView only for app-bound domains, hence
   `ios.limitsNavigationsToAppBoundDomains` and `WKAppBoundDomains`.
5. **Native projects are in git.** `npx cap add android` and `npx cap add ios`
   ran here without the Android SDK or Xcode (Capacitor 8 uses Swift Package
   Manager on iOS, so no CocoaPods either), so `apps/mobile/android` and
   `apps/mobile/ios` are committed. `scripts/configure.mjs` writes the
   environment into them between `milos:app-links` markers on every run:
   the Android App Links intent filter (`autoVerify`), the iOS Associated
   Domains and `aps-environment` entitlements (and `CODE_SIGN_ENTITLEMENTS`
   in the Xcode project), `WKAppBoundDomains`, and `www/app-config.js`.
   `scripts/bootstrap.sh` reproduces the whole setup on a build machine.
   `AppDelegate.swift` forwards the APNs token to the push plugin.
6. **Share links open the app** (universal links / App Links) for the
   prefixes in `apps/web/src/lib/platform/app-links.json`: `/c/` (QR
   check-in and posters), `/join/`, `/b/` (box page and its chat), `/r/`
   (referrals), `/events/`, `/trials/`, `/buddy/`. The web app serves
   `/.well-known/apple-app-site-association` and
   `/.well-known/assetlinks.json` as route handlers read at request time
   from `APPLE_TEAM_ID` (+ `IOS_BUNDLE_ID`) and
   `ANDROID_SHA256_CERT_FINGERPRINTS` (+ `ANDROID_PACKAGE_NAME`); each
   answers 404 until configured. In the app, `NativeAppBridge` routes an
   opened link to its path, only when it points at the app's own host.
7. **Native push next to web push.** New personal table
   `native_push_tokens` (owner RLS; `provider` `fcm`+`android` or
   `apns`+`ios` with `apns_environment`; unique per provider and token).
   `POST /api/notifications/native-push-tokens` registers (201, then 200 on
   refresh; the token is never echoed), `POST
   /api/notifications/native-push-tokens/unregister` forgets (the token
   travels in the body, never in a URL), and `GET
   /api/notifications/push-config` gains `native_providers`. A token moves
   to whoever registers it last on that install
   (`milos_claim_native_push_token`, SECURITY DEFINER, deletes only other
   accounts' rows for that exact token). Every notification that gets a web
   push also queues one `NativePushDispatchJob` per install whose provider
   is configured; the job sends the same title, body and link, records the
   same delivery outcome analytics (ADR-123, install hashed), deletes tokens
   the provider calls gone and retries other failures.
8. **Delivery port `Notifications.Ports.NativePushSender`** with
   `FcmSender` (FCM HTTP v1: service-account JWT bearer grant for the
   `firebase.messaging` scope, access token cached until 5 minutes before
   expiry) and `ApnsSender` (HTTP/2, ES256 provider JWT from the .p8 key,
   reused 40 minutes; production or sandbox host per token). Credentials
   come from runtime config (`FCM_SERVICE_ACCOUNT_JSON`, `APNS_TEAM_ID`,
   `APNS_KEY_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPIC`), as text or file path.
   Without them the provider is off: nothing is queued and registration
   answers 503 `native_push_not_configured` (the Wallet/Garmin pattern, D10
   of Phase 2). Both adapters are tested against fake providers (`Req.Test`).
9. **`src/lib/platform/` capability layer in the web app:** `isNative()`,
   `nativePlatform()`, `nativePushProvider()`, `hasCapability()` and
   `getCapabilities()` for `nativePush`, `healthKit`, `healthConnect`,
   `widgets`, `geofence`, `nfc` — all false on the web. Detection reads the
   bridge the shell injects (`window.Capacitor`) and imports nothing;
   `@capacitor/app` and `@capacitor/push-notifications` are imported lazily
   inside the app only, so the web bundle carries no Capacitor code on any
   page. A capability is "its plugin is present on its platforms", so
   P3-M10/M11 light up by shipping their plugin (`MilosHealth`,
   `MilosWidgets`, `MilosGeofence`, `MilosNfc`). `usePlatform()` exposes it
   to components without a hydration mismatch.
10. **Push in the app:** `usePushNotifications` keeps its interface and
    switches to OS push when native (permission → APNs/FCM token →
    registration once per app run); sign-out forgets the install's token.
    A tapped push opens its link in the web view and records the click.
    Android's back button follows the web history and minimises at the root.
11. **Safe areas:** the root layout sets `viewport-fit=cover`; bottom insets
    were already handled by the tab bar and every sheet. Inside the app
    (`html[data-platform]`, set before first paint) the body starts below
    the status bar, a strip in the page colour sits behind it, and the top
    bar sticks below it. Browsers never get `data-platform`, so the web is
    unchanged.
12. **CSP and CORS: no change.** The web view's origin is the deployed web
    app's own https origin, so the CSP (`'self'`, nonce) and same-origin
    `/api` calls work as in a browser; `capacitor://localhost` /
    `https://localhost` only serve the offline page, which calls nothing.

## Decisions
Product and UX choices made without a board (owner's standing instruction:
most robust, least clutter).
- **Remote URL, not a bundled export:** the proxy, rewrites, redirects and
  server routes need the Next server; one deploy updates web and apps alike.
- **Generated native projects in git, environment applied by a script:**
  reviewable diffs and reproducible builds without hand edits in Xcode.
- **Share links only, not the whole site, open the app:** opening a QR code,
  invite or box page in the app is what people expect; admin links and
  e-mail flows (password reset) keep opening where they were tapped.
- **Registration answers 503 while a provider has no credentials:** nothing
  is stored that cannot be used, and it matches Wallet and Garmin.
- **A token follows the last account that registered it:** the person
  signed in on the phone is the one holding it; shared devices just work.
- **The token is never echoed and unregistering takes it in the body:** it
  stays out of URLs, logs and responses.
- **APNs environment defaults to production:** store and TestFlight builds
  use it. The API already accepts `apns_environment: "sandbox"` for Xcode
  debug builds; the web sends nothing until a native build flag exists.
- **No «Εγκατάσταση εφαρμογής» prompt to hide:** the web app has none
  today; any future install prompt must check `isNative()` first.
- **Devices rows (least clutter):** in a browser both phone-health rows keep
  «Με την εφαρμογή»; inside the app only this phone's row shows (Apple
  Health on iOS, Health Connect on Android) and reads «Σύντομα» / «Έρχεται
  σε επόμενη έκδοση της εφαρμογής.» until the P3-M10 plugin is present.
- **No new screens:** push on/off stays where it is (bell and profile); the
  app adds no settings of its own.
- **Offline page copy is bilingual (Greek, else English):** it is a static
  local file, outside the web app's i18n.

## Owner actions
1. Apple Developer Program membership; note the **Team ID** → `APPLE_TEAM_ID`
   (web) and `APNS_TEAM_ID` (API).
2. Register the App ID `app.milos.member` with Associated Domains and Push
   Notifications capabilities; create provisioning profiles / let Xcode
   manage signing.
3. Create an **APNs auth key (.p8)** → `APNS_KEY_ID`, `APNS_PRIVATE_KEY`
   (`APNS_TOPIC` = bundle id if it changes).
4. Create a **Firebase project**, add the Android app `app.milos.member`,
   download `google-services.json` into `apps/mobile/android/app/` (never
   committed), and create a service account with the Firebase Cloud
   Messaging API → `FCM_SERVICE_ACCOUNT_JSON`.
5. **Google Play Console** account; create the app, enrol in Play App
   Signing; put the SHA-256 fingerprints of the upload key and of Play's app
   signing key in `ANDROID_SHA256_CERT_FINGERPRINTS`.
6. Generate and safely store the **Android upload keystore**; configure
   release signing in Android Studio (keystores are gitignored).
7. Confirm the production host (`https://milos.4kq.net` is the default in
   `apps/mobile/config/environments.json`) and set a staging URL if wanted.
8. App icons and splash artwork (the generated defaults are Capacitor's),
   then store listings for both stores: name «Milos», descriptions in Greek
   and English, screenshots, privacy policy URL, data-safety / privacy
   nutrition answers (push token, account data; health data arrives with
   P3-M10), age rating, support contact.
9. Build and submit: `cd apps/mobile && npm run bootstrap`, then
   `npx cap open ios` / `npx cap open android` (Xcode 16+, Android Studio
   with SDK 36 and JDK 21).

## Rationale
Capacitor keeps one codebase and one deploy (D8) and still gives real
native plugins where the web stops (push on iOS outside an installed PWA,
HealthKit, Health Connect, widgets, geofencing, NFC). Loading the deployed
URL keeps every server feature and ships web fixes to the apps instantly;
the offline page plus the existing outbox and service worker cover the
connectivity gap. A provider-agnostic sender port mirrors the existing web
push dispatcher, so delivery, analytics and token clean-up stay uniform.

## Alternatives Considered
- **Static export bundled in the app:** loses the proxy (CSP nonce,
  retired-slug redirects), rewrites, redirects and server routes; every web
  fix would need a store release.
- **TWA (Android) + PWA (iOS):** no HealthKit, widgets, geofence or NFC on
  iOS, which P3-M10/M11 need.
- **React Native / Flutter rewrite:** a second codebase, against D8.
- **FCM for iOS too (Firebase iOS SDK):** one provider, but adds the
  Firebase SDK to the iOS app; APNs directly is lighter and already
  familiar from Wallet (ADR-155).
- **Storing tokens while unconfigured:** rejected; data that can't be used.

## Consequences
- New env vars: API `FCM_SERVICE_ACCOUNT_JSON`, `APNS_TEAM_ID`,
  `APNS_KEY_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPIC`; web `APPLE_TEAM_ID`,
  `IOS_BUNDLE_ID`, `ANDROID_PACKAGE_NAME`,
  `ANDROID_SHA256_CERT_FINGERPRINTS` (passed through docker-compose).
- Web dependencies `@capacitor/core`, `@capacitor/app`,
  `@capacitor/push-notifications` (lazy chunks, loaded only in the app).
- Changing the app-link prefixes means editing `app-links.json` and
  re-running `npm run configure` in `apps/mobile`.
- P3-M10/M11 add their plugins in `apps/mobile` and gate UI with
  `hasCapability(...)`.

## Implementation Notes
- Migration `20261121100000_create_native_push_tokens`;
  `native_push_tokens` is listed in `@ready_personal_tables`.
- `NativePushTokenStore` facade is in `@tenant_scoped_stores`.
- Tests: API controller, worker, payload domain and both adapters against
  `Req.Test` fakes; vitest for the platform layer, app links and native
  push; `apps/mobile` has `node --test` checks for the configure script;
  Playwright `e2e/native-wrapper.spec.ts` (well-known 404s, browser rows,
  simulated iOS bridge).
- Native builds were not compiled here (no Xcode / Android SDK).
