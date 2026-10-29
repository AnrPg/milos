# ADR-273: Fiscal «Συνδέσεις», «Δοκιμή σύνδεσης» and Palee-managed setup
Date: 2026-10-29
Status: Accepted

## Context
A box's fiscal connections (myDATA and the AADE registry in Greece, fiskaly
SIGN DE/AT/FR for the till, fiskaly E-INVOICE for Peppol in Belgium) had
API endpoints (ADR-243, ADR-250, ADR-251, ADR-265, ADR-266) but no screen:
«Στοιχεία τιμολόγησης» only showed a read-only «Σύνδεση με myDATA» card.
A wrong key showed up only when the first document failed, as free provider
text in `last_error`. For the pilot, the product owner chose mockup p3,
alternative A (`v3-mockups-pilot-gaps.html`), and decided:

- every connection gets a «Δοκιμή σύνδεσης», behind the ports (sandbox
  adapters included), run on save, on demand and periodically (about every
  3 months, sooner after failures);
- a failure marks the connection invalid with a stable error code that the
  screens turn into a plain message, and notifies the owner;
- the AADE registry check looks up the business's own ΑΦΜ and respects
  AADE's quota;
- the owner sees the test environment under «Προχωρημένα»;
- fiskaly HUB setup is done by the owner or by the Palee team: the vendor
  console can fill or replace a box's credentials (audited), a per-box flag
  records who manages them, and the owner then sees «Τη σύνδεση τη
  διαχειρίζεται η ομάδα Palee»;
- small API fixes: the registry connection returns `username` (not
  `user_id`), the Peppol `webhook_url` is no longer handed out, the till
  connection's description includes SIGN FR.

Secrets are never returned, logged, journaled or exported.

## Decision
1. **A check port per provider.** `AuthorityGateway`, `CashRegisterSecurity`
   and `EInvoiceNetwork` gain `check/1 :: {:ok, map} | {:error, term}`.
   Nothing is sent or signed:
   - myDATA: `GET RequestTransmittedDocs?mark=999999999999999` with the
     business's user and key (200 = ok, 401/403 = refused);
   - AADE registry: a look-up of the business's own ΑΦΜ (one call of its
     quota);
   - fiskaly SIGN DE: authenticate, read the TSS and its client (a TSS not
     `INITIALIZED` is `unit_not_ready`); SIGN AT: read the signature unit and
     cash register; SIGN FR and E-INVOICE: token, then the System's VAT
     table;
   - sandbox adapters answer ok.
2. **Pure rules in `Fiscal.Domain.ConnectionCheckPolicy`**: the kinds a
   country asks for (in screen order), the outcome of a port's answer
   (`:ok`, `{:invalid, code}`, `{:unreachable, code}`), the columns to
   write and the next check:
   - ok → next in 90 days; an invalid connection becomes active again and
     its waiting documents are woken;
   - invalid → status `invalid`, retried after 1 h, 6 h, 1 day, 3 days,
     then weekly;
   - unreachable (network, outage, AADE quota, or the business's own ΑΦΜ
     missing or unknown to the registry) → status unchanged, retried after
     15 min, 1 h, 6 h, then daily.
   A staff member's check is refused (`check_too_soon`, 429) within 30 s of
   the last one, 10 min for the registry (its quota); the endpoint is also
   rate-limited (10 a minute).
3. **Stable error codes replace provider text on screen**:
   `credentials_rejected`, `credentials_missing`, `unit_not_found`,
   `unit_not_ready`, `system_not_found`, `tax_id_missing`,
   `tax_id_not_found`, `siren_missing`, `limit_reached`, `unreachable`,
   `provisioning_failed`, `provider_retired`. Connections store
   `error_code`, `checked_at`, `next_check_at`, `check_failures` and
   `updated_by_platform` (migration `20270312000000`). `last_error` stays
   in the table for support but is no longer returned.
4. **When checks run.** Every save checks synchronously and answers
   `{connection, check}`; `POST /admin/fiscal/connections/:kind/check` on
   demand; `CheckFiscalConnectionsJob` hourly (`43 * * * *`, queue
   `fiscal`) checks what is due. A scheduled check (or a provider refusing
   while working) that makes a connection newly invalid notifies the staff
   who manage billing (`fiscal_connection_failed`, one a day per person and
   connection, link `/admin/settings/billing?connection=<kind>`) through the
   `ConnectionNotifier` port.
