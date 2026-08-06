# Test and Verification Strategy

Date: 2026-08-05

## Commands run during this audit (all read-only / standard dev-loop; no production access, no destructive operations)

```bash
# Local dev infra started for this audit only (postgres, redis, meilisearch, minio)
docker compose up -d postgres redis meilisearch minio

# Test DB creation/migration against the local container (port 15434)
DB_PORT=15434 MIX_ENV=test mix ecto.create
DB_PORT=15434 MIX_ENV=test mix ecto.migrate

# Tenancy audit task (read-only queries against the local dev DB, port 15434)
DB_PORT=15434 mix milos.tenancy.audit
# Result: all 44 tables in the script's checked list report
# unmapped=0 rls=true force=true; ready_for_full_enforcement?/1 passes.
# See 04-findings.md F-13 for why this passing is weaker evidence than it looks.

# Hexagonal architecture boundary gate
DB_PORT=15434 mix milos.architecture
# Result: "Hexagonal architecture boundaries are clean"
# See F-13 — this only checks two Scheduling files by substring match.

# Tenancy/organizations/invitation/isolation test suites
DB_PORT=15434 mix test \
  test/milos_training/organizations/ \
  test/milos_training/analytics/tenant_isolation_test.exs \
  test/milos_training/execution/owner_isolation_test.exs \
  test/milos_training/feedback/tenant_isolation_test.exs \
  test/milos_training/finance/tenant_isolation_test.exs \
  test/milos_training/gamification/tenant_isolation_test.exs \
  test/milos_training/messaging/tenant_isolation_test.exs \
  test/milos_training/scheduling/tenant_isolation_test.exs \
  test/milos_training/workouts/tenant_isolation_test.exs \
  test/milos_training_web/channels/user_socket_tenant_context_test.exs \
  test/milos_training_web/controllers/organization_access_controller_test.exs \
  test/milos_training_web/controllers/platform_organization_controller_test.exs
# Result: 51 tests, 0 failures.
# CRITICAL CAVEAT: this test run, like all runs in this codebase's dev/test
# config, connected as the Postgres superuser (config/test.exs default
# DB_USER=postgres). Per F-07, a superuser unconditionally bypasses RLS.
# These 51 passing tests prove the application-layer `where` clauses (where
# they exist) are correct; they do NOT prove RLS enforcement, because RLS was
# never actually active on these connections. Treat "0 failures" as partial
# evidence, not proof of isolation, exactly as the audit brief's working
# constraints require.

# Live RLS/role verification queries (read-only SELECT against pg_roles,
# pg_class, pg_policies on the local dev database)
# — executed by the delegated research pass for task 2/5, see 04-findings.md
# F-07/F-13 for the exact queries and results.
```

## Assessment of existing test quality (not just pass/fail)

- **Good pattern, present but under-applied:** `t4_ownership_foundation_test.exs`
  and the per-context `tenant_isolation_test.exs` files correctly seed two
  organizations and assert cross-tenant reads/writes are rejected — this is
  the right shape of test. It exists for Analytics, Execution (owner-scoped),
  Feedback, Finance, Gamification, Messaging, Scheduling, Workouts.
- **Missing entirely:** Notifications, Wellbeing, Coaching (F-14) — despite
  `docs/technical_debt.md` TD-038 claiming "two-tenant tests" for
  Notifications and Wellbeing specifically.
- **Structurally unable to prove what it claims:** every isolation test in the
  suite runs under the Postgres superuser (F-07) — none of them can be
  evidence that RLS itself blocks a cross-tenant query, only that the
  application-layer predicate (where present) does. Finance's underlying
  store has almost no application-layer predicates (F-05), meaning
  `finance/tenant_isolation_test.exs` passing is currently the weakest signal
  in the whole suite despite testing the highest-stakes domain.
