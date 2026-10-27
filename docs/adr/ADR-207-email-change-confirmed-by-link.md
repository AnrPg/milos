# ADR-207: Email change confirmed by a link, revert link to the old address, lock
Date: 2026-10-27
Status: Accepted

## Context
The login's email (ADR-187) is where password resets go and what people sign
in with. Until now Settings changed it at once, given the current password:
nothing was mailed, the new address was never proven and every session
survived. Someone who learned the password could move the account to an
inbox they control in one step, and the owner would not find out.

## Decision
### Request (Settings, signed in)
- `POST /api/me/email-change {email, current_password}` needs the current
  password (422 `invalid_current_password`). It records **one pending change
  per login** (`login_email_changes`: `new_email`, `requested_at`,
  `expires_at`, unique on `login_id`) and mails `:email_change_confirm`
  (category `security`) with an ADR-203 `email_change` link (24 h, token in
  the fragment, `/confirm-email-change#token=…`) to the **new** address. A
  new request replaces the pending one and its link.
- The login keeps its email for sign-in and resets until the link is opened.
- The answer (202 with the pending state) is the same whether or not the
  address already has an account: the form never checks, so it can't be
  used to probe addresses. The confirmation step finds a conflict.
- `SecurityNotices.notify(:email_change_requested, account, %{to: old})`
  tells the current inbox at once (no revert link: nothing changed yet).
- `GET` shows `{pending, locked_until}`, `POST …/resend` mails a fresh link
  and restarts the 24 h (throttled like any security mail, 429),
  `DELETE` cancels; a cancelled change's link stops working.
- The confirmation email never names the account or its current address.
- `PATCH /api/me/profile` no longer changes the email: a different address
  is refused with 422 `email_change_needs_confirmation`; the unchanged one
  may still come along. The store's profile update only takes the password.

### Confirm (`POST /api/auth/email-change/confirm {token}`, public)
- Consumes the token, then in one transaction: locks the login row, checks
  the pending change matches the token's `target_email` and hasn't lapsed,
  checks no other login uses the address (case-insensitive;
  `logins_email_unique_index` stays the final word on races), sets
  `email`, `email_verified_at = now`, bumps `logins.security_version` (every
  session of every profile ends) and deletes the pending change.
- A taken address: 409 `email_change_unavailable`, the pending change is
  dropped and nothing else is said. Unknown or used link: 422
  `invalid_email_change_link`; expired: 410 `expired_email_change_link`.
- After the commit: `CorporateSeats.email_changed(login_id, old, new)` (ADR-205;
  a raise is logged by struct name only and never undoes the change), a
  7-day `email_change_revert` link to the **old** address (target_email = old,
  metadata `new_email`), and `SecurityNotices.notify(:email_changed, account,
  %{to: old, revert_url: …})`.
- **Session decision:** the browser that opens the link keeps a session only
  if its refresh cookie (path `/api/auth`, which this endpoint is under)
  belongs to a profile of the same login: it gets a fresh pair for that
  profile (`access_token` and `user` in the answer, new cookie). Any other
  browser gets `access_token: null` and signs in with the new address. The
  page needs a button press, so a mail scanner that opens links changes
  nothing.

### Revert ("this wasn't me", `POST /api/auth/email-change/revert {token}`, public)
- Consumes the revert token, restores the old address (verified now),
  bumps `security_version`, drops any pending change and sets
  `logins.email_change_locked_until = now + 7 days`. Requests while locked
  answer 409 `email_change_locked` with `locked_until`.
- A **password reset** (`reset_login_password`, used by the reset link and
  by recovery codes) clears the lock and any pending change: it proves the
  inbox. A Settings password change does not, since whoever changed the
  email knew the password.
- The page then tells the person to reset their password (`/forgot-password`).
- Revert links are never replaced (ADR-203), so after two changes the first
  link still restores the original address.

### Web
Settings › Personal info shows the email read-only with "Change email"; the
inline form (new email, current password) sends the link; the pending state
says where it waits, until when, and offers resend / cancel; a lock says
until when. `/confirm-email-change` and `/revert-email-change` are auth pages
(no bottom bar). Strings: `emailChange` namespace, 12 locales.

## Rationale
- Proving the new inbox before switching keeps resets going to an address
  that works, and keeps a stolen password from silently moving the account.
- One pending row per login is simpler than a history and enough: the link
  token carries which address it proves.
- Checking for conflicts only at confirmation removes the probing oracle;
  the one who learns that the address is taken already controls that inbox.
- A lock that a reset lifts stops an attacker who still has the password
  from changing the email again straight after the owner reverts it.

## Alternatives Considered
- **`pending_email` column on `logins`.** Fewer tables, but the lapse time and
  request time would also need columns there; a separate table keeps
  `logins` about credentials and deletes cleanly.
- **Hook registry (`EmailChangeHooks`) for other features.** Built first
  while `CorporateSeats` was not on the branch; once it was merged a direct
  call was clearer than indirection for one consumer.
- **Auto-confirm on page load.** Link scanners would confirm changes.

## Consequences
- After a confirmed change the old address is free; someone could sign up
  with it before the owner reverts, and the revert then answers 409
  `email_change_unavailable` (reset the password / contact support). A later
  change could reserve the old address for the 7 days of its revert link.
- Every confirm and revert signs every device out.
- `SecurityNotices` renders the old-address emails (`:email_change_requested`,
  `:email_changed` with `revert_url`).

## Implementation Notes
- Migration `20261224140000_pending_email_changes.exs`; schema
  `Palee.Identity.PendingEmailChange`; `Login.email_change_locked_until`.
- Domain `Palee.Identity.Domain.EmailChangePolicy`; port
  `Palee.Identity.Ports.EmailChangeStore`, facade `Palee.Identity.EmailChangeStore`,
  adapter `Palee.Infrastructure.Identity.EctoEmailChangeStore`.
- Service `Palee.Application.EmailChange`; controller
  `PaleeWeb.EmailChangeController`; template
  `Palee.Email.Templates.EmailChangeConfirm` (own footer reason: the reader
  may not have an account).
- Web: `EmailChangeField`, `ConfirmEmailChange`, `RevertEmailChange`,
  `email-change-model.ts`, `src/api/email-change.ts`, `e2e/email-change.spec.ts`.
