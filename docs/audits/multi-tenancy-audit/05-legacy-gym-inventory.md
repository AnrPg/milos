# Legacy Gym (`legacy-milos-training`) Inventory

Date: 2026-08-05. Scope: `apps/api`, `apps/web`, `docs/`, migrations, config,
docker-compose. Methodology: exhaustive grep for legacy/default/primary/main/home/root
gym terms, semantic search for "first organization"/fallback patterns, and direct
migration review for RLS defaults. All items independently traced to file:line.

Legend — classification per item: **privileged** / **compatibility** /
**fallback** / **stale data** / **dead code** / **test fixture assumption** /
**configuration coupling** / **uncertain**.

## Summary judgment

The legacy organization (`slug: "legacy-milos-training"`, created idempotently by
`Organizations.ensure_legacy_organization/0`) receives **no explicit extra
entitlement, subscription tier, or feature flag** at creation — it goes through
the same `create_organization/1` path as any platform-provisioned tenant. However
it is wired in as the **implicit default tenant** at five distinct layers, and one
of those (RLS policy COALESCE fallback) is a genuine, currently-live privilege
asymmetry, not just migration tooling. This contradicts the stated invariant that
historical origin must never grant additional authorization.

## 1. `mix milos.organizations.ensure_legacy` — creation privilege comparison

**File:** `apps/api/lib/mix/tasks/milos.organizations.ensure_legacy.ex`,
`apps/api/lib/milos_training/organizations.ex:22-31,136` (`@legacy_organization`,
`ensure_legacy_organization/0`, `create_legacy_organization/0`).

`create_legacy_organization/0` calls the same `Commands.CreateOrganization` used
by normal provisioning. No entitlement/plan/feature-flag row, no elevated
`status`, is created here beyond `create_organization/1`'s defaults.
`ensure_legacy_membership/2` auto-grants `:owner` to accounts whose global
`role == :admin` and `:member`/`:athlete` role otherwise — this affects only
*membership role assignment for pre-existing single-tenant accounts* during
migration, not a capability unavailable to any other org's owner.

`priv/repo/migrations/20260804170000_promote_legacy_milos_tenant_branding.exs`
only renames branding fields ("Legacy Milos Training" → "Milos Training") —
cosmetic.

**Classification: compatibility behavior (creation-time), legitimate one-time
migration tooling.** No entitlement disparity found at creation.

## 2. HTTP tenant-context resolution defaults to the legacy org

**File:** `apps/api/lib/milos_training_web/plugs/resolve_tenant_context.ex:13-16`

```elixir
slug =
  conn.path_params["organization_slug"] ||
    List.first(get_req_header(conn, "x-organization-slug")) ||
    MilosTraining.Organizations.legacy_organization_slug()
```

Any request reaching this plug without a path-scoped `organization_slug` (i.e.
every route under `/api/admin/...`, ~140 endpoints — see
`01-architecture-and-data-model.md` §4) resolves against the legacy org unless
overridden by the client-controlled `x-organization-slug` header. Bounded by a
DB membership check downstream (`TenantAuthorization.build/4`), so this is not
an open door to arbitrary accounts — but the legacy org is uniquely reachable
via any tenant-context route that omits explicit tenant context, which no other
org is.

**Classification: fallback behavior — real, membership-gated.**

## 3. WebSocket connection defaults to the legacy org

**File:** `apps/api/lib/milos_training_web/user_socket.ex:26-38` — identical
shape to §2; request metadata is explicitly tagged `compatibility:
:legacy_path`, confirming the pattern is a known, acknowledged shim rather than
an oversight.

**Classification: compatibility behavior (acknowledged in code), fallback
behavior.**

## 4. Realtime broadcast helpers silently target the legacy org

**Files:** `apps/api/lib/milos_training_web/realtime.ex:5-15,52-54`,
`apps/api/lib/milos_training/application/schedule_realtime.ex:5-19`

```elixir
organization_id =
  Map.get(payload, :organization_id) ||
    Map.get(payload, "organization_id") ||
    legacy_organization_id()
```

Any caller that omits `organization_id` from a broadcast payload silently
broadcasts on the legacy org's PubSub topic instead of raising. Doesn't leak
other tenants' data directly (topics are per-org) but hides bugs: a caller with
broken tenant-context propagation "succeeds" against the legacy org's channel
instead of failing loudly.

