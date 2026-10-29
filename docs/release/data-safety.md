# Palee 3.0.0: App Privacy (Apple) and Data safety (Google) answers

> ADR-256. Source of truth: `apps/mobile/config/data-collection.json` (read from the API tables and the web code on 2026-10-29). The iOS privacy manifest `apps/mobile/ios/App/App/PrivacyInfo.xcprivacy` is generated from the same file by `npm run configure` and checked by `npm test` in `apps/mobile`. If you change an answer here, change the JSON first.
> Re-check before every submission: V3-M4 to M9 add data (documents, signatures, payments).

## General answers

| Question | Apple | Google |
|---|---|---|
| Do you or your partners collect data? | Yes | Yes |
| Used to track you / shared for advertising? | **No** for every type. No App Tracking Transparency prompt | No |
| Linked to the person's identity? | Yes, every type | n/a |
| Encrypted in transit? | n/a | **Yes** (https everywhere) |
| Can people ask to delete their data? | In-app: Me › Settings › Delete account | **Yes**: `https://palee.app/me/settings#delete-account` (also works in any browser) |
| Independent security review? | n/a | No |
| Ads in the app? | No | No (App content › Ads: "No") |

**"Shared" (Google):** Google does not count transfers to a service provider that processes data on Palee's behalf as sharing. Brevo (email), Google Gemini (voice transcription, not stored), Anthropic (analysis of transcribed text), Viva / Stripe (payments for the box), Apple APNs / Google FCM (push) act as service providers. Answer **Collected, not shared**, unless a contract says otherwise (owner to confirm, see open questions).

## Item by item

| Data | Required? | Apple type (App Privacy) | Apple purposes | Google category › type | Google purposes | Notes |
|---|---|---|---|---|---|---|
| Display name, @handle | Yes | Contact Info › Name | App Functionality | Personal info › Name | App functionality | |
| Email | Yes | Contact Info › Email Address | App Functionality | Personal info › Email address | App functionality, Account management | Brevo sends the emails |
| Phone (trial request, check-in buddy, business request, box legal details) | No | Contact Info › Phone Number | App Functionality | Personal info › Phone number | App functionality | |
| Account id | Yes | Identifiers › User ID | App Functionality | Personal info › User IDs | App functionality, Account management | |
| Gender and partner preference (Training partners) | No | Other Data › Other Data Types | App Functionality | Personal info › Other info | App functionality | Not "Sensitive Info" in Apple's definition |
| Injuries, health certificate, wellbeing, cravings, sleep, heart rate | No | Health & Fitness › Health | App Functionality | Health and fitness › Health info | App functionality | Apple Health / Health Connect read-only, never for ads, not in iCloud |
| Workouts, scores, PRs, journal, body data, steps, nutrition | No | Health & Fitness › Fitness | App Functionality | Health and fitness › Fitness info | App functionality | Garmin only if connected |
| Around me areas (GPS rounded to ~100 m, one search) | No | Location › Coarse Location | App Functionality | Location › Approximate location | App functionality | The arrival reminder's location stays on the phone: **not** precise location |
| Profile, body, post and message photos | No | User Content › Photos or Videos | App Functionality | Photos and videos › Photos | App functionality | |
| Voice logging | No | User Content › Audio Data | App Functionality | Audio › Voice or sound recordings | App functionality | Google: tick **"processed ephemerally"**. Not stored (ADR-175) |
| Messages between people | No | User Content › Emails or Text Messages | App Functionality | Messages › Other in-app messages | App functionality | |
| Posts, comments, notes, signed documents | No | User Content › Other User Content | App Functionality | App activity › Other user-generated content | App functionality | |
| Uploaded files (health certificate, documents, receipts) | No | User Content › Other User Content | App Functionality | Files and docs › Files and docs | App functionality | |
| Bookings, packages, invoices, payments, receipts | No | Purchases › Purchase History | App Functionality | Financial info › Purchase history | App functionality | Viva / Stripe; myDATA provider for Greek receipts |
| Card brand and last 4, payment status, saved-card consent | No | Financial Info › Other Financial Info | App Functionality | Financial info › Other financial info | App functionality | The card number is typed only on the provider's page (ADR-246, ADR-256) |
| Push token, login device hash | Yes | Identifiers › Device ID | App Functionality | Device or other IDs › Device or other IDs | App functionality, Fraud prevention and security | APNs, FCM |
| Feature usage (Palee's own analytics) | Yes | Usage Data › Product Interaction | Analytics, App Functionality | App activity › App interactions | Analytics, App functionality | No third-party SDK |
| Saved filters and searches | No | Usage Data › Search History | App Functionality | App activity › In-app search history | App functionality | |

## Not collected

Contacts, date of birth, precise location, advertising identifiers, crash or performance data from an SDK in the app, browsing history, calendar, card numbers.

## Google Play: other App content forms

- **Health apps declaration:** declare every Health Connect read permission in `AndroidManifest.xml` (exercise, heart rate, distance, sleep, weight, resting heart rate, steps) with the reason "shown in the person's private journal". The privacy policy linked there must be the same as the listing's.
- **Background location:** only if `ACCESS_BACKGROUND_LOCATION` stays in the first release (owner decision; the release-prep notes recommend removing it for the first Play release). Needs the declaration form and a video.
- **Financial features:** none (the box's provider takes the payment).
- **Government apps:** no. **News app:** no.
