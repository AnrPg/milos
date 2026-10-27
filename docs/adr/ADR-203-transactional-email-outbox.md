# ADR-203: Transactional email outbox, templates, link tokens, budgets and suppression
Date: 2026-10-27
Status: Accepted

## Context
Palee sends email through Brevo SMTP (`Palee.Mailer`, sender
`no-reply@palee.app`). Until now there were two emails, owner invitations
and corporate invoices, both sent synchronously inside the request with a
hand-written HTML body in English. Upcoming features need many more
emails: verify email, email change and its revert link, password reset,
account deletion, "sign out everywhere", invitations and receipts. Brevo's
free plan sends 300 emails a UTC day. Sending inside a request loses mail
on a provider outage, double-sends on a retried request, can exceed the
provider's quota and lets a demo business (ADR-184) email real people.
Every feature would also need single-use links and the same look.

## Decision
One shared foundation in the `Palee.Email` context. Feature work only adds
a template module and one registry line.

### 1. Outbox (`email_messages`) and worker
- `Palee.Email.enqueue/4` renders the email at enqueue time and encrypts
  the text and HTML bodies with `DataCipher` (`encrypted_body`). It then
  inserts the row **and** its `Palee.Workers.DeliverEmailJob` in one
  transaction. Inside a caller's transaction it joins that transaction,
  so the email exists only if the caller's write commits.
- Row: `id, kind, to_address (normalised), login_id, user_id,
  organization_id, locale, category, subject, encrypted_body, status,
  attempts, last_error, message_id, idempotency_key (unique),
  scheduled_at, sent_at, timestamps`.
- `status`: `queued`, `deferred` (over budget, snoozed to the next UTC
  day), `sent`, `failed` (given up), `suppressed`.
- `message_id` is the `Message-ID` header. It is chosen at enqueue on the
  sender's domain, and `Palee.Mailer` keeps it, so every retry carries the
  same ID and a provider event can be matched to the row.
- The body is cleared once the email is `sent`, `failed` or `suppressed`.
- The worker runs on its own Oban queue `email` (concurrency 2) with
  `max_attempts` 8 and backoff of 60 s doubling to 1 h. A permanent SMTP
  answer (`:permanent_failure`, 5xx) or an unreadable body is cancelled
  at once. Swoosh exits are caught (`SwooshSender.safe_deliver`). A
  repeat run on a sent message does nothing.
- Telemetry `[:palee, :email, :enqueued | :sent | :failed | :suppressed |
  :deferred]`, measurements `%{count: 1}`, metadata `%{message_id, kind,
  category}` (`:failed` adds `reason`). No event carries the address.
  `:failed` fires only when the email is given up. A retry logs
  `email_delivery_retry`.

### 2. Public contract
```elixir
# Palee.Email
enqueue(kind :: atom, to :: String.t, assigns :: map, opts :: keyword) ::
  {:ok, %Palee.Email.Message{}} |
  {:error, :unknown_kind | :invalid_address | :invalid_category | :not_live |
           :suppressed | :throttled | :over_budget | Ecto.Changeset.t}
  # opts: locale ("en"), login_id, user_id, organization_id,
  #       idempotency_key, category (:security | :account | :transactional), now
status(message_id) :: {:ok, summary} | {:error, :not_found}
  # summary: %{id, kind, category, status ("queued"|"deferred"|"sent"|"failed"|"suppressed"),
  #            attempts, last_error, scheduled_at, sent_at, inserted_at, idempotency_key}
list_by_idempotency_prefix(prefix) :: [summary]   # newest first
suppressed?(address) :: boolean
suppress(address, :bounce | :complaint | :manual) :: {:ok, %Palee.Email.Suppression{}} | {:error, _}
unsuppress(address) :: :ok
budget() :: %{daily_budget: integer, hard_cap: integer}

# Palee.Email.LinkTokens
issue(purpose, login_id, opts \\ []) :: {:ok, raw_token :: String.t, %Palee.Email.LinkToken{}}
  # opts: user_id, target_email, metadata (map), ttl_seconds, now
consume(purpose, raw_token, now \\ DateTime.utc_now()) ::
  {:ok, %LinkToken{}} | {:error, :invalid | :expired | :used}
peek(purpose, raw_token, now \\ DateTime.utc_now()) :: same as consume, never spends it
purposes() :: [String.t]
```
Enqueue checks run in this order:
1. The kind is registered.
2. The address is valid. It is normalised (trim, downcase) and must be
   one `local@domain.tld` with no display name and no control characters.
