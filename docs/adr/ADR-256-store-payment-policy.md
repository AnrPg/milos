# ADR-256: Payments in the store apps: what is sold where, and how the payer pays
Date: 2026-10-29
Status: Accepted

## Context
V3-M12 (CP-F1) puts the member app (`app.palee.member`, Capacitor shell of the
web app, ADR-171) on the Apple App Store and Google Play. ADR-246/247/248 added
online payments through each business's own provider account (Viva, Stripe):
the payer types the card on the provider's checkout page, which then redirects
to `https://<host>/pay/return?payment=<id>` (and `&cancelled=1` from the cancel
URL; Viva also adds `s` = order code and `t` = transaction id).

Both stores control payments inside apps:

- **Apple 3.1.3(e)** "If your app enables people to purchase physical goods or
  services that will be consumed outside of the app, you must use purchase
  methods other than in-app purchase to collect those payments, such as Apple
  Pay or traditional credit card entry."
- **Apple 3.1.3(d)** real-time one-to-one services ("fitness training") may be
  paid outside in-app purchase; "One-to-few and one-to-many real-time services
  must use in-app purchase."
- **Apple 3.1.1** unlocking features or content (subscriptions, premium
  content) must use in-app purchase.
- **Google Play Payments policy §3.1**: Play's billing system must not be used
  when payment is primarily "for the purchase of physical services", for
  example "gym memberships", or for physical goods. **§2** requires Play
  billing for "subscription services (such as fitness, …)" that are digital,
  and for "cloud software and services".

The stores also require: in-app account deletion (Apple 5.1.1(v), Google
account deletion policy), a privacy manifest and App Privacy / Data safety
answers that match what the app collects, and permission texts.

## Decision
1. **Sold inside both apps, through the box's provider (never In-App Purchase
   or Play Billing):** subscription packages that include anything used in
   person at the box (classes, personal training or assessments, open gym,
   events), payment at booking, personal training packages, event tickets for
   physical venues, shop orders (physical goods) and the box's invoices. These
   are physical services and goods: Apple 3.1.3(e) (and 3.1.3(d) for
   one-to-one personal training), Google §3.1.
2. **Not sold inside the apps (web only, nothing changes on the web):**
   - **Subscription packages with only digital services** (Online
     programming, on-demand content, nutrition plan, none of the in-person
     services of point 1). They count as digital fitness subscriptions (Apple
     3.1.1, Google §2). The package is shown in the apps, without a buy
     button, without a price call to action and without any link or text that
     points to buying it on the web.
   - **Plan (Palee)**, what a business pays Palee: cloud software (Google §2,
     Apple 3.1.1). Owners activate and pay it on the web; the apps show no
     buy or upgrade button.
   - The rule lives in one function, `canBuyHere(item, nativePlatform())` in
     `apps/web/src/lib/platform/store-policy.ts`; screens ask it before
     offering a purchase.
3. **How the payer pays in the apps.** `openCheckout()`
   (`apps/web/src/lib/platform/checkout.ts`) opens the provider's https page in
   the system in-app browser (SFSafariViewController on iOS, Custom Tabs on
   Android) through the Capacitor Browser plugin, never in the app's own web
   view, so the card is typed only on the provider's page with the browser's
   address bar visible. On the web the page opens in the same tab.
4. **Coming back.** `/pay/return` is an app link (universal link on iOS, App
   Link on Android, listed in `apps/web/src/lib/platform/app-links.json` and so
   in `apple-app-site-association`, `assetlinks.json` and the Android intent
   filter). `routeDeepLink()` (`deep-links.ts`) turns it into the in-app page
   plus the API's return body (`payment_id`, `provider_ref`, `transaction_id`);
   the native bridge closes the in-app browser and opens the page. If the
   payer closes the browser without being redirected, the app opens
   `/pay/return?payment=<id>&closed=1` for that payment, so the outcome is
   always read from the API (the webhook and polling of ADR-246 stay the
   source of truth).
5. **Front-desk card payments** go app-to-app to the Viva.com Terminal app
   (V3-M6). Palee never calls ProximityReader, so it needs no Tap to Pay
   entitlement. A future in-app Stripe Terminal SDK would need it.
6. **Store readiness of the native projects:** store version `3.0.0` and build
   number in `apps/mobile/config/release.json` (`PALEE_BUILD_NUMBER`
   overrides per build); permission texts in English and Greek
   (`en.lproj`/`el.lproj/InfoPlist.strings`, camera and photos added); the iOS
   privacy manifests are generated from `apps/mobile/config/data-collection.json`,
   which is also the source of the App Privacy and Data safety answers
   (`docs/release/data-safety.md`); Android declares the camera, a named push
   channel and status-bar icon, no cloud backup, and signs release builds from
   an untracked `keystore.properties`. The `.well-known` files are served only
   for a real Apple team id (10 characters) and real SHA-256 fingerprints, so a
   placeholder never publishes a wrong file.
7. **Account deletion** stays the existing flow (ADR-211): Me › Settings ›
   Delete account, `/me/settings#delete-account`, which works in the apps and
   in any browser.

## Rationale
Paying the box directly is what the rules require for physical services and
keeps the provider's fees low for boxes (no 15–30 % store commission). The
in-app browser is the pattern reviewers expect for third-party checkout, keeps
the card out of the app (PCI SAQ A as in ADR-246), and lets password managers
and Apple Pay in Safari work. Hiding purchases of digital-only packages costs
little (most packages include classes) and removes the one case where a
reviewer could ask for In-App Purchase or Play Billing.

## Alternatives Considered
- **In-App Purchase / Play Billing for everything:** forbidden for physical
  services (Apple 3.1.3(e) says "must use purchase methods other than in-app
  purchase"; Google §3.1), and the money would reach the store, not the box.
- **In-App Purchase only for digital-only packages:** needs a store merchant
  setup per box or Palee as reseller of the box's services, commission and a
  second reconciliation path. Revisit if boxes ask for it.
- **Checkout inside the app's web view:** the provider's host would have to
  be an allowed navigation host, the card would be typed in a view the app
  controls, and 3-D Secure redirects are less reliable there.
- **External-purchase link entitlements (StoreKit External Purchase, Google
  alternative billing):** country-specific, need applications and add fees;
  not needed for physical services.
- **A custom URL scheme (`palee://`) for the return:** any app can claim a
  scheme; universal links / App Links are verified against the domain.

## Consequences
- Screens that sell anything must call `canBuyHere`; reviewers of member-app
  UI work check it.
- Invoices are payable in the apps. An invoice whose only lines are a
  digital-only package is an edge case: when invoice lines carry the package,
  the same rule should hide its pay button.
- The `/pay/return` page itself is UI and waits for an approved mockup; until
  then the deep link opens the route the web app serves there.
- The Plan (Palee) purchase and upgrade buttons must stay out of the apps.
- `config/data-collection.json` must be reviewed before every submission and
  whenever a milestone adds personal data.

## Implementation Notes
- Package classification reads the package contract fields of ADR-098
  (`group_classes.included`, `personal_training.included`,
  `personal_training.assessments`, `facility.open_gym`, `perks.events`).
- The web reaches the native Browser plugin through `registerPlugin` from
  `@capacitor/core` (already a dependency), so no new web package.
- Owner actions (accounts, certificates, keystore, Team ID, fingerprints,
  screenshots) are in `docs/release/signing-guide.md` and
  `/mnt/project-files/milos/v3-store-release-prep.md`.