**Classification: fallback behavior — should fail loudly, currently fails
silently-to-legacy.**

## 5. Un-scoped legacy-arity store functions are hardcoded to the legacy org

**Files:** `apps/api/lib/milos_training/scheduling/scheduling_store.ex` (all
legacy-arity functions — `create_class_type/2` without context,
`list_class_types/0`, `create_slot/1`, `get_booking/1`, etc.), comment in
`apps/api/lib/milos_training/workouts/workout_store.ex:10-11`:

> "Scoped variants are the tenant-aware public boundary. The legacy arities
> remain temporarily for jobs and callers still being migrated; RLS limits
> those to legacy."

This is explicit, intentional, ADR-060-acknowledged migration debt. RLS still
prevents these call sites from leaking into non-legacy orgs. Net effect is an
**inequality in the other direction**: any caller still using the legacy arity
only works against the legacy org, so newly onboarded tenants get zero
functionality from unmigrated call sites — a functional/operational risk to new
tenants, not a security hole for existing ones.

**Classification: compatibility behavior, acknowledged migration debt. No
cross-tenant leakage risk.**

## 6. RLS policies COALESCE-fallback to the legacy org (highest-severity item — see Finding F-05)

**Files:**
`apps/api/priv/repo/migrations/20260803223000_add_t4_ownership_foundation.exs:66-73,236-241`
(creates `milos_legacy_organization_id()` SQL function; adds `organization_id
DEFAULT milos_legacy_organization_id()` to ~44 tenant tables — this column
default is **never dropped** in any later migration);
`.../20260804090000_enforce_remaining_t4_tenant_boundaries.exs:49-63`,
`.../20260804113000_enforce_feedback_tenant_boundaries.exs:18-22`,
`.../20260804143000_finalize_finance_t4_tenant_boundaries.exs:26-40`,
`.../20260804150000_finalize_remaining_t4_tenant_boundaries.exs:33-47`.

Every "enforce"-stage RLS policy across finance, memberships, promotions,
referrals, messaging, gamification, analytics, feedback/reviews, and attendance
tables uses:

```sql
organization_id = COALESCE(
  NULLIF(current_setting('app.organization_id', true), '')::uuid,
  milos_legacy_organization_id()
)
```

A Postgres session/transaction that never calls `SET app.organization_id` (a
raw `psql` admin session, a misconfigured Oban worker, a `user_id`-only
`RepoContext.run` context per
`apps/api/lib/milos_training/infrastructure/tenancy/repo_context.ex:4-13`, any
manual data-repair script) transparently reads and writes **the legacy org's
rows** instead of erroring or matching zero rows. `mix milos.tenancy.audit` does
not detect this — it only checks `rls_enabled`/`rls_forced` booleans, not policy
predicate content.

A concrete live application-code instance of dependence on this fallback:
`apps/api/lib/milos_training/infrastructure/finance/ecto_finance_store.ex`
`get_finance_settings/0`/`update_finance_settings/1` — `Repo.one(from s in
FinanceSetting, limit: 1)` with **no explicit `organization_id` filter at all**,
unlike the equivalent Gamification store function which wraps its query in
`scoped_to_tenant/1`.

ADR-060 itself explicitly warned against exactly this shape of risk
("Leaving nullable tenant ownership indefinitely was rejected because it
creates an implicit global tenant and weakens isolation" — Alternatives
Considered) — the enforce-stage COALESCE fallback reintroduces the same
implicit-global-tenant risk, scoped to legacy-org identity instead of null.

**Classification: privileged behavior / fallback behavior — the one confirmed,
currently-live, real special case. See `04-findings.md` F-05 (Critical).**

## 7. Test fixtures pervasively default every test user/admin to legacy-org membership

**File:** `apps/api/test/support/fixtures.ex:4-25` — `user_fixture/1` and
`admin_fixture/1` both call `Organizations.ensure_legacy_membership/2`.
Confirmed used pervasively across the controller/channel test suite (chat
channel, auth controller, admin workout controllers, etc.).