3. The category is resolved (an override comes from `opts[:category]`).
4. The demo gate.
5. An existing message with the same idempotency key is returned as is,
   with nothing new sent.
6. The address is not on the suppression list.
7. The throttle allows another email.
8. The budget allows it.
9. The email is rendered and inserted.

Conventions for idempotency keys: `"<feature>:<record id>[:<variant>]"`,
for example `"owner_invitation:<invitation id>"` or
`"corporate_invoice:<invoice id>:reminder:2026-12-24"`. With that shape,
`list_by_idempotency_prefix("owner_invitation:<id>")` shows the delivery
status of one record.

`PaleeWeb.FallbackController` maps errors to HTTP codes:
- `invalid_address` → 422
- `suppressed` → 422
- `throttled` → 429
- `over_budget` → 503
- `:not_live` → ADR-184's `business_not_activated` (403)

### 3. Templates
- Behaviour `Palee.Email.Template`. Required callbacks are `category/0`,
  `subject(assigns, locale)`, `text(assigns, locale)` and
  `html(assigns, locale)`. `throttle/0` is optional.
- `use Palee.Email.Template, category: :account` defines `category/0`,
  aliases `Palee.Email.Layout` and adds a private `t(locale, msgid,
  bindings \\ %{})` that reads the `emails` gettext domain.
- Registry `Palee.Email.Templates`: a map from kind atom to module.
  `config :palee, :email_templates_extra` adds kinds; tests use it.
- **How to add an email:**
  1. Write `lib/palee/email/templates/<kind>.ex` (module
     `Palee.Email.Templates.<Kind>`). Build the content from `Layout`
     components and return `Layout.html(locale, blocks, reason: ...)` and
     `Layout.text(locale, blocks, reason: ...)`.
  2. Add one line `<kind>: Palee.Email.Templates.<Kind>` to
     `Palee.Email.Templates`. Keep the list sorted.
  3. Add each new msgid to `priv/gettext/emails.pot` and to
     `priv/gettext/<locale>/LC_MESSAGES/emails.po` for **every** locale:
     ar bg de el en es fr he it nl pt_PT ru. `en` repeats the msgid.
     `Palee.Email.LayoutTest` fails when a locale lacks a string or leaves
     it empty.
  4. Call `Palee.Email.enqueue(:<kind>, address, assigns, opts)`.
- Layout `Palee.Email.Layout`:
  - `html/3` and `text/3` produce an HTML document and its plain-text
    twin, in the theme colours from `BrandPalette`.
  - The product name comes from the `mail_from` name and is never
    "milos".
  - Arabic and Hebrew are laid out right to left.
  - The footer holds the "you're receiving this because …" line and the
    "sent automatically by Palee" line with a link to the public URL.
  - Options: `reason:` and `preheader:`. `reason/2` returns the `:account`
    or `{:business, name}` sentence.
  - HTML components: `heading/1`, `paragraph/1`, `note/1`, `button/2`,
    `fallback_link/2`, `details/1`, `code/1`. Text components:
    `text_button/2`, `text_details/1`. Also `escape/1`, `t/3`,
    `product_name/0`.
  - Every HTML component escapes its values, including `'`. Templates
    never interpolate raw input into HTML.
- Strings already in the `emails` domain:
  - "Hello %{name},"
  - "Hello,"
  - "This link works only once."
  - "If you didn't ask for this, you can safely ignore this email."
  - the fallback-link line
  - the two reason lines
  - the corporate billing reason
  - the sent-automatically line

### 4. Link tokens (`email_link_tokens`)
- A token is 32 random bytes, url-safe base64 without padding
  (43 characters). Only its SHA-256 is stored, and the column is unique.
- Pure rules live in `Palee.Email.Domain.LinkTokenPolicy`. They cover
  generate/hash, `expired?/2`, `usable?/2`, `check/2` and the lifetimes
  below.