5. **One overview**: `GET /admin/fiscal/connections` → `{country, kinds,
   managed_by, connections}`, each connection as its own endpoint returns
   it plus `error_code`, `checked_at`, `updated_by_platform` and
   `updated_by_name`. Saving stays on each connection's endpoint.
6. **Who manages the connections**: table `fiscal_connection_settings`
   (`managed_by` `owner` | `palee`, forced RLS). While `palee`, the box's
   own saves are refused (`fiscal_connections_managed_by_palee`, 403);
   «Δοκιμή σύνδεσης» stays open to staff. Vendor endpoints under
   `/api/platform/organizations/:id/fiscal-connections` (show, `managed-by`,
   save `:kind`, check `:kind`) reuse the owner's save use cases; every
   change is written to `organization_provisioning_events`
   (`fiscal_connections_manager_changed`, `fiscal_connection_saved` with
   connection, environment and whether secrets were replaced, never their
   values) and the fiscal journal entry carries `by_platform`.
7. **Screen (mockup p3 A)**: a «Συνδέσεις» card in «Στοιχεία τιμολόγησης»
   once a country is chosen, one row per kind with its status; a row opens
   a side panel with one «Αποθήκευση»; a saved secret shows only
   «Αποθηκευμένο» and «Αντικατάσταση»; «Παραγωγή» / «Δοκιμή» sit under
   «Προχωρημένα» («Δοκιμή» is the provider's test system once credentials
   are given, the sandbox before; the registry only has its sandbox);
   errors from the save or the check stay inside the panel, under the field
   they concern. The vendor console opens the same panel from the
   organization's row, with the `managed_by` choice.

## Rationale
- Checking behind the ports keeps the providers' knowledge in the adapters
  and lets the sandbox and tests run the same flow.
- A transient failure must not mark a connection invalid: that would hold
  documents back for a provider's hiccup. Only a definite refusal does.
- Own-ΑΦΜ problems say nothing about the registry credentials (look-ups of
  other ΑΦΜ keep working), so they are reported but do not invalidate.
- Stable codes are translatable and safe; provider text may leak details
  and cannot be localized.
- A per-box flag is simpler than per-connection ownership and matches how
  the pilot boxes are onboarded (one fiskaly account per box).

## Alternatives Considered
- **Asynchronous check after save** (job + polling): the screen would need
  a second round trip to show a refused key; the providers usually answer
  within a second or two, so the save waits for it.
- **Mockup alternatives B/C** (own section in Settings, a wizard): rejected
  by the product owner; the connections exist to issue legal documents, which
  already live in «Στοιχεία τιμολόγησης».
- **Hiding the test environment from owners** (Palee support only): the
  owner decided to show it under «Προχωρημένα».
- **Keeping `webhook_url`**: fiskaly E-INVOICE sends no webhooks; the
  secret URL had no use for the owner and was a credential on screen.

## Consequences
- Every save answers `{connection, check}` instead of `{connection}`; the
  registry connection's field is `username`; `last_error` and the Peppol
  `webhook_url` are gone from responses (OpenAPI and `schema.ts`
  regenerated).
- An hourly job calls the providers for due connections (about one call per
  connection every 3 months when healthy); the registry check spends one
  AADE look-up each time.
- New notification type `fiscal_connection_failed` (12 locales).
- Tests: `config :palee, :mydata` now points at the `Palee.FiscalHttp` test
  plug, so a test saving a myDATA test or production connection must stub
  it.

## Implementation Notes
- `Fiscal.Connections` (domain) runs a check and records it with
  `update_connection_check/3` on the three stores (a whitelisted
  `update_all`, `updated_at` untouched); `Application.Fiscal.FiscalConnections`
  adds names, the guard and the vendor use cases.
- A till connection still `provisioning` keeps that status after a check;
  only saving finishes the device. Provisioning failures now set
  `error_code` (`credentials_rejected`, `siren_missing`,
  `provisioning_failed`).
- Unauthorized answers while working (myDATA transmission, registry
  look-up, fiskaly signing) go through `Connections.mark_invalid/5`, which
  notifies on the transition to invalid.
- The web «Συνδέσεις» card replaces the old `NextStepCard`; its brand names
  live in `connections-model.ts`, never in the messages.
