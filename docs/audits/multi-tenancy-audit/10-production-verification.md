# Production Verification Pass (2026-08-05)

This is a follow-up to the main audit (files `00`–`09`), performed after the
user provided access details for the live production deployment: Kubernetes
namespace `tenant-m4` on the Gata cluster, GitOps source at
`/home/rodochrousbisbiki/MyApps/deployed-milos/gitops`, live app at
`https://milos.4kq.net/`.

**Scope and method:** Read-only only. No `kubectl apply`/`delete`/`patch`, no
secret values were read or displayed, no destructive SQL. All database
queries were executed via `kubectl exec` into the running `milos-api` pod,
using `./bin/milos_training rpc '...'` to run `SELECT`-only statements through
the application's own `Ecto.Repo` connection — i.e., using exactly the
database role and connection the production application itself uses, with no
credentials ever displayed to or handled directly by the operator running
this audit. Explicit user approval was obtained before performing any
`kubectl exec` (per the user's instruction to "ask for interventions").
Access to raw Kubernetes `Secret` data was attempted once for informational
purposes (listing key names only, not values) and was correctly blocked by
the environment's own permission classifier; this was respected and not
retried or worked around.

## What this pass changed in the main audit

- **F-07 downgraded from "unknown, worst-case assumed" to "confirmed
  resolved" for production specifically.** Production's runtime database role
  is `app` (CloudNativePG-managed application-owner role), confirmed via live
  query to have `rolsuper = false` and `rolbypassrls = false`. No
  `milos-db-superuser` Kubernetes secret exists in the namespace at all. Both
  the `migrate` initContainer and the runtime `api` container in
  `milos-api.yaml` connect using the same non-superuser `milos-db-app`
  secret. **RLS is genuinely active for production traffic.** The dev/test/CI
  gap (tests never exercise RLS because they run as the `postgres` superuser)
  remains a fully valid finding on its own terms — it means a *regression* in
  RLS policy correctness would not be caught by CI — but it is no longer
  grounds to suspect production itself lacks RLS enforcement.
- **F-04 (RLS legacy-org COALESCE fallback) confirmed live in production**:
  40 policies reference `milos_legacy_organization_id`. However, the function
  currently resolves to `NULL` in production because it looks up the legacy
  organization by a hardcoded slug (`legacy-milos-training`) and production's
  sole organization has since had its slug changed to `milos-training`. This
  makes the fallback **accidentally inert right now** (fails closed to zero
  rows instead of silently exposing/misattributing to that org) — but it is
  fragile, unintentional, and will silently reactivate if any organization is
  ever created or renamed back to that exact slug (including via a routine,
  documented-as-safe re-run of `mix milos.organizations.ensure_legacy`). This
  must still be remediated per F-04's original recommendation (remove the
  fallback entirely) rather than relied upon.
- **Production is currently single-tenant**: exactly one organization
  (`milos-training`, status `active`), 5 total `users` rows, 3
  `organization_memberships`, 1 active `platform_owners` row. This is
  evidently a pre-commercial-launch or early-access deployment, consistent
  with the codebase's own runbook guidance not to provision a second
  independent tenant until T4–T6 enforcement fully passes. **Practical
  consequence:** the confirmed cross-tenant leaks (F-21, F-22, F-04) cannot
  yet have exposed a *second* tenant's data to anyone, because no second
  tenant exists. They remain fully live, confirmed defects in the deployed
  code that will activate with zero additional trigger the moment a second
  organization is provisioned — this audit's P0/P1 remediation priority is
  unchanged and should be treated as a hard prerequisite before any second
  tenant onboarding, commercial or otherwise.
- F-23 (Execution `admin_mode` cross-user IDOR) is **not** mitigated by the
  single-tenant state, since it is cross-*user* as well as cross-tenant — any
  of the 5 production accounts with a global `admin` role could already
  target any other production user's execution records. This was not
  actively tested against live data (no impersonation/exploitation was
  performed), but access-log review is recommended.
- Confirmed zero `organization_id IS NULL` rows across `finance_invoices`,
  `memberships`, `master_workouts`, `bookings`, `messaging_threads` — no
  writes have hit the broken/NULL-fallback path.
- `messaging_threads` and `finance_settings` both currently have 0 rows in
  production — consistent with (but not conclusive proof of) F-25's
  prediction that Messaging is non-functional for real tenant use, and
  meaning F-05's `get_finance_settings/0` gap has not yet manifested simply
  because no settings row has ever been created.

## Exact queries run (sanitized — no credentials, no row-level PII beyond aggregate counts)

