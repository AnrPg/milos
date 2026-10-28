# Email deliverability runbook (ADR-212)

Palee sends all email through the outbox (ADR-203) and Brevo SMTP
(`smtp-relay.brevo.com:587`, from `no-reply@palee.app`). This page covers
the settings ADR-212 adds and what to do when an alert or log line fires.
For a step-by-step setup with every command explained, see the operator
guide `email-deliverability-setup-2026-10-27.md` in the project files.

## Environment variables (api container)

| Variable | Example | Default | What it does |
|---|---|---|---|
| `BREVO_WEBHOOK_SECRET` | 64 random hex characters | unset: the webhook answers 503 | Shared secret Brevo presents on `POST /api/webhooks/brevo`. At least 24 characters. Keep it in a Secret (`palee-brevo-webhook`), never in plain env |
| `EMAIL_DAILY_BUDGET` | `280` | `280` | Non-security mail sent past this count in a UTC day waits for the next day (`deferred`). The alarm fires at 80% |
| `EMAIL_DAILY_HARD_CAP` | `295` | `295` | Security mail (password reset and the like) keeps going past the budget until this count; past it, it is refused. Keep it below Brevo's 300 a day |
| `SMTP_KEY_EXPIRES_ON` | `2027-10-26` | unset: no expiry check | The SMTP key's expiry date, `YYYY-MM-DD`. A malformed value stops the boot (the old pod keeps running) |

The other SMTP variables are unchanged: `SMTP_RELAY`, `SMTP_PORT`,
`SMTP_HELO_HOST`, `MAIL_FROM_NAME`, `MAIL_FROM_ADDRESS`, `MAIL_REPLY_TO`,
and `SMTP_USERNAME` / `SMTP_PASSWORD` from the `palee-smtp` Secret.

## Brevo webhook

- URL: `https://palee.app/api/webhooks/brevo`
- Auth, any one of:
  - basic credentials in the URL, `https://palee:<secret>@palee.app/api/webhooks/brevo`;
  - `Authorization: Bearer <secret>`;
  - an `x-webhook-secret: <secret>` header.
- Events to tick: Hard bounce, Soft bounce, Blocked, Invalid email,
  Complaint (spam), Unsubscribed, Delivered. Opens and clicks are ignored,
  so leave them off.
- Check it works:

  ```sh
  curl -sS -X POST https://palee.app/api/webhooks/brevo \
    -H "Authorization: Bearer $SECRET" -H 'content-type: application/json' \
    -d '{"event":"soft_bounce","email":"test@example.invalid","ts_epoch":1}'
  ```

  The expected answer is `{"applied":1,"duplicate":0,"unmatched":0}` (a
  soft bounce is only recorded). Without the header the answer is 401;
  without the env var it is 503.

## Rotating the SMTP key (before `SMTP_KEY_EXPIRES_ON`)

1. Brevo → SMTP & API → SMTP tab → **Generate a new SMTP key**. Note its
   expiry date. Brevo keys last a year.
2. Put the new key into the `palee-smtp` Secret (`SMTP_PASSWORD`). This
   needs the age private key (the sysadmin, or whoever holds it). The
   login `SMTP_USERNAME` stays the same.
3. Set `SMTP_KEY_EXPIRES_ON` in `palee/palee-api.yaml` to the new date.
4. Push. After the rollout, send one email (for example a password reset
   to yourself) and check that the outbox row is `sent`.
5. Delete the old key in Brevo.

The `gmail-send-as` key (Gmail "Send mail as") expires on the same day.
Rotate it in Gmail's settings too.

## Alerts and log lines

| Signal | Where | What to do |
|---|---|---|
| `PaleeEmailBudgetHigh` / log `email_budget_warning` | Prometheus / api logs | 80% of today's budget is used. Look for a loop or a burst (`SELECT kind, count(*) FROM email_messages WHERE sent_at >= date_trunc('day', now() at time zone 'utc') GROUP BY 1`). Raise `EMAIL_DAILY_BUDGET` only if the Brevo plan allows it |
| `PaleeEmailDeferred` | Prometheus | Emails wait for the next UTC day (00:01). Nothing is lost |
| `PaleeEmailSmtpKeyExpiring` / log `smtp_key_expiring` / bell "The email key expires soon" | Prometheus / logs / vendors' bell | Rotate the key (above) |
| `PaleeEmailSmtpKeyExpired` / log `smtp_key_expired` | Prometheus / logs | No email is sent. Rotate now |
| `PaleeEmailComplaints` | Prometheus | Someone marked a Palee email as spam; the address is suppressed. Check which kind it was: `SELECT kind, count(*) FROM email_messages WHERE status = 'complained' GROUP BY 1` |

The prod cluster runs no Prometheus today, so the `palee_email_*` metrics
and the rules in `ops/observability/prometheus/rules/palee-alerts.yml`
apply only where the observability stack runs (`METRICS_PORT` set). The
log lines and the vendors' bell notification work everywhere.

## Suppression and opt-outs

- An address that hard-bounced, was invalid or blocked, or complained is
  on `email_suppressions`. Nothing is mailed to it any more, invitations
  included. Code: `Palee.Email.suppression/1`, `deliverable?/1`,
  `undeliverable/1`.
- To take one off the list (for example, the mailbox was fixed), run in
  the api pod:

  ```sh
  bin/palee rpc 'Palee.Email.unsuppress("person@example.com")'
  ```
- An address that clicked "Unsubscribe" in a business's email
  (transactional mail) is opted out of that one kind only
  (`email_opt_outs`). Security and account mail always go.

## Retention

Daily at 03:15 UTC, `EmailRetentionJob`:
- deletes outbox messages older than 90 days, with their provider events
  (never ones still queued or deferred);
- deletes link tokens used or expired more than 7 days ago.
