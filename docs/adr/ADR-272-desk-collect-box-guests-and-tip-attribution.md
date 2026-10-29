# ADR-272: «Είσπραξη» on the staff phone, box guests, tip attribution and the walk-in's receipt QR
Date: 2026-10-29
Status: Accepted

## Context
ADR-249 and ADR-264 gave Palee Tap to Pay through the «Viva.com Terminal»
app, but no screens: they waited for the approved mockup. The product owner
approved screen 2 of `v3-mockups-pilot-gaps.html`, alternative A: a
step-by-step «Είσπραξη» on the staff phone, Ποιος › Τι › Έλεγχος ›
Viva.com Terminal › Αποτέλεσμα, one main button per step. The mockup listed
API gaps:

1. The payment result did not say which fiscal document it issued (number,
   transmission state), so the result screen could not show «Απόδειξη
   R-000420 · ✓ myDATA».
2. `GET /admin/payments/terminal/availability` said only `available`, not
   why not (no Viva, Stripe, another provider, an account not ready).
3. Only a box member could pay a membership package. A person standing at
   the desk who is not (yet) a member had to be invited first.
4. A tip had no owner: staff could not see whose it was, and payroll had no
   list.
5. A walk-in (no account) had no way to keep the receipt.

The product owner decided the names on 2026-10-29: the new box role is
«Επισκέπτης» (en: Guest), and the walk-in is renamed from «Επισκέπτης
χωρίς λογαριασμό» to «Πελάτης χωρίς λογαριασμό» (en: Customer without an
account) everywhere.

## Decision

### 1. The screens (mockup screen 2 A)
- **Home** (`CollectEntry`, on the staff home for anyone with
  `take_payments`, only inside the store apps where the
  `PaleeVivaTerminal` plugin exists): the big «Είσπραξη» button; or
  «Tap to Pay θέλει σύνδεση με Viva» with the API's reason and «Ρυθμίσεις ›
  Πληρωμές»; or «Λείπει η εφαρμογή «Viva.com Terminal»» with «Άνοιγμα
  store» when the plugin says the app is not installed; and «Μια πληρωμή
  γύρισε από τη Viva» when iOS reset the web app at the PIN pad
  (`takePendingResult`, posted to the API at once).
- **Ποιος πληρώνει;** (`/admin/collect`): today's check-ins, a search by
  name or email, a badge for a guest («Επισκέπτης») and for someone not in
  the box («Όχι στο box», with «Κάνε τον επισκέπτη»), «Πελάτης χωρίς
  λογαριασμό», and «+ Νέος επισκέπτης» (name and email).
- **Τι πληρώνει;**: the renewal of the last package («Προτείνεται»), open
  invoices, shop orders waiting for payment, another membership package
  (themed `ui/Select`), «Άλλο ποσό» (free sale: description ≤ 120,
  amount, category chips). A walk-in sees only orders and a free sale, and
  «Κάνε τον επισκέπτη ›» to sell them a package. Errors stay in the form,
  under the field.
- **Έλεγχος**: who, what, the amount, «Χρέωση X με Tap to Pay».
- **Επιβεβαιώνουμε με τη Viva…** while the answer is not known: the page
  asks every 4 s (a page-scoped work queue, ADR-215), «Έλεγχος τώρα»,
  «Ακύρωση πληρωμής».
- **Αποτέλεσμα**: paid («Πληρώθηκαν X», card and time; when Viva added a
  tip or a surcharge, the breakdown: the sale, «Επιβάρυνση κάρτας · στην
  απόδειξη», «Φιλοδώρημα · για σένα / για την υποδοχή / για το
  προσωπικό, όχι στην απόδειξη», «Στην κάρτα»; the receipt with its
  number, buyer and transmission pill); cancelled; declined; unconfirmed
  («Μην χρεώσεις ξανά», «Έλεγχος τώρα»); amount mismatch; any other
  failure; «Νέα είσπραξη».
- **Receipt**: for a walk-in, a QR of the receipt link shows by default
  («Ο πελάτης σκανάρει και κρατά την απόδειξη στο κινητό του»), and
  «Αποστολή με email» asks for an address. For a member, «Αποστολή με
  email» sends to the account email (ADR-265's outbox) and asks for an
  address only if there is none.
- The `PaleeVivaTerminal` plugin is read from the shell's bridge
  (`Capacitor.Plugins`) when present, otherwise registered through
  `@capacitor/core`.

### 2. API gaps closed
- `GET /admin/payments/terminal/availability` → `{available, reason,
  provider}`, `reason ∈ no_viva | stripe_only | provider_without_terminal |
  account_not_ready`. Whether the phone has the app is known on the phone.
- Every terminal payment returned by the API carries `document`: `{id,
  kind, number, gross_cents, currency, issued_at, authority,
  transmission_status, receipt_url}` (null until the receipt is issued),
  plus `fiscal_document_id`, `started_by_id`, `started_on`,
  `tip_attribution`, `tip_recipient_user_id`, `tip_recipient_role`.
- `POST /admin/payments/terminal/:id/receipt-email` `{idempotency_key,
  to?}`: the payment's document through ADR-265's email; a walk-in needs
  `to`; a member's account email otherwise (placeholder `.invalid`
  addresses count as none → `no_recipient`); no document yet →
  `terminal_no_receipt` (409).