- **Concurrency test that doesn't test concurrency:** the invitation-redemption
  race test (`organizations_test.exs` "concurrent redemption consumes an
  invitation exactly once") spawns two `Task.async` processes under a shared
  Ecto Sandbox connection, which serializes them onto one physical DB
  connection rather than exercising genuine concurrent-connection lock
  contention. The application-level outcome it asserts (exactly one success)
  is still correct and valuable, but it doesn't prove the `FOR UPDATE` lock
  resolves a true concurrent race under a real connection pool.
- **Test-fixture blind spot:** `test/support/fixtures.ex`'s `user_fixture/1`/
  `admin_fixture/1` both default every test subject into the *same* legacy
  organization membership. Any test that doesn't explicitly provision a
  second organization exercises exactly one tenant, which — combined with the
  RLS COALESCE-to-legacy fallback (F-04) — means a query missing an explicit
  `organization_id` predicate can look identical to a correctly-scoped one in
  that test's output.

## Missing high-value tests, prioritized by risk

### Cross-tenant tests (highest priority — several map directly to confirmed findings)

| # | Test | Layer | Setup | Action | Expected result | Invariant protected |
|---|---|---|---|---|---|---|
| 1 | Finance MV leak regression | Controller integration | Seed `finance_aggregates` rows for Org A and Org B | Org A admin calls `GET /api/admin/finance/summary` | Response contains only Org A's rows | F-21 |
| 2 | Leaderboard MV leak regression | Controller integration | Seed `weekly_leaderboard` for Org A and Org B; user with no membership anywhere | Call `GET /challenges/:id/leaderboard` | Either 403 (no membership) or only caller's own org's rows | F-22 |
| 3 | Execution admin_mode cross-tenant IDOR | Controller integration | Global-role-admin account with zero Org X membership; execution belonging to an Org X user | `GET /api/executions/:id` for that execution | 403/404, not the execution data | F-23 |
| 4 | Legacy admin-route header trust | Controller integration | Org-A-only admin session | `GET /api/admin/users` with `x-organization-slug: org-b` header, no Org B membership | 403/404 | F-01 |
| 5 | Execution provenance forgery | Command/application | Member with zero Org X membership | `POST /api/executions` `{source: "self_selected", organization_id: "<org-x>"}` | Persisted `organization_id` is not Org X (nulled or rejected) | F-03 |
| 6 | Admin invitation role-ceiling | Command | Org admin (non-owner) | Issue invitation with `role: "owner"` | Rejected | F-06 |
| 7 | Invitation email binding | Application | Invitation issued with `intended_email` | Redeem from an authenticated account with a different email | Product's chosen policy enforced (currently: succeeds — flag as a decision point) | F-10 |
| 8 | Cross-tenant background job | Worker | Two orgs with overdue invoices | Run `mark_overdue_invoices` job | Both orgs' invoices transition, not just legacy | F-24 |
| 9 | Messaging cross-tenant functional check | Application | Non-legacy org member creates a thread | Read the thread back | Thread is found and readable (currently likely fails) | F-25 |
| 10 | Export/report cross-tenant check | Application | Two orgs with finance data | Generate a finance report/export for Org A | No Org B rows appear | General IDOR/BOLA category from audit brief |

### Legacy-gym tests

| # | Test | Setup | Action | Expected result |
|---|---|---|---|---|
| 11 | No-tenant request does not fall back to legacy | Authenticated user, no path slug, no header | `GET /api/admin/*` route with `x-organization-slug` header absent | 400/404 tenant-ambiguous, not legacy-org data (currently fails — see F-01) |
| 12 | RLS with unset session context returns zero rows | Raw transaction, no `app.organization_id` set | `SELECT` from any enforce-stage tenant table | Zero rows, not legacy-org rows (currently fails — see F-04) |
| 13 | First-created org has no special privilege | Two orgs provisioned in sequence | Compare available operations for org 1 vs org 2 | Identical (currently true for provisioning; false for the fallback-dependent surfaces above) |
| 14 | New org gets full functionality parity | New org, no legacy-arity call sites migrated for it | Exercise every Scheduling/Workouts operation | All succeed (currently: legacy-arity call sites fail for new orgs — F-18) |

### Role tests

| # | Test | Setup | Action | Expected result |
|---|---|---|---|---|
| 15 | Only SaaS owner assigns global roles | Non-platform-owner account | Attempt any path to `platform_owners` grant | No HTTP path exists (confirmed already — add a regression test asserting no such route exists) |
| 16 | Gym admin cannot assign roles ≥ their own | Org admin | Issue `owner`/`admin` invitation | Rejected (currently fails for `owner` — F-06; untested for `admin`-to-`admin`, a product decision) |
| 17 | Gym admin cannot assign roles in another gym | Org A admin | Issue invitation scoped to Org B | Rejected (org_id is server-derived from context — already correct, add regression test) |
| 18 | Revoking a role invalidates access | Active member | Revoke membership (once F-08/F-11's command exists), then request tenant-scoped endpoint | Rejected — **cannot be tested today; command doesn't exist (F-11)** |
| 19 | Global admin not silently SaaS owner | Account with global `role: admin` | Attempt platform-owner-gated endpoint | Rejected (confirmed correct — add regression test) |

### Invitation tests

| # | Test | Setup | Action | Expected result |
|---|---|---|---|---|
| 20 | Tampered role field ignored | N/A — role is server-normalized from a fixed enum, not free text | Send `role: "platform_owner"` | Rejected by `normalize_role/1`'s enum check (confirmed already enforced — add regression test) |
| 21 | Expired invitation rejected | Invitation past `expires_at` | Attempt redemption | Rejected — confirmed by `InvitationPolicy.redeemable?/2`, add explicit regression test if not already covered |
| 22 | Genuinely concurrent redemption | Two real DB connections (not shared sandbox) | Redeem the same token from both simultaneously | Exactly one succeeds — needs a non-sandboxed or `Ecto.Adapters.SQL.Sandbox.mode(:auto)` test to actually exercise this (current test doesn't — see quality note above) |
| 23 | Partial failure atomicity | Force a failure mid-redemption (e.g. membership insert conflict) | Attempt redemption | No orphaned account/membership/invitation-state |

## Recommended test-infrastructure change (prerequisite for several tests above)

Add a CI job variant that runs at least the isolation-test subset against a
**non-superuser, non-BYPASSRLS** database role (mirroring `milos_runtime`),
so RLS itself is exercised by automation for the first time. Without this,
tests 1–4, 8, 9, and 12 above cannot actually distinguish "RLS caught it" from
"the test never exercised RLS at all" — see F-07.
