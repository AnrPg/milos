# ADR-213: Email verification at sign-up: emailed link, resend, banner, `email_verified`
Date: 2026-10-27
Status: Accepted

## Context
ADR-187 let anyone sign up with any email and never set `logins.email_verified_at`, because
there was no mail service. ADR-203 added the outbox and single-use link tokens. Several flows now
need to trust the address: password reset by email, corporate email-domain seats, business
activation and invitations bound to an email. So the address has to be proved first.

## Decision
- **Sign-up.** A new login (`POST /api/auth/register`, `/register-member`, `/register-admin`)
  gets one `:verify_email` email (category `account`). Adding a profile to an existing login
  sends nothing. `EmailVerification.after_sign_up/1` runs after the tokens are issued, so a sign-up
  that is rolled back (failed token issue, invitation not redeemed) sends nothing. It sends only
  when the login has exactly one profile, is unverified, and has no earlier sign-up email
  (idempotency key `verify_email:<login_id>:sign_up`). People use the app at once; nothing is
  blocked while the address is unverified. Features that need a proved address check
  `Identity.email_verified?/1` themselves.
- **The link.** A `verify_email` LinkToken (48 h, a new one replaces older unused ones, with
  `target_email` = the address it was sent to) goes in
  `<public url>/verify-email#token=...`. The token is in the **fragment**, so mail scanners
  and server or proxy logs never see it and cannot spend it by prefetching. The page posts it.
- **API.**
  - `POST /api/auth/verify-email {token}`: public, behind the auth rate limit (10/min per IP).
    It consumes the token and calls `Identity.mark_email_verified(login_id, target_email)`.
    The answers:
    - `200 {email_verified: true}`
    - `422 invalid_verification_link`
    - `409 used_verification_link`
    - `410 expired_verification_link`
    - `409 verification_email_changed`: the login's email changed after the link was sent.
  - `POST /api/auth/verification-email`: authenticated, sends a new link.
    - `200 {status: "sent" | "already_verified"}`
    - `429 {code: "throttled", retry_after_seconds}` with a `Retry-After` header
    - otherwise the outbox errors through the fallback (`suppressed` 422, `over_budget` 503)
  - The throttle is the template's: 60 s between links and 5 a day. The sign-up email counts.
    It is checked against the login's own verification emails **before** a token is issued,
    so a throttled resend never kills the link already in the inbox, and the answer can say
    how long to wait.
  - `GET /api/auth/me` (and the `user` of login and refresh) carries a required
    `email_verified` boolean.
- **Email change.** Changing a login's email through `Login.credentials_changeset` clears
  `email_verified_at`. The confirmed email-change flow sets it again, because opening its link
  proves the new address.
- **Reuse.** `Palee.Application.EmailVerification.send_verification(account, to:, variant:)`
  sends the same email and link to any address of the login.
- **Web.**
  - `/verify-email` is a signed-out style page (AuthShell, language picker, ErrorNotice for
    every error). It reads the token from the fragment, drops it from the address bar, posts
    it once, and shows one of these states:
    - confirmed
    - already confirmed (a used link on a verified login)
    - expired, used or invalid: signed in it offers "Send a new link"; signed out, "Sign in to
      get a new link"
    - email changed: no new link is offered
  - Signed-in unverified people see one quiet line under the top bar with **Resend** and
    **Change email** (→ `/me/settings#personal`) and a close button that hides it for the
    browser session. It never shows in workout execution, the class timer, the check-in kiosk
    or scan pages, first run, auth pages or public box pages. A user record without the field
    counts as verified.
  - After sign-up the shared "check your inbox" notice (`CheckInboxNotice`, built with the
    sign-up hardening) says a link was sent.
- **Existing logins** (production has only the vendor account) are not emailed at deploy. They
  see the banner and can resend.
- **Dev.** `AUTO_VERIFY_EMAIL=true` (config `:auto_verify_email`, dev only) marks new logins
  verified instead of emailing them. Without it the link shows in `/dev/mailbox`. The dev seed
  marks the dev admin verified. Playwright stubs carry `email_verified: true`.

## Rationale
- Not blocking the app keeps sign-up as quick as before (ADR-187's goal). The gates belong to
  the features that need a proved address, not to sign-in.
- Keeping the token in the fragment is the same choice as ADR-187's reset links. Scanners that
  open links (Outlook Safe Links, corporate gateways) would otherwise spend a single-use token
  before the person clicks.
- Sending after token issue, keyed by login, makes the sign-up email exactly-once without
  changing `RegisterProfile`'s result shape.

## Alternatives Considered
- **Block the app until verified.** People sign up at the front desk and want to book a class
  right away; a missing email would lock them out. Rejected.
- **A six-digit code instead of a link.** It costs an extra screen and typing on mobile, and
  needs its own brute-force limits. The link is enough; a code can be added if mail clients
  break the links.
- **Token in the query string.** Logs, `Referer` and scanner prefetch. Rejected.
- **Mass email to existing unverified logins at deploy.** Production has one account; the
  banner is enough.

## Consequences
- The per-login throttle check and the outbox's per-address check can, in a race of two
  resends in the same instant, issue a token whose email the outbox then refuses. The older
  link has then been replaced, and the person asks again after 60 s. This is accepted.
- `email_verified` is now a required field of the current-user schema; clients regenerate
  their types.
- ADR-187's "no verification for the MVP" is superseded on this point (see its Consequences).

## Implementation Notes
- Code:
  - `lib/palee/application/email_verification.ex`
  - `lib/palee/email/templates/verify_email.ex` (strings in `emails.po` for all 12 locales)
  - `lib/palee_web/controllers/email_verification_controller.ex`
  - the two routes in `router.ex`
  - the `after_sign_up/1` calls in `RegisterUser` and `RegisterInvitedUser`
- Web:
  - `src/api/email-verification.ts`
  - `src/components/auth/{VerifyEmail,EmailVerificationBanner}.tsx`
  - `src/lib/email-verification.ts`
  - `src/app/verify-email/page.tsx`
  - messages namespace `emailVerification`
  - `/verify-email` added to the routes without the bottom bar
- No migration: `logins.email_verified_at` exists since 20261203100000.
