# ADR-206: Password reset by email, with the handler flow as fallback
Date: 2026-10-27
Status: Accepted

## Context
ADR-187 had no mail service. A forgotten password went to human handlers:
the vendor, the staff of the person's boxes or their coach. They checked
it was really the person and mailed a 24-hour link from their own mailbox.
Recovery codes were the self-service fallback. ADR-203 added the
transactional email outbox and single-use link tokens. ADR-187 already
named automatic reset emails as the follow-up.

## Decision
### 1. Asking for a reset
`POST /api/auth/password-reset-requests` takes `{identifier, cant_access_email?, locale?}`.
- The answer is always `202 {"status":"sent"}`.
- The request only queues a `PasswordResetRequestJob` (default queue,
  3 attempts) through the `PasswordResetQueue` port, then answers. The
  answer and its timing are therefore the same whether the account exists,
  gets an email or reaches the handlers.
- The job runs `PasswordRecovery.request/2`:
  - No account: nothing.
  - The login's email is verified (`Identity.email_verified?`) and the person
    did not say "I can't access my email": `LinkTokens.issue("password_reset")`
    with a 1 h TTL and `target_email` = the login's address, plus
    `Email.enqueue(:password_reset, ...)`, category `:security`, key
    `password_reset:<login_id>:<link id>`. Both happen in one transaction, so
    a refused email never replaces the link already in the inbox. The link
    is `/reset-password#token=<raw>`.
  - The email is unverified, the person can't open their inbox, or the email
    cannot go out (suppressed, over the hard cap): the ADR-187 handler
    request, as before (still one open request per login).
- The web `/forgot-password` page has an explicit "I can't access my email"
  path. Every answer screen says "if an account matches".

### 2. Limits
- **Per login.** At most one reset email every 10 minutes and five a rolling
  day, counted from the login's outbox rows (`list_by_idempotency_prefix`),
  leaving out failed and suppressed ones (`PasswordResetPolicy.email_allowed?/2`).
- **Per address.** The template's throttle sets the same 600 s / 5 a day for
  the outbox's per-recipient check.
- **Per IP.** The existing `auth_rate_limited` pipeline (10 a minute) still
  applies.
- **Handler queue.** On top of one open request per login, one client files
  at most three handler requests a day. A client is identified by
  `password_reset_requests.requester_key`, an HMAC-SHA256 of its IP keyed
  with the endpoint's `secret_key_base`; the IP itself is never stored.
- **Over a limit.** Nothing is sent and nothing is filed. The public answer
  is unchanged. Telemetry emits `[:palee, :auth, :anomaly]` with
  `reason: "password_reset_throttled" | "password_reset_handler_cap"`, and
  the vendor log gets `throttled`.

### 3. The link page
- `/reset-password` reads the token from the fragment. Links handlers sent
  with `?token=` still work. The page then removes the token from the
  address bar (`history.replaceState`).
- On open, the page calls `POST /api/auth/password-reset/inspect` (`LinkTokens.peek`
  or the handler hash). It answers 200 `{expires_at}`, 410 `expired_reset_link`
  or `used_reset_link`, or 422 `invalid_reset_link`. Nothing is spent on
  open, so a mail scanner or a reload cannot use the link up.
- `POST /api/auth/password-reset` checks the password rule first. In one
  `PasswordResetStore.transaction/1` it then:
  - spends the link (`LinkTokens.consume`), or locks the handler request by
    its hash (`FOR UPDATE`);
  - for an emailed link, calls `Identity.mark_email_verified(login, target_email)`.
    A mismatch means the address changed since the link was sent, so the
    link is invalid;
  - sets the password, which bumps the login's `security_version`, so every
    session of every profile dies;
  - deletes the login's open handler request.

  Any failure rolls all of it back. There is never a spent link with the old
  password still set, or a new password with the link still usable. Racing
  submits succeed exactly once.
- After the commit, the action is logged (`completed`). The person gets both
  the in-app `password_reset_completed` notification and
  `SecurityNotices.notify(:password_reset_completed, account, %{})`. A
  reset with a recovery code sends its own `:recovery_code_used` notice
  instead (owned by the security notices work).
- Emailed links live 1 h. Handler-issued links keep 24 h.
- `Referrer-Policy: no-referrer` is set on `/reset-password` and
  `/forgot-password` in three places: the Next proxy, a `<meta name="referrer">`
  from page metadata, and Caddy. The API's reset endpoints also answer with
  `no-referrer` and `Cache-Control: no-store`.

### 4. Handlers
Their UI is unchanged, apart from a note that people with a confirmed
email get the link automatically. The vendor log labels the new events
`link_emailed` and `throttled`.

## Rationale
- A background job is the simplest way to get the same answer in the same
  time on every path. Rendering, encryption and the extra inserts of the
  email path, and the handler lookups, all happen off the request.
- Counting a login's emails from its outbox keys needs no new table, and it
  survives an address change. The template throttle covers the address.
- Peek on open and consume on submit, in one transaction with the password
  change, removes both of the classic failure modes: a link burnt by a
  link scanner, and a link spent while the password write failed.

## Alternatives Considered
- **Doing the work inline.** Simpler, but the email path is measurably
  slower than "no account", which leaks existence. Rejected.
- **A `Task` instead of Oban.** No retry, and it is lost on a restart. Oban
  is already the outbox's mechanism.
- **Moving handler links onto `LinkTokens`.** It changes ADR-187's request
  states and its handler UI for no user-visible gain. Kept as is; only the
  completion path is shared.
- **Storing the raw IP for the handler cap.** Personal data with no need.
  An HMAC is enough to count.

## Consequences
- Job args hold the typed identifier (an email or handle) until Oban prunes
  the job. They never hold a token or a password.
- Handler-link completion does not mark the email verified: the request
  does not record which address the handler mailed.
- `password_reset_log.event` gains `link_emailed` and `throttled`.
- Follow-up: once SecurityNotices sends real email, a reset notice could
  carry the device and IP in `meta`.

## Implementation Notes
- Migration `20261224130000_password_reset_by_email` (requester_key, its
  index, new log events).
- Code:
  - `lib/palee/application/password_recovery.ex` (`submit_request/2`,
    `request/2`, `inspect_link/2`, `complete/3`)
  - `lib/palee/identity/domain/password_reset_policy.ex` (limits)
  - `lib/palee/identity/ports/{password_reset_store,password_reset_queue}.ex`
  - `lib/palee/infrastructure/identity/{ecto_password_reset_store,oban_password_reset_queue}.ex`
  - `lib/palee/workers/password_reset_request_job.ex`
  - `lib/palee/email/templates/password_reset.ex`
- Web:
  - `components/auth/{ForgotPassword,ResetPassword}.tsx`
  - strings in the `passwordReset` message namespace
  - `e2e/password-reset.spec.ts`
