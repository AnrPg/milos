# Palee 3.0.0: notes for App Review and Google Play review

> V3-M12, ADR-256. Part 1 is for the product owner (how to prepare the review accounts). Part 2 is the English text to paste into App Store Connect › App Review Information › Notes and into Play Console › App content › App access.
> Guideline quotes were checked on 2026-10-29 against https://developer.apple.com/app-store/review/guidelines/ and https://support.google.com/googleplay/android-developer/answer/9858738. Read them again before you submit.

## Part 1: preparing the review accounts (owner)

Apple 2.1(a): "include demo account info (and turn on your back-end service!) if your app includes a login." Google asks the same in App content › App access.

1. **Create the review business in production.** Business name «Palee Review Box», in demo mode (ADR-184: sample people, a week of classes, the day's WOD, subscription packages, a club with posts). Never use real members.
2. **Connect a test payment account to it** (Admin › Payments › Account): Stripe with a **test** secret key (`sk_test_…`, environment "test") is the simplest, because reviewers know Stripe's test card `4242 4242 4242 4242`, any future expiry, any CVC. A Viva **demo** account (environment "test", `demo.vivapayments.com`) also works; then give Viva's demo card from Viva's developer portal. The sandbox provider of ADR-246 is off in production and cannot be used.
3. **Create two people:**
   - `review-member@palee.app`: Μέλος box of Palee Review Box, with one active subscription package and one unpaid invoice, so the reviewer can see a payment.
   - `review-owner@palee.app`: owner of Palee Review Box.
   Confirm both emails, turn off two-step sign-in for them, set long random passwords, and keep them in your password manager.
4. **Check before submitting:** sign in with both accounts on a phone, book a class, open the unpaid invoice and pay with the test card (the provider's page opens in the in-app browser and returns to the app on `/pay/return`), and delete nothing.
5. **After every approval:** change both passwords (and update them in App Store Connect and Play Console before the next submission).
6. **Video (optional, recommended):** a 1–2 minute screen recording of the front-desk card payment through the Viva.com Terminal app, uploaded unlisted; put its link where Part 2 says `[video link]`. Without a Viva merchant account the reviewer cannot test that flow.

Where things are in the app (for your own check):
- Account deletion: **Me › Settings › Delete account** (`/me/settings#delete-account`). Asks for the password, confirms by email, deletes after 7 days, can be undone from the email (ADR-211). Legal accounting records are kept as the law requires (ADR-117).
- Report and block: on a post or message, the «…» menu › Report; on a person's profile, «…» › Block (tables `community_reports`, `community_user_blocks`).
- Arrival reminder (optional geofence): Box › Check-in.

## Part 2: text for the reviewer (paste as is, fill in the brackets)

```
Palee is a management and community app for gyms and CrossFit boxes. Members of a box book classes, see the workout of the day, log scores and talk with their box's community. The box's staff manage classes, subscription packages, payments and documents.

DEMO ACCOUNTS
Member: review-member@palee.app / [password]
Owner: review-owner@palee.app / [password]
Both belong to "Palee Review Box", a demo business with sample data. Its payments use the payment provider's test mode and never charge a real card. Test card: 4242 4242 4242 4242, any future expiry date, any CVC.

To see a payment: sign in as the member, open Me > Payments, choose the unpaid invoice and pay. The payment provider's page opens in the in-app browser (SFSafariViewController) and the app comes back through a universal link to /pay/return.

PAYMENTS (guidelines 3.1.3(e) and 3.1.3(d))
Everything that can be bought in the app is a physical service consumed at the gym or a physical good from the gym's shop: memberships with in-person classes, class bookings, in-person personal training with a coach (one-to-one), tickets for events at the gym, and the gym's shop products. Under guideline 3.1.3(e) ("If your app enables people to purchase physical goods or services that will be consumed outside of the app, you must use purchase methods other than in-app purchase to collect those payments") these are paid to the gym through the gym's own card processor (Viva.com or Stripe). The money goes to the gym, not to Palee.
Nothing digital is sold in the app: packages that contain only remote online programming are shown without a purchase option, and Palee's own business subscription for gyms is not sold or linked in the app.

FRONT-DESK CARD PAYMENTS
Staff can take a card payment at the front desk. Palee opens the separate Viva.com Terminal app (app-to-app), which reads the card; Palee itself does not use the ProximityReader framework. This needs a Viva merchant account and cannot be tested by the reviewer; a video is here: [video link].

NATIVE FEATURES (guideline 4.2)
Push notifications (optional, per category), Apple Health (read-only: workouts, sleep, weight, resting heart rate and steps appear in the user's private journal), home-screen widgets, an optional arrival reminder (geofence; the location stays on the device), writing NFC check-in tags, QR check-in with the camera, universal links for invitations and payments, and an offline mode with a queue of pending actions.

ACCOUNT DELETION (guideline 5.1.1(v))
Me > Settings > Delete account.

USER-GENERATED CONTENT (guideline 1.2)
Users can report posts and messages (the "..." menu > Report) and block other users (profile > "..." > Block). Reports are reviewed by the box's staff and by Palee.

PERMISSIONS
Camera: QR check-in, body photos, photos in posts. Photos: choosing a picture. Microphone: logging a workout by voice (not stored). Location: boxes near you and the optional arrival reminder. Health: read-only, shown only to the user. NFC: writing the box's check-in tag. All are asked only when the feature is first used.
```

### Google Play: App access

Choose "All or some functionality is restricted", add one instruction set per account:
- Name: `Box member`, username `review-member@palee.app`, password `[password]`, other information: the paragraph "To see a payment…" above.
- Name: `Box owner`, username `review-owner@palee.app`, password `[password]`.

### If the review asks about payments

Reply with ADR-256's table in plain words and quote:
- Apple 3.1.3(e) as above; for personal training also 3.1.3(d): "If your app enables the purchase of real-time person-to-person services between two individuals (for example tutoring students, medical consultations, real estate tours, or fitness training), you may use purchase methods other than in-app purchase to collect those payments."
- Google Play Payments policy §3.1: Play's billing system must not be used when payment is primarily "for the purchase of physical services", for example "gym memberships".

## Open items before the first submission

1. `/privacy` and `/terms` exist as marked drafts (ADR-267) and Health Connect's privacy link (`palee_health_privacy_path`) is `/privacy#health`. Before submission the law consultant fills in the `[…]` placeholders (controller, address, contact, hosting provider, supervisory authority, governing law) and confirms retention and legal bases, then the draft notice comes off.
2. A public page that explains account deletion without signing in is better for Google than the settings link; it is UI and waits for a mockup.
3. Owner decisions from the release-prep notes §18: company or individual accounts, background location on Android in the first release, DSA trader details. (Minimum age: 16, confirmed at sign-up, ADR-267.)
4. The `/pay/return` page and the member purchase screens are UI and wait for approved mockups; until they exist the reviewer cannot pay in the app, so either ship them first or remove the "To see a payment" paragraph.
