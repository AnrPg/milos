# ADR-205: Verified email gates for corporate seats and business activation
Date: 2026-10-27
Status: Accepted

## Context
Palee did not check that people can read the email on their account.
Two features still trusted that address:
- **Email-domain company plans (ADR-098).** `EnrollCorporateSeat` offered
  and granted a company-paid seat to anyone whose account email ended in
  the company's domain. Anyone could sign up as `x@acme.com` and get a
  seat that Acme pays for.
- **Business activation (ADR-184).** A vendor issued the activation link
  for an account and copied it by hand to the owner. Nothing showed
  whether that account's email was real, and the link never went to it.

ADR-203 added the outbox and `Identity.email_verified?/1`. The
verify-email work (row 1) lets people confirm their address and resend
the link (`POST /api/auth/verification-email`).

## Decision
### 1. Company seats by email domain
- `EnrollCorporateSeat.offer/2` still matches the domain. It now answers
  `%{company_name, needs_verification}`, and `needs_verification` is true
  while the account email is unverified.
- `call/3` without a code joins by domain only when the email is
  verified. Otherwise it returns `{:error, :corporate_email_unverified}`
  (403). The code path is unchanged, because the employer's code is its
  own proof.
- The actor is the Guardian resource (`Identity.find_by_id`). Its
  `%Account{}` carries the login's `email_verified_at`.
- The web card (`CorporateEnrollmentCard`) says "Confirm your email
  address to join <company>'s plan" with a "Send the link again" button
  that calls the verify-email endpoint. It shows the same state when
  enrollment returns the 403.
- A seat records how it was taken:
  `membership_package_subscriptions.corporate_enrolled_via` is `code`,
  `email_domain`, or nil for seats an admin added and seats older than
  this ADR.
- **Email change.** `Palee.Application.CorporateSeats.email_changed(login_id,
  old_email, new_email)` covers every profile of the login in every
  business where it is a member. It ends (cancels today) each active
  `email_domain` seat whose company's domain no longer matches the new
  address, and it refreshes the entitlement. Code seats and admin seats
  stay. The email-change flow calls it once the new address is in place.
  It runs in a system tenant context (`%{organization_id: id}`), like the
  corporate invoicing run, and returns `{:ok, count}`.

### 2. Business activation needs a verified email
- `BusinessActivation.issue_link/4` refuses an account whose email is
  unverified with `{:error, :activation_email_unverified}` (422). This
  covers both the vendor's "issue link" action and approving an
  activation request.
- The vendors' queue now shows:
  - `email_verified` for each owner
  - `requester_email_verified` for each request (nil outside the queue)
- The console shows a badge "Email not confirmed" and disables issuing or
  approving for that account.

### 3. The link is emailed
- On issue, the link is enqueued as `:business_activation_link`
  (category `:account`, idempotency key
  `business_activation_link:<link id>`). It goes to the account's
  verified email in its `preferred_locale` and holds the absolute
  `/activate-business#token=…`.
- The template's throttle is 10 s and 10 a day, so a vendor can replace a
  link a few times in a row.
- An outbox refusal (throttled, suppressed, over budget) never undoes the
  link. The answer's `email_delivery` is
  `{status: "not_sent", error: <code>}`.
- `email_delivery` on a link is `{status, error, sent_at}`:
  - just after issuing, it is the outbox summary
  - in the queue, it is `Email.list_by_idempotency_prefix` for the live
    link
- The console shows "Emailed to the account", "Email on its way" or "The
  email didn't arrive". It also offers "Send a new link", which issues a
  fresh link and email for the same account and role. The raw token is
  only ever stored hashed, so the old email can't be re-sent. The
  copy-link fallback stays.
- `ActivationLinkPolicy.path/1` now uses the fragment form
  (`#token=`). The page reads the fragment and still accepts `?token=`.
  `AuthGuard` keeps the fragment through the sign-in redirect.
- `business_activation_links.email` stores the address the link was
  issued for. Opening the link (`inspect/2`) while signed in as its
  account calls `Identity.mark_email_verified(login_id, link.email)`. If
  the email changed since, that call does nothing (`:email_mismatch`).

## Rationale
- Gating the domain path, not the offer, keeps the offer useful: the
  member learns the company pays and what to do next.
- Recording how a seat was taken lets an email change end only the seats
  that relied on the address. Without it, a seat taken with a code at an
  email-domain company would also be lost.
- Ending the seat at once, rather than flagging it for an admin, matches
  the threat: whoever leaves the domain should stop costing the company
  from that day.
- A fresh link for "resend" keeps tokens hashed at rest (ADR-203 §4).

## Alternatives Considered
- **Checking the domain at every entitlement read.** That puts an
  identity lookup on the hottest finance path and still doesn't know how
  the seat was taken. Rejected.
- **Storing the activation token encrypted to re-send the same email.**
  It keeps a usable secret at rest for no gain over issuing a new link.
  Rejected.
- **Hiding the offer until verified.** The member would never learn why
  their company plan doesn't show. Rejected.

## Consequences
- Accounts that joined by domain before this ADR keep their seats. Those
  seats have `corporate_enrolled_via` nil, so a later email change does
  not end them. A one-off backfill would need to guess, so there is none.
- The email-change flow must call `CorporateSeats.email_changed/3`.
- Vendors can no longer activate an unverified account's business. They
  first ask the person to confirm their email.

## Implementation Notes
- Migration `20261224120000_verified_email_gates.exs` adds two plain
  columns. The RLS policies and grants already cover them.
- Finance: `end_email_domain_seats/3` (context, store port, Ecto adapter).
- Error codes: `corporate_email_unverified` (403) and
  `activation_email_unverified` (422), in `FallbackController`.
- Web: `VerifiedGates` message namespace;
  `activationTokenFrom`, `activationEmailState` (business-accounts.ts);
  `needsEmailConfirmation` (corporate-enrollment.ts);
  `requestCorporateVerificationEmail` calls the verify-email endpoint
  inline until that branch's `resendVerificationEmail`
  (`src/api/email-verification.ts`) is merged.