Consequence: most tests exercise exactly one organization. A query missing an
explicit `organization_id` predicate would produce identical-looking results
whether relying on correct explicit filtering or on the legacy-org RLS
fallback (§6), because there's only one org in play. Contexts confirmed to have
an explicit two-organization isolation test (`t4_ownership_foundation_test.exs`,
plus dedicated `tenant_isolation_test.exs` files) are exempt from this blind
spot; Notifications, Wellbeing, and Coaching have **no dedicated
`tenant_isolation_test.exs`** at all (confirmed by direct directory listing
during this audit) — see Finding F-10.

**Classification: test fixture assumption — legitimate convenience default, but
it is exactly the mechanism that can mask a missing `organization_id`
predicate.**

## 8. No "first/oldest organization" selection pattern found

Grepped for `Organizations.first()`, `Repo.one(from o in Organization, limit:
1)`, `ORDER BY inserted_at ASC LIMIT 1` selecting an organization — **none
found**. The only `limit: 1` patterns found are on **settings tables**
(finance/gamification/push settings, relying on RLS scoping — see §6 and
`04-findings.md`), not on the `organizations` table itself.

**Classification: no finding / clean.**

## 9. No hardcoded legacy env var / config coupling

Searched `apps/api/config/*.exs`, `docker-compose*.yml`, `.env.example` for
`LEGACY_GYM_ID`, `DEFAULT_ORG_SLUG`, and equivalents — no hits. The only
"milos-training" occurrences in config are OpenTelemetry service naming
(`config/runtime.exs` `OTEL_SERVICE_NAME`/`OTEL_SERVICE_NAMESPACE` defaulting to
`"milos-training-api"`/`"milos-training"`) — telemetry branding, not tenant
privilege.

**Classification: no finding / clean.**

## 10. Frontend — no hardcoded privileged legacy slug

Searched `apps/web/src` for `legacy`, `default_org`, `milos-training`. Only
hits: a cosmetic export-filename fallback
(`apps/web/src/lib/document-export.ts:910`,
`.slice(0, 72) || "milos-training"`) and an E2E fixture value
(`apps/web/e2e/offline-message-delivery.spec.ts:21`, uses `"milos-training"`,
not the real `legacy-milos-training` slug). No hardcoded organization slug in
the membership-switcher UI or a default-selected org.

**Classification: no finding / clean.**

## 11. `DEY48keGE` / old `/set-admin` fixed code

**Files:** `docs/adr/ADR-054-code-gated-admin-registration.md:24`,
`docs/discussions/2026-07-18-multi-tenant-refactor-discussion.md:277`. Confirmed
via repo-wide grep: **no live route, controller, or config references this code
or a `/set-admin` path**. `POST /api/auth/register-admin`
(`apps/api/lib/milos_training_web/controllers/auth_controller.ex:367-369`) has
been fully repurposed to require a valid `:owner`/`:admin`-scoped invitation
token via `RegisterInvitedUser.call/2` — the old fixed-code bypass is not
dormant, it is removed.

**Classification: dead code, fully retired — not a live finding.** (Not a
legacy-*org* privilege item; included here only because the prompt's search
term list named it.)

## Prioritized retirement/hardening actions

1. **Critical — remove the COALESCE-to-legacy-org fallback** from every RLS
   policy (§6) and drop the `DEFAULT milos_legacy_organization_id()` column
   defaults; a missing `app.organization_id` should cause RLS to match zero
   rows, not the legacy org's rows. See `04-findings.md` F-05 and
   `06-legacy-data-and-code-retirement-plan.md` phase 3.
2. **High — add an explicit `organization_id` predicate** to
   `get_finance_settings/0`/`update_finance_settings/1` (§6) and audit the rest
   of `ecto_finance_store.ex` for the same gap (see F-06 in `04-findings.md`).
3. **Medium — fail loudly instead of silently** in `realtime.ex`/
   `schedule_realtime.ex` (§4) when `organization_id` is missing from a
   broadcast payload.
4. **Medium — extend `mix milos.tenancy.audit`** to detect a COALESCE-to-legacy
   (or any non-strict-equality) predicate in a table's RLS policy, not just the
   `rls_enabled`/`rls_forced` booleans.
5. **Low — track remaining `legacy_scope()`-only call sites** in
   `scheduling_store.ex`/`workout_store.ex` (§5) as functional migration debt
   for new-tenant parity, separate from the security track.
6. **Low — add explicit two-organization isolation tests** for Notifications,
   Wellbeing, and Coaching (§7) to close the test-fixture blind spot.
