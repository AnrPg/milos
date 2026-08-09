# Handoff: getting `mix precommit` (apps/api) green on a truly fresh DB

## Status: DONE

All work below is complete and committed. `mix precommit` — plus `mix hex.audit` and
the migrate/rollback/migrate cycle — passes cleanly (677 tests, 0 failures) against a
genuinely fresh, from-scratch-migrated database, verified twice on two separate
freshly-created databases. This file is kept as a record of what was found and fixed;
nothing further is required unless new failures show up on a future fresh-DB run.

## Why this document exists

The user asked me to fix the crashing "Verify API" precommit CI step. I fixed the
originally-scoped 240 test failures first. While replicating the full CI job locally
I discovered the local Postgres container I'd been validating against had **drifted
schema state** that doesn't match what a genuinely fresh `postgres:16-alpine`
container (like real GitHub Actions CI uses) would have. Testing against a truly
fresh, from-scratch-migrated database surfaced a much larger, **pre-existing** set of
77 failures — unrelated to the originally-scoped work — caused by an earlier tenancy
migration (`fix(tenancy): remove legacy tenant defaults from T4 foundation — fail
unscoped inserts`, commit `e3c8ae5`, and siblings) whose fallout across the wider test
suite (and in a few cases, production code) was never fully addressed, plus one broken
piece of shared RLS test infrastructure. All of that is now fixed too.

## How to reproduce/re-verify (always test against a FRESH database)

```bash
cd apps/api
docker exec milos-postgres-1 psql -U postgres -c "DROP DATABASE IF EXISTS milos_training_test_fresh;"
docker exec milos-postgres-1 psql -U postgres -c "CREATE DATABASE milos_training_test_fresh OWNER postgres;"
export DB_HOST=localhost DB_NAME=milos_training_test_fresh DB_PASSWORD=postgres DB_USER=postgres DB_PORT=15435
MIX_ENV=test mix ecto.migrate
MIX_ENV=test mix precommit
mix hex.audit
MIX_ENV=test mix ecto.rollback --step 1 && MIX_ENV=test mix ecto.migrate
```

Do NOT validate against the shared `milos_training_test` dev database on the same
container without recreating it fresh first — it accumulates schema/role state from
manual `mix ecto.migrate`/`ecto.rollback` invocations across sessions that doesn't
represent what CI's Postgres service container starts with.

## Root causes found and fixed

1. **`test/support/fixtures.ex` `workout_fixture/2` never established tenant
   context.** Unlike its siblings (`class_type_fixture`, `slot_fixture`), it called
   the fully unscoped `Workouts.create_workout/2`. Worked by accident on a DB with a
   stale `organization_id` DEFAULT; fails NOT NULL on a fresh one (fail-closed by
   design per e3c8ae5). **Fixed**: resolves a tenant context in priority order —
   explicit `attrs.tenant_context`, then the ambient RLS session GUC if a test has
   already set one (`app.organization_id`), then the legacy org as a last resort —
   and calls the scoped `Workouts.create_workout/3`. The ambient-session check matters:
   many tests set `app.organization_id`/`app.user_id` directly before calling this
   fixture rather than threading a context struct, and a naive "always default to
   legacy" fallback broke those (org mismatch downstream). See
   `test/support/fixtures.ex` `ambient_tenant_context/0`.

2. **`test/support/rls_case.ex` self-provisioning ran through the Ecto sandbox.**
   `MilosTraining.RLSCase` (used by every `*/rls_enforcement_test.exs` and
   `root_tables_rls_test.exs`, 17 tests total) self-provisions a non-superuser
   Postgres role so it can prove RLS policies actually block things. The
   provisioning (`CREATE ROLE`/`GRANT`) was issued through `MilosTraining.Repo`,
   wrapped in a per-test sandbox transaction that rolls back — so the grants never
   durably existed on a fresh DB, and the real RLS-testing connection got `permission
   denied`. **Fixed**: provisioning now goes through a dedicated, non-sandboxed
   `Postgrex` connection, matching the pattern the file's own cleanup already used.
   This was a genuine pre-existing infrastructure bug, unrelated to anything else in
   this session — it would have failed in true CI on any run.

3. **Several genuine production bugs**, all variations on "a write path had no way to
   receive tenant context, so it silently depended on the now-removed DB default":
   - `UpdateAdminSettings.maybe_update_gamification/1` silently dropped the `context`
     it was given, so **every admin gamification-settings update (theme, weekly
     target, leaderboard toggle) crashed with a 500** in production. Fixed by adding
     `Gamification.with_tenant_context/2` (mirroring the pattern already used by
     `Workouts`/`Messaging`) and threading it through.
   - `AdminChallengeController#create`/`#index` never had any tenant scope at all —
     **creating or listing seasonal challenges crashed/returned nothing** in
     production. Fixed by wrapping both actions in `Gamification.with_tenant_context/2`
     using `conn.assigns.tenant_context`.
   - `RecordAnalyticsEvent.call_unsafe/2` claimed to be best-effort ("never blocks the
     caller") but only caught returned `{:error, _}` tuples, not raised exceptions —
     a DB-level NOT NULL failure recording an analytics event (e.g. from
     `MarkNotificationsRead`) **crashed the primary action it was piggybacking on**.
     Fixed with a `rescue` clause so it's actually best-effort.
   - `MarkNotificationClicked`/`notification_click_events.organization_id` — the
     code has always explicitly allowed a nil organization_id here on purpose (F-28:
     the notification inbox spans every org a member belongs to, so a click on a
     cross-org notification is legitimate, not an error) — but the DB column was
     `NOT NULL`. New migration
     `20260809140000_allow_null_organization_on_notification_click_events.exs`
     relaxes the constraint to match what the application has always intended.

4. **Several test files** had leftover direct/unscoped calls to context-aware
   application commands (`Gamification.create_seasonal_challenge/2`,
   `CreateDraftWorkout.call/1`, `Workouts.create_folder/2`,
   `Workouts.create_workout/2`, etc.) or session-GUC ordering bugs (setting
   `app.organization_id` *after* the call that needed it). Each was fixed locally —
   either by wrapping the call in `with_tenant_context/2`, passing a resolved
   context explicitly, or reordering the session-setup vs. the call. See the git log
   for the individual commits (all today, all prefixed `fix(...)`/`test(...)`).

5. **`t4_ownership_foundation_test.exs`** literally asserted the *old, now-retired*
   behavior — that a completely unscoped raw-SQL insert lands in the legacy org via
   an implicit DB default. That's exactly what e3c8ae5 intentionally removed.
   Rewrote the test to assert the *new* intended behavior instead: the legacy org is
   an ordinary organization that a write can be explicitly scoped to (via session GUC
   for triggered tables, or an explicit `organization_id` value for `class_types`,
   which has no BEFORE INSERT tenant-context trigger).

## Verification performed

- Fresh DB #1 (`milos_training_test_fresh`, migrated from scratch): `mix test` →
  677/0 (after all fixes above), `mix precommit` → clean, `mix hex.audit` → clean,
  `ecto.rollback --step 1 && ecto.migrate` → clean, then `mix test` again → 677/0.
- Fresh DB #2 (`milos_training_test_verify`, migrated from scratch, independent of
  DB #1): same full sequence, same clean result — rules out DB #1 having picked up
  incidental state from the debugging session.
- Both temporary databases were dropped after verification.

## Commits

All work is committed on `main` (originally-scoped fixes: 13 commits; this larger
fresh-DB cleanup: additional commits following, each prefixed `fix:`/`test:` with a
descriptive body). See `git log` for the full list — no further action needed here.