- `GET /admin/payments/desk/people?q=` and `GET
  /admin/payments/desk/options?user_id=` for the first two steps;
  `POST /admin/payments/desk/guests` `{user_id}` or `{name, email}`
  (201 when the person became a guest now, 200 when they already belong).
  All three need `take_payments`.
- `GET /admin/payments/tips?from&to` (`view_finance_reports` or
  `manage_billing`): tips by owner for a period (default: this month, at
  most 366 days).
- `GET /api/memberships/guest-boxes` (account scope): the boxes the
  signed-in person is only a guest of, for the banner.
- `GET /api/public/receipts/:token`: the walk-in's receipt (HTML, `no-store`,
  `noindex`).

### 3. The box role `guest` («Επισκέπτης»)
- A person can be a guest of many boxes. `guest` is a client-type role at
  the lowest tier (owner 5, admin 4, staff 3, member/athlete 2, guest 1),
  may be a membership's only role, is never self-assignable, and owners,
  admins, coaches and front desk may grant it.
- Front desk makes someone a guest from «Ποιος;»: a found person (an exact
  email for someone outside the box: the directory is never browsable by
  name), or a walk-in's name and email. A new email gets a **held** profile
  (ADR-254) that the person claims by proving the inbox. A guest gets a
  finance profile (`user_type_snapshot = guest`, `signup_source =
  admin_created`), so a package, a free sale or a shop order can be sold
  at the desk.
- Memberships are written by owners and admins only (FORCE RLS). Front desk
  and coaches write a guest membership through `palee_add_box_guest(org,
  user)`, a `SECURITY DEFINER` function pinned to `search_path = public,
  pg_temp` (no extension GUC in its `SET`), which checks the acting person
  (`app.user_id`) is active staff of the box, writes only a `guest`
  membership, and leaves an active membership as it is. It relies on the
  function owner bypassing RLS (the migration role in production).
- **What a guest may see** (audited): nothing of the member app. Guest-only
  memberships are left out of `/api/memberships` and of everything built on
  `Organizations.provider_memberships/1` (club scope, around me, event
  hosts, shop product cards), of workout execution and of the staff
  checks (`MembershipPolicy.staff?/1`; `TenantAuthorization` and
  `LocationScopePolicy` counted any non-client role as staff before).
  `AccessPolicy` grants a guest no capability. Booking still needs a
  package entitlement, so a guest books only once a package allows it.
  Seat counting does not count guests. **What a guest sees**: the public
  box page with a banner «Είσαι επισκέπτης του {box}» and «Γίνε μέλος
  box» → the box's packages page; their own receipts by email or QR.

### 4. Tips
- When a payment with a tip succeeds, its owner is written once
  (`payment_intents.tip_attribution`, checked by a constraint):
  `started_payment` (the staff member who started it on their phone),
  else, for a payment started at the desk, `sole_front_desk` (the box's
  only front desk person) or `front_desk_role` (several or none: the
  front desk role, unpersonalised). Owners and admins are never counted.
- The result screen says whose the tip is. Finance › Accounting shows this
  month's tips by owner (a payroll list, never revenue).

### 5. The walk-in's receipt QR
- `receipt_url` is set only for a receipt with no buyer (a walk-in's). The
  token is `Plug.Crypto.sign/4` over the business and the document (salt
  `palee-fiscal-receipt-link`), expires after 90 days and cannot be pointed
  at another document. The page is the document's printable HTML.

### 6. Names
- «Επισκέπτης» (en Guest; de Gast, fr Visiteur, es/pt-PT Visitante, it
  Ospite, nl Gast, ru Гость, bg Гост, he אורח, ar زائر) for the box role.
- «Πελάτης χωρίς λογαριασμό» (en Customer without an account) for the
  walk-in, in the ontology, all 12 catalogs and the UI.

## Rationale
The flow follows the approved mockup step for step; every rule is in a pure
module (`collect-flow.ts`, `TipAttribution`) and tested. A guest role,
rather than a hidden member, keeps «Μέλος box» meaning someone with a
membership, and the role check that hides the member app is one place
(`provider_memberships`). The definer function is the smallest hole in the
memberships RLS: one role, one writer check.

## Deviations from the mockup
- A member's receipt is not «Στάλθηκε με email» automatically: the result
  shows «Αποστολή με email», which sends to the account email.
- «Το «12 επισκέψεις» της Μαρίας ανανεώθηκε έως …» is not shown (the
  payment does not return the renewed package's dates).
- Search is by name or email; phone numbers are not searched.
- «Πληρωμή με μετρητά ›» opens Finance › Members (the desk's cash flow).

## Consequences
- New migration `20270311000000_box_guests_and_tip_attribution`: role
  checks admit `guest` (memberships and invitations), `user_type_snapshot`
  admits `guest`, tip owner columns with a check and an index, and the
  definer function. The down migration turns guests into members.
- Open questions for the product owner: the English "Guest" also names an
  event's «Καλεσμένος» (ontology §4.7); the shop's «Και επισκέπτες»,
  package «προσκλήσεις επισκεπτών» and the door's «Επισκέπτες» use the word
  for other things; whether a guest may leave a box on their own; a guest's
  booking screens; the production role that owns the definer function must
  bypass RLS.