- `consume` is one `UPDATE … WHERE used_at IS NULL AND expires_at > now
  RETURNING`, so of several racing requests exactly one gets the token.
- Purposes, default lifetimes, and whether a new token deletes the login's
  older **unused** ones:

| purpose | TTL | new link replaces older unused |
|---|---|---|
| `verify_email` | 48 h | yes |
| `email_change` | 24 h | yes |
| `email_change_revert` | 7 days | **no**, every change keeps its revert link |
| `password_reset` | 1 h | yes |
| `account_deletion` | 24 h | yes |
| `sign_out_everywhere` | 7 days | **no** since ADR-208, every security notice keeps its own link |

Purposes are accepted as atoms or strings. An unknown purpose raises
`ArgumentError` on `issue` and returns `{:error, :invalid}` elsewhere. A
token of another purpose is `:invalid`. A new purpose is one line in the
policy; no migration is needed, because the check constraint only checks
the shape.

### 5. Budgets and throttles (`Palee.Email.Domain.SendingPolicy`)
- **Per recipient and kind** (rolling 24 h): `max_per_day` and
  `min_interval_seconds`. A template's `throttle/0` sets its own values;
  otherwise the category default applies:
  - `security`: 60 s and 10 a day
  - `account`: 60 s and 10 a day
  - `transactional`: 0 s and 20 a day

  When the limit is hit, enqueue returns `{:error, :throttled}`. Failed and
  suppressed messages do not count toward the limit.
- **Global daily budget** (per UTC day, counted from `sent_at`):
  - Non-security mail sends while fewer than `EMAIL_DAILY_BUDGET` emails
    (default 280) have been sent that day. Past the budget it is
    **deferred**: the row becomes `deferred` with `scheduled_at` set to the
    next UTC midnight plus 1 minute, and the job is scheduled or snoozed to
    that time. It is never dropped.
  - `security` mail keeps sending until `EMAIL_DAILY_HARD_CAP` (default
    295). Past the cap, `enqueue` returns `{:error, :over_budget}`,
    because a reset link that arrives tomorrow is useless. Security mail
    that is already queued is deferred instead.
  - Both settings are runtime env (`config :palee, :email_budget`). The
    worker checks the budget again just before sending. With 2 concurrent
    deliveries the budget can overshoot by at most 1. The cap stays under
    Brevo's 300.

### 6. Suppression (`email_suppressions`)
- The primary key is `Palee.Organizations.Domain.InvitationEmail.digest/1`
  of the address. `reason` is `bounce`, `complaint` or `manual`.
  Suppressing an address again updates the reason.
- `enqueue` refuses a suppressed address with `{:error, :suppressed}`. The
  worker marks an address suppressed after enqueue as `suppressed` and
  sends nothing.
- A later provider webhook calls `Palee.Email.suppress/2`.

### 7. Demo gate (ADR-184)
`enqueue` with `organization_id:` and category `transactional` calls
`Organizations.go_live(org, :send_outside)`. It returns
`{:error, :not_live}` while the business is in demo mode or unknown.
`security` and `account` mail is the platform's own mail, not the
business's, so it always goes.

### 8. Existing emails
- **Corporate invoices** now go through the outbox as kinds
  `:corporate_invoice_issued` and `:corporate_invoice_reminder`.
  - They keep the `corporate_invoices` gettext domain and the gym's
    default locale, now inside the shared layout.
  - The daily run is idempotent: the key is `corporate_invoice:<id>:issued`
    for the issued email and `corporate_invoice:<id>:reminder:<date>` for a
    reminder. An admin's manual resend has no key.
  - `:not_live` and `:invalid_address` map back to the run's existing
    errors.
  - `CorporateInvoiceEmail.build/3` still returns a `Swoosh.Email` for the
    mailer tests.
- **Owner invitation** is unchanged and still synchronous. It moves in a
  later change, with key `owner_invitation:<invitation id>`.

### 9. Testing (`Palee.EmailCase`, test/support/email_case.ex)
- In tests Oban is not started. Rows and their jobs are written to the
  sandbox and nothing is sent until the test asks. The Swoosh adapter is
  `Swoosh.Adapters.Test`, and the budget is 100 000.