```elixir
# Role privilege check
Ecto.Adapters.SQL.query!(MilosTraining.Repo,
  "SELECT current_user, (SELECT rolsuper FROM pg_roles WHERE rolname = current_user), (SELECT rolbypassrls FROM pg_roles WHERE rolname = current_user)", [])
# => [["app", false, false]]

# Legacy-org fallback policy count
Ecto.Adapters.SQL.query!(MilosTraining.Repo,
  "SELECT count(*) FROM pg_policy p WHERE pg_get_expr(p.polqual, p.polrelid) ILIKE $1 OR pg_get_expr(p.polwithcheck, p.polrelid) ILIKE $1",
  ["%milos_legacy_organization_id%"])
# => [[40]]

# Legacy-org fallback function live resolution
Ecto.Adapters.SQL.query!(MilosTraining.Repo, "SELECT milos_legacy_organization_id()", [])
# => [[nil]]

# Tenant/user/org counts
Ecto.Adapters.SQL.query!(MilosTraining.Repo, "SELECT slug, status FROM organizations", [])
# => [["milos-training", "active"]]
Ecto.Adapters.SQL.query!(MilosTraining.Repo, "SELECT count(*) FROM users", [])           # => [[5]]
Ecto.Adapters.SQL.query!(MilosTraining.Repo, "SELECT count(*) FROM organization_memberships", []) # => [[3]]
Ecto.Adapters.SQL.query!(MilosTraining.Repo, "SELECT count(*) FROM platform_owners WHERE status = $1", ["active"]) # => [[1]]

# Materialized view exposure size
Ecto.Adapters.SQL.query!(MilosTraining.Repo,
  "SELECT (SELECT count(DISTINCT organization_id) FROM finance_invoices), (SELECT count(*) FROM organizations), (SELECT count(*) FROM finance_aggregates), (SELECT count(*) FROM weekly_leaderboard)", [])
# => [[0, 1, 7, 0]]

# Unmapped-row check (F-04 blast-radius so far)
Ecto.Adapters.SQL.query!(MilosTraining.Repo,
  "SELECT (SELECT count(*) FROM finance_invoices WHERE organization_id IS NULL), (SELECT count(*) FROM memberships WHERE organization_id IS NULL), (SELECT count(*) FROM master_workouts WHERE organization_id IS NULL), (SELECT count(*) FROM bookings WHERE organization_id IS NULL), (SELECT count(*) FROM messaging_threads WHERE organization_id IS NULL)", [])
# => [[0, 0, 0, 0, 0]]

# Feature-usage sanity checks
Ecto.Adapters.SQL.query!(MilosTraining.Repo, "SELECT count(*) FROM messaging_threads", []) # => [[0]]
Ecto.Adapters.SQL.query!(MilosTraining.Repo, "SELECT count(*) FROM finance_settings", [])  # => [[0]]
```

## GitOps/Kubernetes configuration review (read-only)

- Namespace `tenant-m4`, reconciled by Flux from
  `src.4kq.net/client-milos-method/gitops` `main` branch every minute.
- `milos-api.yaml`: 2-replica Deployment, `migrate` initContainer runs
  `MilosTraining.Release.migrate()` before the `api` container starts;
  **both use the same `milos-db-app` DATABASE_URL** — no separate elevated
  migration role exists at the Kubernetes-manifest level, matching what the
  live role query confirmed (both are the same non-superuser `app` role).
- `milos-db.yaml`: a CloudNativePG (`postgresql.cnpg.io/v1`) `Cluster` with 3
  instances, no custom `managed.roles` override, so CNPG's default
  non-superuser `app` role convention applies — consistent with the absence
  of a `milos-db-superuser` secret.
- `milos-secrets.yaml`: SOPS-encrypted with `age`, per the repo's documented
  convention; not decrypted as part of this audit.
- Pod inventory at time of check: `milos-api` (2/2 running, 15h age),
  `milos-web` (2/2, 15h — recent rollout), `milos-db-{1,2,3}` (18–19d age),
  `milos-redis`, `milos-meilisearch`, `milos-minio` — all healthy.

## What was explicitly not done

- No decryption of `milos-secrets.yaml` or any live Kubernetes `Secret`
  value.
- No write, update, patch, or delete operation against any cluster resource.
- No mutation of any database row.
- No live exploitation attempt against `https://milos.4kq.net/` (no crafted
  HTTP requests to reproduce F-21/F-22/F-23 against the real endpoint were
  made; findings were validated at the database layer only).
- No access-log review (recommended as a follow-up for F-23 specifically,
  requires log access this audit did not have/use).
