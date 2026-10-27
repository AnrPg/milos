# ADR-208: Security notices by email, new-sign-in alert and the "sign out everywhere" link
Date: 2026-10-27
Status: Accepted

## Context
A person learned about a change to their password, recovery codes or
sessions only in the app, if at all. Someone who took over an account could
change the password or add a profile, and the owner would not find out.
ADR-203 gave Palee a transactional email outbox with single-use links, and
`Palee.Application.SecurityNotices.notify/3` was reserved as the one entry
point for security emails. Other flows (password reset, email change,
account deletion) call it at their own moments.

## Decision
### 1. One notice per event
- `SecurityNotices.notify(event, account, meta)` always returns `:ok`. It
  logs a mail problem and never fails the caller.
- Events and the paths that send them:
  - `:password_changed`: a new password in Settings (`UpdateProfile`).
  - `:password_reset_completed`: a reset link was used (password-reset flow).
  - `:email_change_requested`, `:email_changed`: the email-change flow. The
    second goes to the old address and carries `revert_url`.
  - `:recovery_code_used`: `PasswordRecovery.redeem_code`.
  - `:recovery_codes_running_low`: the same path, when 2 or fewer unused
    codes are left. It links to Settings.
  - `:recovery_codes_regenerated`: `PasswordRecovery.generate_codes`.
  - `:signed_out_everywhere`: `POST /api/auth/sign-out-all` and the emailed
    link below.
  - `:profile_added`: `AccountProfiles.add`.
  - `:new_sign_in`: see section 2.
  - `:account_deletion_scheduled` (carries `undo_url`) and `:account_deleted`:
    the account-deletion flow.
- Every event has its own template module, kind `:security_<event>`, so the
  ADR-203 throttle and delivery status stay per event. The body is shared
  (`Palee.Email.Templates.SecurityNotice`):
  - what happened;
  - when, on the person's clock with the city named, or in UTC with "UTC"
    written when their zone is unknown (ADR-179);
  - the device ("Chrome on Windows", "Palee app on iPhone"), the network
    part of the IP address ("203.0.113.x") and a place when one is known;
  - what to do if it wasn't them: a "Sign out everywhere" button, then a
    "Choose a new password" link (`/forgot-password`).
- Category `:security`. The footer says the notice concerns their account
  and can't be turned off: security notices have no opt-out.
- The address is `meta[:to]` or the login's email. The language is the
  profile's `preferred_locale`. The account is never reloaded.
- Idempotency key: `security_notice:<event>:<login id>:<occurrence>`. A
  caller that may retry passes `meta[:occurrence]`.
- A notice never holds a password, a recovery code or a raw token outside
  its own link.
- In-app notifications that already exist (`password_reset_completed`) stay.

### 2. New-sign-in alert (`login_devices`)
- The web app keeps a random id in `localStorage` (`palee:device-id`) and
  sends it as `x-palee-device-id` with sign-in and sign-up. The native app
  is the same web app.
- The API picks the device id in this order: the `palee_device` cookie
  (httpOnly, path `/api/auth`, 400 days), then the header, then a fresh id.
  It always sets the cookie to the id it picked, so the cookie and the
  header end up the same.
- The user agent is reduced to a client and a platform, with no versions.
- Only `SHA-256("palee-device" | id | client | platform)` is stored, per
  login, with `sign_ins`, `first_seen_at` and `last_seen_at`. A login keeps
  its 30 newest devices.
- A password sign-in from an unknown device sends `:new_sign_in` only when
  the login has signed in with a password before. So:
  - the first sign-in of a login never alerts;
  - a login that existed before this change never alerts on its first
    sign-in;
  - the sign-up device is remembered with `sign_ins = 0`, so the first
    sign-in after sign-up never alerts.
- A token refresh or a profile switch is not a sign-in.
- The login row is locked while a device is remembered, so two racing
  sign-ins agree on whether the device is new.
- `:new_sign_in` may be sent again right away (minimum interval 0), up to
  10 a day.

### 3. "Sign out everywhere" link
- Each notice issues its own `sign_out_everywhere` link token: 7 days,
  single use, `target_email` set to the address the notice went to.
- **Change to ADR-203:** a new link no longer replaces older unused ones.
  When two notices arrive close together, both links keep working.
- `/sign-out-everywhere#token=…` is a web page. The token stays in the URL
  fragment, so it never reaches a server log. The page does nothing until
  the person taps "Sign out everywhere". A mail scanner that opens the link
  therefore signs no one out.
- The tap posts `POST /api/auth/sign-out-everywhere {token}`. This consumes
  the token and bumps the login's `security_version`
  (`Identity.bump_login_security_version/1`). That ends the sessions of
  every profile of the login. The request also:
  - marks the address verified (ADR-203);
  - sends `:signed_out_everywhere`;
  - clears the browser's refresh cookie.
- Answers:
  - `204` when every session was ended;
  - `422 invalid_link`;
  - `410 expired_link`;
  - `410 used_link`.
  The page then suggests choosing a new password.

## Rationale
- One template per event keeps each subject meaningful, makes throttling
  and delivery status per event, and lets other flows add events without
  touching each other's code. The shared body keeps them consistent.
- Hashing the device id with the coarse client and platform means a
  database read never yields an id that can be replayed, and an id copied
  into another kind of browser counts as a new device.
- Only alerting once a login has signed in with a password avoids an alert
  storm when this ships, and avoids alerting on a brand-new account.
- A confirm tap rather than signing out on page load protects against link
  scanners. Signing out is harmless enough that the link needs no session.

## Alternatives Considered
- **Fingerprinting the user agent and IP instead of a device id.** IP
  addresses change on mobile networks, and the result would spam people.
  Rejected.
- **A geo-IP lookup for the place.** It needs a new data source, and
  `meta[:place]` is already supported for later. The network part of the IP
  address stands in for now.
- **A settings toggle for security notices.** Rejected: a person who lost
  control of their account must still hear about it.
- **Keeping `sign_out_everywhere` replacing.** Then an older notice's
  button would stop working as soon as a second notice is sent. Rejected.

## Consequences
- New platform table `login_devices` keyed by login. It has no RLS, like
  `login_recovery_codes`, and is not tenant data.
- Security mail counts toward the ADR-203 hard cap. Past the cap a notice
  is not sent (logged), and the action still succeeds.
- `POST /api/auth/sign-out-all` (Settings) still ends only the current
  profile's sessions. The emailed link ends every profile's sessions.
- Follow-up work:
  - a geo-IP place;
  - a "your devices" list in Settings built on `login_devices`.

## Implementation Notes
- Code:
  - `lib/palee/application/{security_notices,sign_in_devices,sign_out_everywhere_link,recovery_code_notices}.ex`
  - `lib/palee/email/templates/security_*.ex`
  - `lib/palee/identity/domain/sign_in_device.ex`
  - `lib/palee/identity/{login_device,login_device_store}.ex`, `ports/login_device_store.ex`
  - `lib/palee/infrastructure/identity/ecto_login_device_store.ex`
  - `lib/palee_web/sign_in_device.ex`
  - `lib/palee_web/controllers/security_link_controller.ex`
  - migration `20261224150000_login_devices.exs`
  - web `src/lib/device-id.ts`
  - web `src/app/sign-out-everywhere`, `src/components/auth/SignOutEverywhere.tsx`
- Strings: the `emails` gettext domain in every API locale, and the
  `securityNotices` namespace of the web messages.