- `import Palee.EmailCase` (or `use Palee.EmailCase`) gives:
  - `assert_email_enqueued(filters)`: exactly one match, returned with its
    decrypted `:text` and `:html`
  - `refute_email_enqueued(filters)`
  - `enqueued_emails(filters \\ [])`
  - `deliver_enqueued_emails(now \\ utc_now)`: runs the worker for every
    queued or deferred message, returns how many were sent, and makes
    `Swoosh.TestAssertions.assert_email_sent/1` work
  - `with_bodies(message)`
- Filters: `kind`, `to`, `status`, `category`, `organization_id`,
  `user_id`, `login_id`, `idempotency_key`, and `subject`/`text`/`html`
  (a substring or a regex).
- Worker unit tests: `use Oban.Testing, repo: Palee.Repo` and
  `perform_job(Palee.Workers.DeliverEmailJob, %{"message_id" => id})`.
- `:sample_notice` (`Palee.TestSupport.SampleEmail`) is a test-only kind.

## Rationale
- An outbox row written in the caller's transaction gives at-least-once
  delivery with no dual-write gap. The idempotency key and the
  sent-status check bring that down to effectively once.
- Rendering at enqueue time means the job needs no serialised assigns and
  the email is fixed when the event happens. Encrypting the body and
  clearing it after sending limits how long raw link tokens stay readable.
- A registry module plus one template module per kind keeps the work of
  nine parallel feature changes to an append-only line each.

## Alternatives Considered
- **Oban job args carrying the assigns, rendered at send time.** Raw
  tokens would sit in `oban_jobs` in plaintext, and the email would change
  if data changed before sending. Rejected.
- **`Oban.insert/3` with Oban's unique jobs instead of an idempotency
  column.** Uniqueness on args is time-boxed and can't list statuses. The
  outbox inserts the job changeset with `Repo.insert` in the same
  transaction, which also works in tests where Oban is not started. The
  stager notifies the queue of available jobs.
- **Phoenix.Swoosh / HEEx email templates.** That adds a dependency and a
  second templating style. Plain functions with escaping components are
  enough for transactional mail.
- **Dropping over-budget mail.** It loses invoices and confirmations.
  Deferring keeps them.

## Consequences
- `email_messages`, `email_link_tokens` and `email_suppressions` are
  platform tables without RLS, like ADR-187's password recovery tables.
  `email_messages` is classified as platform-administered in the tenancy
  audit. It is also not tenant data for ADR-117's export and purge: a
  business purge nils its `organization_id`, and the bodies are already
  cleared. The send log (addresses and subjects) therefore outlives the
  business.
- `Palee.Email` reads `Organizations.go_live/2` and the
  `InvitationEmail.digest/1` pure function.
- Follow-up work:
  - A retention sweep for old `email_messages` and spent link tokens.
  - The provider bounce/complaint webhook that calls `suppress/2`.
  - Moving the owner invitation onto the outbox.
  - An admin view of delivery status.
- `TelemetryLogReporter` no longer crashes on a struct tag (Oban's failed
  job `reason`), which every failed job used to trigger.

## Implementation Notes
- Code:
  - context: `lib/palee/email.ex`
  - commands: `lib/palee/email/commands/{enqueue_email,deliver_email}.ex`
  - domain: `lib/palee/email/domain/{address,sending_policy,delivery_policy,link_token_policy}.ex`
  - ports: `lib/palee/email/ports/{message_store,link_token_store,sender}.ex`
  - adapters: `lib/palee/infrastructure/email/{ecto_message_store,ecto_link_token_store,swoosh_sender}.ex`
  - worker: `lib/palee/workers/deliver_email_job.ex`
  - migration: `priv/repo/migrations/20261224100000_transactional_email_outbox.exs`
- Adapters are chosen in config: `:email_message_store`,
  `:email_link_token_store`, `:email_sender`.
- Greek and the other locales use the formal register, matching the
  existing `corporate_invoices` and `notifications` translations. Business
  names are quoted (« », „ “) wherever grammatical gender would otherwise
  leak into the sentence.
