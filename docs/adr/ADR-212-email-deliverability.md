# ADR-212: Email deliverability: provider webhook, suppression state, one-click unsubscribe, alarms and retention
Date: 2026-10-27
Status: Accepted

## Context
ADR-203 gave Palee one outbox for every email, with a suppression list, a
daily budget and follow-up work: the provider webhook that calls
`suppress/2`, a retention sweep, and "what happens after sending". Without
those:

- Palee keeps mailing addresses that hard-bounce, and readers who marked
  its mail as spam. Brevo then blocks the sender, and every email suffers.
- Nobody sees the budget run out. Mail is deferred to the next day while
  people wait for an invitation.
- The Brevo SMTP key expires on 2027-10-26 (keys last a year), and all
  email stops silently on that day.
- Gmail and Yahoo require a one-click unsubscribe (RFC 8058) on bulk mail
  from a business, and mail apps show an "unsubscribe" button instead of
  "report spam" when the header is there.
- `email_messages` and `email_link_tokens` grow forever.

## Decision

### 1. Brevo webhook: `POST /api/webhooks/brevo`
- Public, rate limited (1200 a minute per client, bucket `brevo-webhook`).
- Authenticated by the shared secret `BREVO_WEBHOOK_SECRET`
  (`PaleeWeb.Plugs.WebhookSecret`). The secret may come in any of three
  ways, compared in constant time:
  - `Authorization: Bearer <secret>` (Brevo API's `auth` option);
  - HTTP basic credentials whose password is the secret (the dashboard
    URL `https://palee:<secret>@palee.app/api/webhooks/brevo`);
  - an `x-webhook-secret` header (Brevo API's `headers` option).
- A secret shorter than 24 bytes, or none, refuses every call with 503.
  A wrong secret gets 401 and counts as an auth anomaly.
- The body is one Brevo event or a list of them (at most 500).
  `Palee.Email.Domain.ProviderEvent.parse_brevo/1` reads them. What each
  event does:

| Brevo event | action |
|---|---|
| `hard_bounce`, `invalid_email`, `blocked` | suppress the address (`bounce`), message `bounced` |
| `spam` | suppress the address (`complaint`), message `complained` |
| `unsubscribed` | opt the address out of that message's kind, if the message is transactional |
| `delivered` | set `delivered_at` |
| `soft_bounce`, `deferred`, `error` | record only (Brevo retries) |
| `request`, opens, clicks | ignored |

- Matching: by `message-id`. The outbox chose the Message-ID at enqueue
  and the mailer keeps it (ADR-203). Brevo reports it with or without the
  angle brackets. If no message has that ID, the newest message sent to
  the `email` address in the last 30 days is used. An address Palee never
  mailed is still suppressed.
- Idempotent: every event is stored in `email_provider_events` under a
  SHA-256 of its event, address, Message-ID and timestamps. An event
  already stored is skipped (`duplicate`). This keeps a retried webhook
  from suppressing again an address a vendor took off the list.
- Answer: `200 {applied, duplicate, unmatched}`, or `400` when the body is
  not an event.
- Telemetry:
  - `[:palee, :email, :provider_event]` with `%{provider, event, result}`;
  - `[:palee, :email, :bounced | :complained | :delivered]` with ADR-203's
    message metadata.
- Not in the OpenAPI contract: only Brevo calls it.

### 2. Status set
- `email_messages.status` gains `bounced` and `complained`, and the table
  gains `delivered_at`. `Palee.Email.status/1` returns both.
- Suppression reasons are unchanged: `bounce`, `complaint`, `manual`.
- Every email goes through `enqueue/4`, which refuses suppressed
  addresses, so invitations and everything else stop too. The owner
  invitation still uses the mailer directly until ADR-203's follow-up
  moves it onto the outbox.

### 3. Suppression state for screens
```elixir
Palee.Email.deliverable?(address) :: boolean          # valid and not suppressed
Palee.Email.suppression(address) :: %{reason, since} | nil
Palee.Email.undeliverable([address]) :: MapSet.t(normalised address)   # one query, for lists
Palee.Email.opted_out?(address, kind) :: boolean
```
An opt-out from one kind does not make an address undeliverable.
`/auth/me` is not changed here (see Consequences).

### 4. One-click unsubscribe (RFC 8058), transactional mail only
- `EnqueueEmail` gives every email of category `transactional` (mail a
  business sends: invoices, invitations) these extras:
  - `List-Unsubscribe: <https://palee.app/api/email/unsubscribe/<token>>`
  - `List-Unsubscribe-Post: List-Unsubscribe=One-Click`
  - a footer link "Unsubscribe from these emails" (in the email's
    language) after the "sent automatically" line, in both HTML and text.
- Security and account mail never gets them, and never reads opt-outs.
- The headers go into the encrypted body JSON (`"headers"`), so a retry
  sends the same ones. `SwooshSender` passes on only these two headers,
  with line breaks stripped.
- Token (`Domain.UnsubscribeToken`), url-safe base64, no expiry:
  `digest(32) | kind length | kind | locale | HMAC-SHA256[0..16)`.
  - The digest is the suppression digest, so the link carries no
    readable address.
  - The key is `KeyDerivation.derive("email-unsubscribe", "v1")`.
- `GET /api/email/unsubscribe/:token` shows a page with a button, so a
  link scanner unsubscribes nobody. `POST` (a mail app's one-click
  request, or the button) writes `email_opt_outs (address_digest, kind)`.
  - The page is self-contained HTML in the email's locale (strings in the
    `emails` domain) and in the theme colours.
  - It has no scripts, a CSP of `default-src 'none'` and
    `form-action 'self'`, and is not frameable.
  - An invalid token gets a 404 page.
  - Rate limit: 30 a minute per client.
- Opt-outs are per kind, not per category. A reader who stops invoice
  reminders still gets a gym invitation. The suppression table stays for
  "never mail this address".
- `enqueue/4` refuses an opted-out kind with `{:error, :suppressed}`, so
  the error contract is unchanged. The worker also marks a queued message
  `suppressed` when its address opted out after enqueue.
- Brevo's own `unsubscribed` event writes the same opt-out.

### 5. Budget alarm
- `Infrastructure.Observability.EmailProbe` (a 30 s poller, which runs
  only when `METRICS_PORT` is set) emits `[:palee, :email, :budget]` and
  `[:palee, :email, :smtp_key]`, exported as these gauges:
  - `palee_email_sent_today`
  - `palee_email_daily_budget`
  - `palee_email_daily_hard_cap`
  - `palee_email_deferred_messages`
  - `palee_email_smtp_key_days_left`
- Counters:
  - `palee_email_<event>_total{category}`, for enqueued, sent, failed,
    suppressed, deferred, bounced, complained and delivered;
  - `palee_email_provider_events_total{event,result}`;
  - `palee_email_unsubscribes_total{kind}`.
- Alert rules (group `palee-email`, with promtool tests):
  - `PaleeEmailBudgetHigh`: `sent * 5 >= budget * 4` for 5 minutes,
    integer-exact (in floating point, 0.8 × 280 is more than 224);
  - `PaleeEmailDeferred`: more than 0 for 10 minutes;
  - `PaleeEmailSmtpKeyExpiring`: 30 days or fewer (warning);
  - `PaleeEmailSmtpKeyExpired`: below 0 (critical);
  - `PaleeEmailComplaints`: any complaint in a day.
- The prod cluster has no Prometheus today. So that the alarm still works
  there, the delivery that brings the day's count to 80% of the budget
  (`SendingPolicy.budget_warning?/2`, exactly one count a day) logs
  `email_budget_warning sent_today=… daily_budget=… hard_cap=…`.

### 6. SMTP TLS
- `Palee.Mailer.tls_options(relay)`: TLS 1.2 and 1.3, `verify_peer`
  against `:public_key.cacerts_get()`, SNI with the relay's name, and an
  https-style hostname check.
- If the image has no CA store, it falls back to `CAStore.file_path()`.
- Only prod's `runtime.exs` uses it (when `SMTP_RELAY` is set). Dev and
  test keep the Local and Test adapters.

### 7. SMTP key expiry
- `SMTP_KEY_EXPIRES_ON` (`YYYY-MM-DD`; a malformed value stops boot) is
  read into `config :palee, :smtp_key_expires_on`.
- `Workers.SmtpKeyExpiryJob` runs daily at 07:05 UTC and calls
  `Application.SmtpKeyExpiryCheck`. The check always emits the days left.
  From 30 days before:
  - it logs `smtp_key_expiring days_left=…`;
  - it sends the bell notification `email_key_expiring` to every active
    vendor on days 30, 14 and 7 and on each of the last 3 days.
- Once the key has expired, the check logs `smtp_key_expired` as an error
  and notifies every day. There is one notification per vendor per day
  (dedupe key).
- The notification type is in the locked `account` category and links to
  `/platform`.
- `Organizations.list_active_vendor_user_ids/0` reads `vendors` under the
  operator scope `app.vendor_grant` (read-only), because a job has no
  vendor session. This is the first read under that scope outside the
  grant tasks.

### 8. Retention (`Workers.EmailRetentionJob`, daily 03:15 UTC)
- It deletes `email_messages` inserted more than 90 days ago, together
  with their provider events (`ON DELETE CASCADE`). Messages still
  `queued` or `deferred` are never deleted.
- It deletes `email_link_tokens` used or expired more than 7 days ago, so
  for a week an old link still answers "used" or "expired".
- Rules are in `Domain.RetentionPolicy`. The sweep is `Palee.Email.purge/1`.

## Rationale
- **Message-ID first, address second.** Palee chooses the Message-ID, so
  it identifies the exact email. If Brevo rewrites it, the newest send to
  the address is the best guess, and the suppression is per address
  anyway.
- **Recording events by digest.** Brevo sends no event id (`id` is the
  webhook's id). A digest of the identifying fields is stable across
  retries.
- **Opt-out per kind.** "Stop these invoice reminders" should not also
  stop a new gym's invitation, nor any security mail.
- **The unsubscribe page lives in the API.** It works from any mail app
  without the web app or a session, and RFC 8058's POST needs the same
  URL anyway.
- **A log line besides the alert rule.** The 80% warning and the key
  expiry must work on today's prod, which has no Prometheus.

## Alternatives Considered
- **Brevo's own unsubscribe link and contact lists.** That needs Brevo
  contacts and marketing features, and it is not applied to Palee's own
  checks. Rejected; Brevo's `unsubscribed` event is still honoured.
- **IP allowlisting the webhook.** Brevo's ranges change, and the cluster
  ingress sees the proxy's address. A shared secret is simpler; IP
  allowlisting can be added at the ingress later.
- **Signing the unsubscribe token with `Phoenix.Token`.** Its payload is
  readable base64, so the address would be in the URL. A digest plus an
  HMAC is shorter and reveals nothing.
- **A `transactional` opt-out for the whole category.** Too coarse (see
  Rationale).

## Consequences
- New tables, platform tables without RLS:
  - `email_provider_events` (90 days, with its message);
  - `email_opt_outs` (kept; one row per address and kind).
  Neither has an `organization_id`.
- `/auth/me` does not get `email_deliverable`. It would add a query to
  every `/auth/me`, change the OpenAPI shape and the generated web client,
  and clash with verify-email's `email_verified` change in the same map.
  The verify banner can call a small endpoint, or the field can be added
  after both merge, with `Palee.Email.deliverable?(user.email)`.
- An admin view of bounced, complained and opted-out addresses, with
  "take off the list", is still to do. `unsuppress/1` exists.
- The prod alert rules need the observability stack, or Prometheus in the
  cluster. Until then, the log lines and the vendor bell carry the alarms.
- Rotating the SMTP key means a new key in Brevo, the `palee-smtp`
  secret, and a new `SMTP_KEY_EXPIRES_ON`
  (docs/operations/email-deliverability.md).

## Implementation Notes
- Migration: `20261224190000_email_deliverability.exs`. It adds the
  statuses, `delivered_at`, two tables, retention indexes and the
  notification type, using the read-modify-write of
  `notifications_type_check` from earlier migrations.
- Code:
  - commands: `lib/palee/email/commands/{handle_provider_events,unsubscribe}.ex`
  - domain: `lib/palee/email/domain/{provider_event,unsubscribe_token,key_expiry,retention_policy}.ex`
  - schemas: `lib/palee/email/{provider_event,opt_out}.ex`
  - web: `lib/palee_web/plugs/webhook_secret.ex` and
    `lib/palee_web/controllers/{brevo_webhook,email_unsubscribe}_controller.ex`
  - jobs: `lib/palee/workers/{email_retention_job,smtp_key_expiry_job}.ex`
  - check: `lib/palee/application/smtp_key_expiry_check.ex`
  - probe: `lib/palee/infrastructure/observability/email_probe.ex`
- `Layout.html/3` leaves a `<!--palee:unsubscribe-->` placeholder in the
  footer. `EnqueueEmail` replaces it with the link (transactional) or
  removes it (others). Escaped content can never contain `<!--`.
- Runbook: `docs/operations/email-deliverability.md`.
