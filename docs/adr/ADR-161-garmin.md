# ADR-161: Garmin (OAuth, push ingest, matching and the devices row)
Date: 2026-10-21
Status: Accepted (board 16 answered: the recommended option A for Q1–Q7)

## Context
Plan §5 P2-M13 connects Garmin: OAuth, push ingest, dedupe and the status of
the Garmin row on «Συνδεδεμένες συσκευές». ADR-159 left `source` and
`external_id` on wellness rows for devices, ADR-158 left a `source` on body
snapshots, and Συνδεδεμένες συσκευές (ADR-140 era) listed Garmin as
«Σύντομα». Garmin's Health and Activity APIs push summaries (or a ping with
a callback URL) to the partner; there is no polling. Vision §4 binds the
privacy rules: imports are the member's, private until they choose.

## Decision
1. **A Devices bounded context.** `device_connections` (one per user and
   provider; `pending|active|error|revoked`; tokens and the PKCE verifier
   AES-256-GCM encrypted at rest; `sync_prefs` activities/sleep/weight/
   resting_hr, all on by default; `backfill_days` 0|30|90 with progress),
   `device_imports` (one row per received summary, unique per user,
   provider, kind and provider id, so pushes are idempotent),
   `device_activities` (the workout's metrics) and `daily_stats` (resting
   heart rate per local day and source). All personal, owner RLS.
2. **Ports.** `GarminClient` (authorize URL, code exchange, refresh, user id,
   fetch callback, backfill, deregister, verify push) with an HTTP adapter on
   Req and a fake for tests; `DeviceStore` (Ecto) and `SyncQueue` (Oban).
   Without `GARMIN_CLIENT_ID`/`GARMIN_CLIENT_SECRET` the row stays «Σύντομα»
   (`capability: not_configured`) and every Garmin route answers 503.
3. **Connect (Q1 A).** `POST /api/me/devices/garmin/connect` takes the sync
   choices, the backfill window and, if not yet given, M10's `health_data`
   consent; it returns Garmin's OAuth 2.0 PKCE authorize URL. The callback
   finds the connection by the hash of `state` (definer lookup, single use),
   exchanges the code, reads Garmin's user id and redirects to
   `/me/devices?garmin=connected|error`. Backfill is requested in 10-day
   windows by a job that records progress.
4. **Push ingest.** `/api/integrations/garmin/push` and `/deregistration` are
   public, rate limited and verified by the `garmin-client-id` header (plus
   `?token=` when `GARMIN_PUSH_TOKEN` is set). Each batch is grouped by
   Garmin user and queued; ping callbacks are fetched only from
   `https://apis.garmin.com`. Garmin only sends data the member allowed.
5. **Matching (Q2 A).** A watch workout merges into an existing entry
   (training log, completed execution, or an approved/attended class not yet
   logged) when it starts within ±15 minutes and overlaps at least 50%. One
   candidate merges automatically (metrics stay in `device_activities` and
   show on that entry as `device`); two or more wait as
   `needs_confirmation` for the member (`GET .../garmin/pending`,
   `POST /api/me/device-imports/:id/confirm` with `target_id` or `as_new`);
   none becomes a journal entry of the new kind `device_activity`.
6. **Privacy (Q3 A).** Imports are `private`; a class match takes that gym's
   provenance so the member can widen it like any entry, and coaches read
   only through `palee_entry_visible_to_acting_coach`.
7. **Health data (Q4 A).** Sleep goes to Ευεξία rows (`source: garmin`) and a
   manual entry or correction always wins; weight becomes a body snapshot
   with `source: garmin`; resting HR lands in `daily_stats`. Without the
   `health_data` consent these are ignored; `sync_prefs` filters every kind.
8. **Status and errors (Q5 A).** Tokens are refreshed ahead of expiry every
   15 minutes; a refused grant or repeated failures move the connection to
   `error` and send one `device_sync_error` notification (12 locales) until
   it syncs again. The row shows last sync, backfill progress and
   `needs_reconnect`. «Συγχρονισμός τώρα» is limited to once every few
   minutes (`sync_too_soon`, 429).
9. **New imports badge (Q6 A).** `GET /api/me/devices/summary` counts
   imports since the member last looked; `POST .../summary/seen` clears it.
10. **Disconnect (Q7 A).** `DELETE /api/me/devices/garmin` deregisters at
    Garmin and revokes; `?delete_data=true` also deletes what came from
    Garmin and reports the counts. Garmin's deregistration push revokes too.
    Tenant purge removes gym-provenance device rows (ADR-117).

## Rationale
Keeping a device's metrics in their own table and attaching them to the
entry they match avoids duplicates in the journal while never overwriting
what the member or coach wrote. Imports as rows make every push idempotent
and auditable, and the pending state keeps a guess from ever merging the
wrong workout.

## Alternatives Considered
- Writing watch workouts straight into training logs: those need a gym, and
  a solo run has none.
- Merging on the closest candidate when several match: rejected; a wrong
  merge is worse than a question.
- Polling Garmin: not offered by the API and wasteful.

## Consequences
- New env vars: `GARMIN_CLIENT_ID`, `GARMIN_CLIENT_SECRET`, optional
  `GARMIN_REDIRECT_URI`, `GARMIN_PUSH_TOKEN` and `DATA_ENCRYPTION_KEY`
  (derived from `SECRET_KEY_BASE` when unset).
- The web screens (connect sheet, device card, pending question, resting HR
  in Πρόοδος) follow after the M13 UX conversation (§5a).

## Implementation Notes
- Migration `20261031100000_device_integrations`; definer functions for the
  sessionless paths (OAuth state, push lookup, refresh due, match
  candidates).
- `Infrastructure.Security.DataCipher` / `EncryptedBinary` hold the tokens.
