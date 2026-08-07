# Findings

Date: 2026-08-05. All findings are evidence-backed with file:line references,
verified either by direct code/migration reading, by live queries against a
locally-migrated copy of the schema (dev Postgres container started for this
audit only — see `08-test-gap-plan.md` for exact commands), or by running the
existing automated test suite. Findings are ordered by severity. Where a finding
originated from a delegated research pass, it was independently spot-checked
against the actual source before being included here.

Severity legend: **Critical** (direct cross-tenant access/action, global
privilege escalation, financial cross-tenant corruption) · **High** (meaningful
authorization bypass, broad tenant leakage, role escalation, systemic missing
enforcement) · **Medium** (localized isolation weakness, risky fallback,
incomplete structural protection) · **Low** (maintainability, dead code, weak
defense-in-depth) · **Informational**.

---

## F-21 — `finance_aggregates` materialized-view query has zero tenant filter: confirmed cross-tenant financial data leak

**STATUS (2026-08-06): FIXED.** The materialized view had no `organization_id`
column at all (not just a missing `WHERE` — a structural gap), so the fix
required rebuilding it via migration
`20260806100000_scope_finance_aggregates_by_organization.exs` to add
`organization_id` to every branch of the `UNION ALL` and to the unique index,
then scoping `financial_summary/1`'s raw query by
`RepoContext.current_setting("app.organization_id")`, mirroring the
`coaching_aggregates` pattern. Verified with a new failing-then-passing test
in `test/milos_training/finance/tenant_isolation_test.exs` ("financial_summary
aggregates are isolated by organization") plus the full 83-test Finance suite
and the full 575-test project suite, all green.

**Severity:** Critical · **Confidence:** Confirmed (read directly)
**Invariant affected:** Direct cross-tenant data access to financial records — the single most severe category named in the audit brief.

**Evidence:** `apps/api/lib/milos_training/infrastructure/finance/ecto_finance_store.ex`
`financial_summary/1` runs:
```sql
SELECT period_start, user_type_snapshot, package_code, package_family,
       membership_count, active_membership_count, expiring_membership_count,
       paid_revenue_cents, pending_revenue_cents, promotion_redemption_count, ...
FROM finance_aggregates
WHERE period_start >= $1
ORDER BY period_start DESC, package_code ASC
```
— no `organization_id` predicate anywhere. `finance_aggregates` is a
materialized view; PostgreSQL cannot apply Row-Level Security to materialized
views, so there is **no database backstop either** — this query is completely
unscoped end to end. Reachable via `GET /api/admin/finance/summary`
(`admin_finance_controller.ex`, behind only the `:admin_only` pipeline — any
organization's owner/admin). The correct pattern already exists elsewhere in
the same codebase for the equivalent `coaching_aggregates` view
(`infrastructure/coaching/ecto_coaching_store.ex` — explicit `WHERE
organization_id = $1::uuid` sourced from `RepoContext.current_setting`), and
`docs/architecture/tenant-ownership-inventory.md` itself documents
`finance_aggregates` as requiring "Group and filter by `organization_id`" —
a documented requirement that was never implemented for this call site. The
migration that created the view (`20260611120000_create_phase8_finance_analytics_foundations.exs`)
predates all T4 tenancy work by nearly two months and was never revisited when
Finance's RLS enforcement slice landed.

**Failure scenario:** Any organization's admin/owner opens their finance
dashboard and receives platform-wide revenue, membership, promotion/referral,
and credit-ledger aggregates for **every tenant on the installation**, not
just their own — a direct, currently-live cross-tenant financial data leak
requiring no exploitation technique beyond using the product as documented.

**Impact:** Confirmed Critical — this is exactly the scenario the audit brief
names as the top-severity category ("direct cross-tenant data access ...
financial cross-tenant corruption, or equivalent").

**Production data risk:** If this endpoint has been used in production by any
tenant admin, that admin has already seen other tenants' aggregate financial
data. This cannot be undone retroactively; recommend checking access logs for
`GET /api/admin/finance/summary` calls across all tenants as an incident
follow-up. **Updated after live production verification (2026-08-05):**
production currently has exactly one organization (see F-07's production
verification note and `10-production-verification.md`), and its
`finance_aggregates` table holds 7 rows, all necessarily belonging to that
single org — there is no second tenant for this query to have leaked data
*to* yet, so no incident has occurred. The vulnerability remains fully live
in the deployed code and will expose real cross-tenant data starting from the
moment a second organization is provisioned, with zero additional trigger
required — this must be fixed before onboarding any additional tenant.

**Recommended remediation direction:** Add `organization_id` filtering to
`financial_summary/1`'s raw SQL identical to the Coaching pattern; treat this
as a hotfix, not part of the general remediation backlog, given it is a
live, low-effort-to-exploit leak.

**Recommended validation test:** Two-organization test: seed
`finance_aggregates` rows for Org A and Org B; call `financial_summary/1`
scoped to Org A; assert Org B's rows are absent from the result.

---

## F-22 — `weekly_leaderboard` materialized-view query has zero tenant filter: confirmed cross-tenant PII leak, reachable without any organization membership

**STATUS (2026-08-06): FIXED**, with one residual, explicitly accepted gap.
Like `finance_aggregates`, `weekly_leaderboard` had no `organization_id`
column at all. Migration `20260806110000_scope_weekly_leaderboard_by_organization.exs`
rebuilds it, deriving `organization_id` from `leaderboard_opt_ins.organization_id`
(a user only appears on a board if opted in *within* that org) and scoping the
`workouts_this_week` count to `workout_executions.organization_id`.
`get_leaderboard/2` in `ecto_gamification_store.ex` now filters by
`RepoContext.current_setting("app.organization_id")`. **The residual gap
noted earlier same-day is now also fixed** (2026-08-06, migration
`20260806130000_add_organization_id_to_user_achievements.exs` +
`20260806140000_scope_weekly_leaderboard_prs_by_organization.exs`):
`user_achievements` now carries `organization_id` (backfilled from the
source execution for PR badges, and from the user's earliest active
membership otherwise), populated explicitly by
`RecordWorkoutCompletion.call/1` rather than left to an ambient session GUC,
and `prs_this_month` in the `weekly_leaderboard` view is scoped by it the
same way `workouts_this_week` is. Fixing this also surfaced and fixed an
unrelated, adjacent gap: `EctoExecutionStore`'s `normalize/1` silently
dropped `organization_id` from every execution map returned anywhere in the
app, which would have broken any future org-aware consumer of executions
without explicit context threading. Verified with a new
failing-then-passing test in
`test/milos_training/gamification/tenant_isolation_test.exs` ("weekly
leaderboard is isolated by organization context") plus the full 49-test
Gamification suite and the full 575-test project suite, all green.

**Severity:** Critical · **Confidence:** Confirmed (read directly)

**Evidence:** `apps/api/lib/milos_training/infrastructure/gamification/ecto_gamification_store.ex`
`get_leaderboard/2`:
```sql
SELECT user_id, nickname, workouts_this_week, prs_this_month
FROM weekly_leaderboard
ORDER BY workouts_this_week DESC, nickname ASC   -- (or prs_this_month DESC for monthly)
LIMIT $1
```
— no `organization_id` predicate. Same structural gap as F-21: materialized
views cannot host RLS, and no application-layer filter was added. Reachable
via `GET /challenges/:id/leaderboard` under the `:user_only` pipeline — **any
authenticated user, with no organization membership check of any kind**, not
even the caller's own org.

**Failure scenario:** Any authenticated user (any role, any org, or even an
account with zero organization memberships) hits this endpoint and receives
`user_id`, `nickname`, weekly workout counts, and monthly PR counts for
members across **every organization on the platform**.

**Impact:** Confirmed Critical — direct cross-tenant PII exposure
(`user_id`+`nickname`+activity data) with the lowest possible barrier to
exploitation (authenticated-only, no tenant relationship required at all).

**Production data risk:** Same as F-21 — any use of this endpoint has already
exposed cross-tenant member identities and activity levels. **Updated after
live production verification (2026-08-05):** production's `weekly_leaderboard`
currently holds 0 rows and there is only one organization (see F-07's
production note), so no actual cross-tenant leak has occurred yet — but this
query has no auth/tenant gate at all, so it will expose real data the moment
either a second org exists or the view is populated, with no code change
required to trigger it.

**Recommended remediation direction:** Add `organization_id` filtering to
both `@weekly_leaderboard_query` and `@monthly_leaderboard_query`; also add
an organization-membership check at the controller/application layer (the
route currently has no tenant gate at all, independent of the query itself).

**Recommended validation test:** Two-organization test: seed
`weekly_leaderboard` for Org A and Org B; call the leaderboard endpoint as an
Org A member; assert no Org B `user_id`/`nickname` appears in the result.

---

## F-23 — Execution `admin_mode` RLS bypass is derived from the legacy global `user.role`, not tenant membership, and is org-blind: confirmed cross-tenant + cross-user IDOR

**STATUS (2026-08-06): FIXED**, verified against real RLS enforcement (not
merely by passing tests). Migration
`20260806120000_scope_execution_admin_mode_bypass_by_organization.exs`
replaces the blanket `current_setting('app.admin_mode', true) = 'true'`
clause in the `workout_executions_owner_or_tenant_policy` RLS policy with a
correlated `EXISTS` check against `organization_memberships`, requiring the
acting admin to hold an active `owner`/`admin`/`coach` membership in the
*specific row's* organization before the admin-mode bypass applies. No
application-code changes were needed — `get_workout_execution.ex` still calls
the unscoped `Execution.get_execution/1` in the admin branch, but the
authorization boundary now lives correctly in the database, which is the
right place for it.

Because this codebase's entire test suite runs against Postgres as a
superuser (see F-07 below — `rolbypassrls = true`), an ordinary Ecto-based
ExUnit test cannot actually exercise RLS: it would report false-green
regardless of policy correctness. To verify this fix honestly, a dedicated
non-superuser role (`milos_test_runtime`) is now self-provisioned by
`test/milos_training/execution/tenant_isolation_test.exs`, which connects via
raw `Postgrex` and proves both directions: (1) a global admin with no
membership in the target org cannot read its executions, and (2) a global
admin who *is* an active coach/admin/owner in that org still can. This was
also independently confirmed via a one-off manual script executed against the
same non-superuser role before the automated test was written, so the result
is not resting on a single test author's assumptions. This test is a narrow,
one-finding instance of what P1.5 ("non-superuser RLS-enforcing test/CI
lane") should generalize — P1.5 remains open for the rest of the suite.

**Severity:** Critical (fixed) · **Confidence:** Confirmed (read directly)
**Invariant affected:** "An account's role in one tenant must not grant access to data or operations in another tenant"; IDOR via IDs in route parameters.

**Evidence:**
`apps/api/lib/milos_training/application/get_workout_execution.ex`:
```elixir
def call(execution_id, %{role: :admin}) do
  case Execution.get_execution(execution_id) do
    nil -> {:error, :not_found}
    execution -> {:ok, attach_workout_summary(execution)}
  end
end
```
`Execution.get_execution/1` performs no ownership/org check itself; it relies
entirely on RLS. `apps/api/lib/milos_training/infrastructure/tenancy/repo_context.ex`
`maybe_put_admin_mode/2`:
```elixir
defp maybe_put_admin_mode(settings, %{account: %{role: role}}) do
  if to_string(role) == "admin" do
    [{"app.admin_mode", "true"} | settings]
  else
    settings
  end
end
```
`role` here is `context.account.role` — the **legacy global `users.role`**
field (F-02), not `organization_memberships.role`. The RLS policy installed by
`apps/api/priv/repo/migrations/20260804161500_allow_execution_admin_and_authorization_reads.exs`:
```sql
CREATE POLICY workout_executions_owner_or_tenant_policy ON workout_executions
USING (
  user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
  OR organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
  OR current_setting('app.admin_mode', true) = 'true'
  OR current_setting('app.execution_authorization_check', true) = 'true'
)
```
has **no organization_id constraint on the `admin_mode` branch** — it is a
blanket bypass, not "admin of this org."
`GET /api/executions/:id` is reachable under the `:user_only` pipeline (no
tenant/role gate at the route level; the controller passes the raw actor into
`GetWorkoutExecution.call/3`).

**Failure scenario:** Any account whose global `users.role` is `admin`
(settable via `POST /api/auth/register-admin` per the legacy-role-still-live
finding in F-02) can `GET /api/executions/<any-execution-id>` for **any
user's execution in any organization**, by enumerating or guessing UUIDs —
textbook IDOR, and the exact "supplying another tenant's record ID" scenario
named in the audit brief's IDOR/BOLA section. This is the only place
`admin_mode` is referenced in any RLS policy (confirmed via repo-wide grep),
so blast radius is scoped to the Execution context, but within that context it
is a complete, confirmed cross-tenant and cross-user bypass.

**Impact:** Confirmed Critical — direct cross-tenant (and cross-user, even
within the same tenant) IDOR on personal training/execution data.

**Production data risk:** Since this is cross-*user* as well as cross-tenant,
it is exploitable even in production's current single-organization state —
any of the 5 production users with global `role: admin` could already fetch
any other production user's execution records by ID. Live verification
(2026-08-05) did not attempt to exercise this endpoint against real data (that
would require impersonating a real account or crafting a live HTTP request,
outside this audit's read-only-query scope), so whether it has actually been
exploited is unknown; recommend checking `GET /api/executions/:id` access logs
for admin accounts requesting execution IDs not belonging to themselves.

**Recommended remediation direction:** Remove the blanket `admin_mode`
bypass; replace with an explicit organization-scoped check (the acting admin's
`organization_id` must match the execution's `organization_id` when the
execution has tenant provenance, and/or require the admin to hold an active
coach/admin membership with the athlete's organization) mirroring the
`active_athlete_membership?/2` pattern already used correctly in
`get_coaching_athlete_drill_down.ex`.

**Recommended validation test:** An account with global `role: :admin` but no
membership in Org X attempts `GET /api/executions/:id` for an execution
belonging to a user in Org X; must be rejected.

---

## F-24 — Finance's cron/Oban automations never open a tenant context; they operate only on the legacy organization's data via the RLS fallback, silently no-op-ing for every other tenant

**STATUS: FIXED** (2026-08-06). `mark_overdue_invoices_job.ex`,
`payment_reminder_job.ex`, and `reconcile_entitlement_reservations_job.ex` now
iterate every active organization from `OrganizationStore.list_organizations/0`
and call the Finance store functions once per organization context (see
remediation direction below, now implemented as described). Covered by
`test/milos_training/workers/mark_overdue_invoices_job_test.exs`,
`payment_reminder_job_test.exs`, and
`reconcile_entitlement_reservations_job_test.exs`, each asserting the job
mutates a *non-legacy* organization's data.

**Additional finding discovered during remediation (beyond original scope):**
this was not merely a "silent no-op for non-legacy orgs" bug. The
`finance_invoices_apply_tenant_context` DB trigger (`BEFORE INSERT/UPDATE` on
`finance_invoices`, backed by `milos_apply_tenant_context()`) unconditionally
overwrites `NEW.organization_id` with the current `app.organization_id`
session GUC whenever that GUC is set. `mark_overdue_invoices/0`,
`memberships_needing_payment_reminder/1`, and
`update_membership_reminder_timestamp/1` in `ecto_finance_store.ex` ran
`Repo.update_all` with **no explicit `organization_id` predicate** — safe only
because RLS was also restricting the affected rows. Once a per-organization
`RepoContext.run` wrapper is added (as this fix does) and the session GUC is
set, that same lack of an explicit predicate becomes a **cross-tenant data
corruption bug**: the bulk update's `WHERE` clause was still unscoped, so if
the RLS predicate ever failed to restrict the row set to the correct org
(e.g. a superuser/RLS-bypassing connection, or a future policy regression),
the trigger would silently reassign unrelated invoices/memberships to the
job's current org. Fixed by adding `tenant_scope/1` (explicit
`organization_id = ^session_org` predicate) to all three functions, making
the query itself tenant-safe independent of RLS/trigger behavior.
`release_stale_entitlement_reservations/1` was already correctly scoped and
did not need this change.

**Severity:** High · **Confidence:** Confirmed by delegated research (migration/RLS mechanics independently verified via F-04/F-05; the specific job call chains below were not independently re-read line-by-line and should get a follow-up direct read before remediation work begins)

**Evidence (as reported):** `mark_overdue_invoices_job.ex` → `Finance.mark_overdue_invoices/0`,
`payment_reminder_job.ex` → `Finance.memberships_needing_payment_reminder/1` /
`update_membership_reminder_timestamp/1`, and
`reconcile_entitlement_reservations_job.ex` → `Finance.release_stale_entitlement_reservations/1`
all call Finance store functions that run `Repo.update_all`/queries with no
surrounding `RepoContext.run`/`with_tenant_context` wrapper. Because the
underlying tables' RLS policy is `organization_id = COALESCE(session_var,
legacy_org)` (F-04), these operations only ever affect the legacy
organization's invoices/memberships/reservations.

**Failure scenario:** For every organization other than the legacy one:
overdue invoices never get marked overdue, payment reminders never fire, and
stale entitlement reservations never get released — a silent, tenant-wide
functional regression rather than a data leak (RLS fails closed here, not
open, for non-legacy orgs).

**Impact:** Not a security leak, but a correctness/product-viability defect:
per-tenant billing automation is effectively dead for every real (non-legacy)
tenant. This directly contradicts "all gyms must have equal
application-level capabilities."

**Recommended remediation direction:** These jobs must iterate over all
active organizations (or be triggered per-organization) and open
`RepoContext.run(%{organization_id: org_id}, fn -> ... end)` for each, rather
than running once, unscoped, for the whole installation.

**Recommended validation test:** Seed an overdue invoice for a non-legacy
organization; run the job; assert it transitions to `overdue`.

---

## F-25 — Messaging's Application layer never opens a tenant context anywhere; the feature is likely non-functional for every organization except the legacy one

**STATUS: FIXED** (2026-08-06). Confirmed by direct read: neither the
`messaging/application/*.ex` modules nor the top-level
`application/*_messaging_thread.ex` / `application/send_message.ex`
orchestration wrappers the controller actually calls ever opened a tenant
context. Worse than the original finding stated — since F-04 already removed
the RLS legacy-org `COALESCE` fallback earlier in this same remediation pass,
messaging now failed closed for **every** organization, including the
legacy one, not just non-legacy tenants. Fixed by mirroring the same
expand-phase pattern already used for Finance (`MyFinanceController`):
added `Messaging.with_tenant_context/2`, mirrored `/api/threads/*` under the
existing `/api/org/:organization_slug/me` (`tenant_member`) scope, and gave
`MessagingController` an `action/2` that wraps the whole action in
`Messaging.with_tenant_context/2` when `conn.assigns.tenant_context` is
present — the legacy flat `/api/threads/*` routes are left as-is (same
known F-01/P1.4 debt as everywhere else). Covered by
`test/milos_training_web/controllers/messaging_controller_tenant_context_test.exs`.

**Follow-up systemic gap discovered while fixing this (relevant to P1.4):**
`OpenApiSpex.Plug.CastAndValidate` rejects any request under a mirrored
`/api/org/:organization_slug/...` route with `"Unexpected field:
organization_slug"` unless the controller's `operation/2` spec explicitly
declares `organization_slug` as a path parameter. This was fixed for
Messaging's three `CastAndValidate`-guarded actions, but the ~90 admin
routes mirrored during F-01's expand phase likely have the same gap on any
POST/PATCH action — none of them have been exercised with a request body by
an automated test yet (only GETs), so this has been silently latent. Needs
a systematic audit of every mirrored controller's `operation/2` specs before
the frontend cuts over to the org-scoped URLs.

**Severity:** High · **Confidence:** Confirmed by delegated research (not independently re-read; recommend a direct read of `apps/api/lib/milos_training/messaging/application/*.ex` before remediation) · **Invariant affected:** tenant feature parity, not leakage (fails closed)

**Evidence (as reported):** None of `get_thread.ex`, `list_threads.ex`,
`list_messages.ex`, `get_or_create_thread.ex`, `mark_read.ex`,
`send_message.ex` call `ThreadStore.with_tenant_context/2` /
`MessageStore.with_tenant_context/2` despite both being defined. Since
`messaging_threads`/`messaging_participants`/`messaging_messages` RLS uses the
same `COALESCE(session_var, legacy_org)` pattern (F-04), any read/write for a
real organization's thread resolves against the wrong `organization_id` and
fails (`not_found` on read; `WITH CHECK` failure on insert).

**Failure scenario:** Any non-legacy organization's messaging feature
(coach/athlete threads, admin communication) does not work — reads return
not-found, writes are rejected — rather than leaking data cross-tenant.

**Impact:** Product-functionality defect of the same shape as F-24, not a
security leak per se, but severe enough to block real tenant onboarding if
messaging is a required feature.

**Recommended remediation direction:** Thread `TenantContext`/`UserContext`
through every Messaging Application module the same way Finance/Scheduling/
Feedback do.

**Recommended validation test:** Create a message thread as a non-legacy
organization member; confirm it can be read back and replied to.

---

## F-01 — Legacy `/api/admin/*` surface (~140 endpoints) resolves tenant identity from a client-controlled request header, not the URL

**STATUS: FIXED — CONTRACT PHASE COMPLETE (2026-08-06).**
`ResolveTenantContext` no longer reads `X-Organization-Slug` or falls back to
the legacy organization; a request whose path lacks `organization_slug` is
now rejected with `organization_context_required` instead of being silently
scoped. The legacy `/api/admin/*` scope was deleted outright (every one of
its 97 routes already had an exact mirror under
`/api/org/:organization_slug/admin/*` from the expand phase - verified by
diffing the full route list before deleting). The frontend's `apiRequest`
(`apps/web/src/api/client.ts`) now transparently rewrites any `/admin/*` or
`/me/search/users` request to the org-scoped backend path using the same
slug it already resolved for the (now-removed) header, so none of the ~15
`api/*.ts` call sites needed individual changes.

Fixing the plug surfaced two things beyond the original finding's named
scope:
1. Three more flat routes shared the same `ResolveTenantContext`-dependent
   pipelines but were never part of the "admin console" framing: `GET
   /api/schedule`, `POST`/`DELETE /api/bookings`, `GET`/`POST`/`PATCH
   /api/my-workouts/*`, and `GET /api/workouts/:id[/scales]`. These were
   equally vulnerable to the same header-spoofing attack for
   member/athlete-facing data, not just admin data. Mirrored them under
   `/api/org/:organization_slug/...` and deleted the flat versions the same
   way.
2. A latent `OpenApiSpex.Plug.CastAndValidate` bug (first found while fixing
   F-25): every org-scoped mirrored route with a request body rejected as
   `"Unexpected field: organization_slug"`, since no operation spec declared
   it as a path parameter. Fixed generically (not per-controller) by having
   `ResolveTenantContext` strip `organization_slug` from `path_params`/`params`
   after resolving it into `tenant_context` - the parameter has served its
   purpose by then and no controller reads it directly.

`me_controller.ex`'s `search_users` (evidence below) now prefers
`conn.assigns.tenant_context` when present (set on the new
`/api/org/:organization_slug/me/search/users` mirror), falling back to the
header only on the still-mounted legacy `/api/me/search/users` route.

Frontend (F-09) fixed alongside this - see F-09 below for the mechanism
(the app already had a proxy that rewrites `/org/:slug/<path>` to `<path>`,
so no page files needed to move).

~130 backend test call sites across 18 files were updated to hit the
org-scoped paths.

**Severity:** Critical · **Confidence:** Confirmed (read directly)
**Invariant affected:** Tenant resolution must never trust body/header/cookie/token-supplied organization identifiers (ADR-058); authorization must depend on `membership(U,A)` derived from trusted server context.

**Evidence:**
`apps/api/lib/milos_training_web/plugs/resolve_tenant_context.ex:13-16`:
```elixir
slug =
  conn.path_params["organization_slug"] ||
    List.first(get_req_header(conn, "x-organization-slug")) ||
    MilosTraining.Organizations.legacy_organization_slug()
```
`apps/api/lib/milos_training_web/router.ex:166` — `scope "/api/admin", ...
pipe_through([:api, :authenticated, :admin_only])` spans ~140 route lines
(166–320): users, workouts, finance, schedule, class types, challenges,
wellbeing, settings. None of these routes carry `:organization_slug` in their
path, so `conn.path_params["organization_slug"]` is always `nil` for every one
of them. The same header-trust pattern is repeated in
`apps/api/lib/milos_training_web/controllers/me_controller.ex:245-250`
(`organization_slug/1` for `/api/me/search/users`).

**Failure scenario:** An authenticated tenant `admin` for Org A sends any
`/api/admin/*` request with header `x-organization-slug: org-b`. If they also
happen to hold (or later acquire, e.g. via F-07) a membership in Org B, the
request is served against Org B — the *choice* of which org's data is acted on
is attacker/client-controlled, not derived purely from an authenticated,
server-issued context. Even without a second membership, every account without
an explicit header falls through to the **legacy organization**, making the
legacy org uniquely reachable from any tenant-scoped route that omits explicit
tenant context — a capability no other organization has.

**Impact:** Structural violation of the stated tenant-resolution model;
converts the "active tenant" from a server-derived fact into a client-supplied
one for the majority of the admin surface. Bounded by the downstream DB
membership check (not a raw impersonation bypass), but it means the security
boundary depends on every future admin endpoint remembering this, and it
directly enables the legacy-org fallback documented in
`05-legacy-gym-inventory.md` §2.

**Production data risk:** The application has been running with this pattern
live; any admin session that ever omitted the header and had legacy-org
membership would have operated against legacy-org data by design, not by bug —
consistent with the T4 migration being partially complete. No evidence this
allowed *cross-tenant* access to a **non**-legacy org without holding a real
membership there.

**Recommended remediation direction:** Stop resolving tenant identity from any
request header. Migrate `/api/admin/*` to `/api/org/:organization_slug/admin/*`
(the pattern already used by the newer 3-endpoint admin surface at router.ex
127–133) and delete the header/legacy fallback from `ResolveTenantContext`
entirely — a request with no path slug should be rejected as tenant-ambiguous,
not defaulted.

**Recommended validation test:** Cross-tenant test: an authenticated Org-A-only
admin sends a legacy `/api/admin/*` request with `x-organization-slug: org-b`
(no Org B membership) and must receive 403/404, not silently fall through to
any org.

---

## F-02 — Legacy global `user.role` still authorizes real behavior on multiple code paths, independent of organization membership


**STATUS: FIXED 2026-08-07.** `RequireRole` deleted (P3.2). The application-layer global-role reads this finding lists are also resolved: see F-29 for the role model, and `GetCalendarFeed`/`GetLeaderboardSnippet`/`GetScheduleCalendar` are now membership-scoped. The remaining `users.role` reads are display/listing filters, not authorization.
**Severity:** High · **Confidence:** Confirmed (read directly)
**Invariant affected:** Tenant roles must be attached to membership, not treated as a global user property; a user's role in tenant A must not grant access derived from a global attribute.

**Evidence:** `apps/api/lib/milos_training/identity/user.ex:14` — `users` schema
retains `field :role, Ecto.Enum, values: RegistrationPolicy.roles()`
(`[:member, :athlete, :admin]`). Read as a live authorization gate at:
- `apps/api/lib/milos_training/application/get_calendar_feed.ex:30,38,79,81,115,123`
  — `user.role == :admin` unlocks org-wide attendee visibility on a
  **token-authenticated public ICS feed** (`GET /api/calendar/feed.ics`) that
  never resolves `TenantContext` at all.
- `apps/api/lib/milos_training/application/get_schedule_calendar.ex:75` —
  `admin_role?(nil, actor), do: actor.role == :admin`, the fallback branch used
  whenever no `TenantContext` is supplied.
- `apps/api/lib/milos_training/application/get_leaderboard_snippet.ex:7`.
- `apps/api/lib/milos_training/infrastructure/identity/ecto_user_store.ex:28,69,91,172,194`
  — including a global "don't demote the last admin" invariant that is
  installation-wide, not per-tenant.
- `apps/api/lib/milos_training/infrastructure/workouts/ecto_workout_store.ex:1910`.

**Failure scenario:** A user whose global `role` is `admin` (set once, anywhere
— e.g. via legacy data, via `Application.UpdateUserRole`, or via the legacy
admin-registration flow) receives elevated visibility on the calendar feed,
schedule admin view, and leaderboard reveal for **every** organization they can
reach through these code paths, regardless of their actual per-org membership
role — directly contradicting "the same user may have different roles in
different gyms" and "role in one tenant must not grant access in another."

**Impact:** Authorization inconsistency between the (correct)
membership-based model used elsewhere and these legacy-role-gated surfaces.
Highest-risk instance is the calendar feed, reachable without a resolved tenant
context.

**Production data risk:** Any account with a global `admin` role today has had
this broadened visibility; scope depends on how many accounts carry that role
historically (likely all pre-migration single-gym admins).

**Recommended remediation direction:** Replace every `actor.role`/`user.role`
check in these five modules with a membership-role check against a properly
resolved `TenantContext` for the calendar/schedule/leaderboard's actual
organization; delete `RequireRole` (confirmed dead code, never wired into any
pipeline) once all call sites are migrated.

**Recommended validation test:** A user with global `role: :admin` but only
`:member` membership in Org A must not see Org A's full attendee list via the
calendar feed or elevated schedule/leaderboard views.

---

## F-03 — Client-supplied `organization_id` accepted with no membership validation for self-selected/class-booking workout executions


**STATUS: FIXED 2026-08-07.** Every execution source now returns a server-derived `organization_id`; `self_selected` derives it from the workout and requires an active membership there. This finding was never carried into the roadmap, which is why it survived earlier passes.
**Severity:** High · **Confidence:** Confirmed (read directly, refined from initial subagent report)
**Invariant affected:** Creation must derive tenant identity from trusted server-side context, not client input.

**Evidence:** `apps/api/lib/milos_training/execution/commands/start_execution.ex:12`:
```elixir
execution_params <- %{
  organization_id: params[:organization_id] || params["organization_id"],
  ...
```
Caller chain: `POST /api/executions` (`apps/api/lib/milos_training_web/router.ex:391-401`,
pipeline `:user_only` — `AssignUserContext` only, no `ResolveTenantContext`) →
`apps/api/lib/milos_training/application/start_workout_execution.ex:30` —
`Execution.start_execution(actor.id, Map.merge(params, authorized_source))`.
`authorized_source` comes from
`apps/api/lib/milos_training/application/authorize_workout_execution_source.ex`:
for `source == "assigned"`, it **does** include a server-derived
`organization_id: access.organization_id` (from the assignment record), which
correctly overrides the client value via `Map.merge/2` key precedence. For
`source == "self_selected"` and `source == "class_booking"`, `authorized_source`
contains **no** `organization_id` key, so the client-supplied value passes
through unchanged to `Execution.Commands.StartExecution.call/2` and is
persisted with zero membership check.

**Failure scenario:** An authenticated member with no relationship to
Organization X calls `POST /api/executions` with `{"source":
"self_selected", "master_workout_id": "...", "organization_id": "<org-X-id>"}`.
The resulting `workout_executions` row is created (owned by the caller's own
`user_id` — this is a global-personal table per the ownership inventory) but
carries Org X as its organization *provenance*. Per ADR-060, Coaching's
tenant-scoped drill-down aggregate "counts only matching execution provenance"
for members with active memberships — a forged provenance value can pollute
Org X's coaching aggregate with an execution from a non-member, or let a real
Org X member mislabel their execution to evade or manipulate that org's
coaching visibility.

**Impact:** Data-integrity/analytics-poisoning risk within the global-personal
+ tenant-provenance model, not a direct cross-tenant *read* of another
tenant's private rows (the row is still owned by the actor's own `user_id` and
gated by owner-or-tenant RLS). Still a genuine violation of "creation must
derive tenant identity from trusted server-side context."

**Recommended remediation direction:** Derive `organization_id` server-side for
every execution source, not just `"assigned"` — e.g. from the actor's active
membership when the workout/class itself is tenant-scoped, or explicitly `nil`
provenance for a workout with no tenant affiliation. Never read
`params[:organization_id]` in `StartExecution.call/2`.

**Recommended validation test:** A user with zero membership in Org X starts a
self-selected execution with a forged `organization_id` for Org X; the
persisted row's `organization_id` must not equal Org X (either rejected or
nulled), and Org X's coaching aggregate must not include it.

---

## F-04 — Row-Level Security "enforce" policies fall back to the legacy organization instead of denying access when tenant context is unset

**STATUS (2026-08-06): FIXED for RLS policies; column defaults deliberately
left in place.** Migration
`20260806150000_remove_rls_legacy_org_coalesce_fallback.exs` drops and
recreates all 40 affected `<table>_tenant_policy` policies (queried live via
`pg_policy`, not guessed from migration source, to be sure none were missed)
with a bare `organization_id = NULLIF(current_setting('app.organization_id',
true), '')::uuid` predicate, matching the pattern Scheduling's tables
(`bookings`, `class_types`, `class_series`, `scheduled_classes`,
`class_attendance_records`, `scheduling_settings`) already used correctly.
Verified directly against the non-superuser `milos_test_runtime` role (not
just "tests still pass," which is meaningless here per F-07): inserted a
`memberships` row under a real organization, cleared `app.organization_id`
entirely, and confirmed the row is now invisible (0 rows) instead of
matching via the old fallback. The 46 `DEFAULT
milos_legacy_organization_id()` **column defaults were deliberately left in
place** — the remediation roadmap's own sequencing note says to defer
dropping these until the write-paths that rely on them without an active
tenant session (F-24 Finance jobs, F-25 Messaging) are fixed; dropping them
now would turn silent misattribution into hard `NOT NULL` failures for those
jobs. This is the correct, intentional scope boundary for this fix, not an
oversight — P1.1 is complete on its own terms, dropping the defaults is P2.3/P2.4-gated
follow-up.

**Severity:** Critical · **Confidence:** Confirmed (migration source + live `pg_policies` query)
**Invariant affected:** Historical origin must never grant a tenant additional authorization; absence of tenant context must be denied, not silently resolved.

**Evidence:**
`apps/api/priv/repo/migrations/20260803223000_add_t4_ownership_foundation.exs:66-73,236-241`
creates `milos_legacy_organization_id()` and adds `organization_id DEFAULT
milos_legacy_organization_id()` to ~44 tenant tables (default never dropped in
any later migration). Every subsequent "enforce"-stage migration
(`20260804090000_enforce_remaining_t4_tenant_boundaries.exs:49-63`,
`20260804113000_enforce_feedback_tenant_boundaries.exs:18-22`,
`20260804143000_finalize_finance_t4_tenant_boundaries.exs:26-40`,
`20260804150000_finalize_remaining_t4_tenant_boundaries.exs:33-47`) installs
policies of the form:
```sql
organization_id = COALESCE(
  NULLIF(current_setting('app.organization_id', true), '')::uuid,
  milos_legacy_organization_id()
)
```
across finance, memberships, promotions, referrals, messaging, gamification,
analytics, feedback/reviews, and attendance tables. `RepoContext.run/2`
(`apps/api/lib/milos_training/infrastructure/tenancy/repo_context.ex:4-13`) has
a `user_id`-only clause that never sets `app.organization_id` — any code path
using that context class against a T4 tenant table hits the fallback.
`mix milos.tenancy.audit` cannot detect this: it only checks the
`relrowsecurity`/`relforcerowsecurity` booleans (`rls_enabled`/`rls_forced`),
never the policy predicate text.

**Failure scenario:** Any Postgres session/transaction that reaches one of
these ~30+ tables without first calling `SET app.organization_id` (a raw
`psql` maintenance session, a misconfigured or partially-migrated Oban worker,
a manual data-repair script, or the concrete application-code instance in
F-06) transparently reads and writes the **legacy organization's** rows
instead of getting zero rows. A regression that drops tenant-context
propagation on any of these tables would silently "succeed" against legacy
data instead of failing loudly — masking exactly the class of bug this audit
was commissioned to find.

**Impact:** The legacy org is the de facto database-level default tenant for
most of the application's tenant-owned data. This does not leak *other*
(non-legacy) tenants' data to each other — RLS still isolates them correctly
from one another — but it is a concrete, currently-live violation of "no
implicit default gym" and "historical origin must never grant additional
authorization," and it directly undermines confidence in every RLS-based
enforcement claim in `docs/technical_debt.md` TD-038.

**Production data risk (updated after live production verification,
2026-08-05):** Read-only queries executed against the live production
database via the running `milos-api` pod's own Ecto connection (Kubernetes
namespace `tenant-m4`, see `10-production-verification.md`) confirm:
- **40 RLS policies in production currently contain the
  `milos_legacy_organization_id` fallback** — the vulnerability is
  structurally live in the deployed database, not just in the migration
  source.
- However, `milos_legacy_organization_id()` currently **returns `NULL`** in
  production, because the function resolves the legacy organization by a
  hardcoded slug lookup (`SELECT id FROM organizations WHERE slug =
  'legacy-milos-training' LIMIT 1`) and production's only organization has
  since had its slug changed to `milos-training` (no `legacy-` prefix) —
  apparently a deliberate rebranding action taken independently of this
  fallback function. This means the COALESCE fallback is **currently inert
  by accident**: an unset `app.organization_id` session setting today
  resolves to `COALESCE(NULL, NULL) = NULL`, which fails RLS row-matching
  closed (zero rows returned) rather than silently exposing the org's data.
  Confirmed zero `organization_id IS NULL` rows across `finance_invoices`,
  `memberships`, `master_workouts`, `bookings`, and `messaging_threads` —
  no write has hit the broken insert path since the slug changed (either
  none was attempted, or it was rejected by a `NOT NULL` constraint).
- **This is not a fix and must not be treated as one.** The fallback
  function still exists, is still referenced by all 40 policies, and will
  silently reactivate the instant *any* organization is created or renamed
  to slug `legacy-milos-training` again — including via a routine re-run of
  `mix milos.organizations.ensure_legacy` (explicitly documented as
  idempotent and safe to re-run), or via a future migration/seed script that
  assumes that slug still exists. The current inertness is an unintended
  side effect of an unrelated branding change, not a deployed mitigation,
  and provides no defense against a code path that reaches these tables via
  the `user_id`-only `RepoContext.run/2` clause without ever going through
  the slug lookup at all (that clause never calls
  `milos_legacy_organization_id()` — it simply never sets
  `app.organization_id`, so the same COALESCE-to-NULL currently applies, but
  would silently flip to COALESCE-to-a-real-org-id the moment the slug
  collision reappears).
- Additionally, production currently has **exactly one organization** (slug
  `milos-training`, 5 users, 3 memberships, 1 active platform owner) — this
  is evidently a pre-commercial-launch/single-tenant deployment, consistent
  with the runbook's own guidance not to provision a second independent
  tenant until T4–T6 enforcement is fully validated. This does not reduce
  the severity of the underlying code defect (it must be fixed before a
  second tenant is onboarded, or F-04 immediately becomes exploitable
  exactly as described above), but it means **no cross-tenant data exposure
  via this specific mechanism has occurred yet**, because there is currently
  no second tenant for data to leak to or be misattributed to.

**Recommended remediation direction:** Remove the `COALESCE(...,
milos_legacy_organization_id())` fallback from every enforce-stage RLS policy;
policies should use bare `organization_id = NULLIF(current_setting(...),
'')::uuid` so an unset session setting matches zero rows. Drop the `DEFAULT
milos_legacy_organization_id()` column defaults once all write paths reliably
supply `organization_id` explicitly. Extend `mix milos.tenancy.audit` to parse
policy predicate text and fail if any policy references
`milos_legacy_organization_id`.

**Recommended validation test:** Open a raw transaction with no
`app.organization_id` setting; attempt to `SELECT` from each enforce-stage
table; expect zero rows, not legacy-org rows.

---

## F-05 — Finance store has no explicit application-layer tenant predicates; relies entirely on the (compromised, per F-04) RLS backstop

**STATUS (2026-08-06): FIXED, with a correction to this finding's own
premise.** While fixing this, discovered the file already had a working
scoping helper — `tenant_scope/1`, used in 25 places — that this finding's
original grep (for the literal string `scoped_to_tenant`) missed entirely.
The real gap was narrower than described: 14 specific call sites
(`Repo.get(FinanceInvoice, ...)`, `Repo.get(Membership, ...)`,
`Repo.get(MembershipPackageSubscription, ...)`, `Repo.get(PromotionCampaign,
...)`, `Repo.get(ReferralProgram/ReferralEvent/ReferralReward, ...)`, and
`get_finance_settings/0` / `update_finance_settings/1`) that genuinely had no
predicate at all. All 14 now go through `tenant_scope/1`. `update_finance_settings/1`
also had a real correctness bug beyond the leak: without a predicate,
calling it from Org B when Org A already had a settings row would **update
Org A's settings** instead of creating Org B's — now fixed by scoping the
lookup and passing `organization_id` explicitly into the insert path.
`Finance.get_invoice/1` (the unscoped 1-arity delegate) is now safe by
construction, since the store function it delegates to is scoped — no need
to remove or gate the arity itself. Verified with a new IDOR-style test
covering invoice, membership, and credit-application fetches across two
organizations (`tenant_isolation_test.exs` — "invoices, memberships, and
package subscriptions cannot be fetched by ID across organizations"), plus
the full 577-test suite, all green.

**Severity:** Critical · **Confidence:** Confirmed (grep + direct read of representative call sites)
**Invariant affected:** ADR-056's explicit "enforce isolation twice" mandate; financial cross-tenant corruption is named as a Critical-severity category in the audit brief.

**Evidence:** `apps/api/lib/milos_training/infrastructure/finance/ecto_finance_store.ex`
(4,215 lines) contains **no `scoped_to_tenant`-style helper and no explicit
`where(query, [row], row.organization_id == ^organization_id)` clause
anywhere**, unlike the equivalent Messaging (`ecto_message_store.ex:154-162`),
Gamification (`ecto_gamification_store.ex:30,46`), Feedback
(`ecto_feedback_store.ex`), and Workouts (`ecto_workout_store.ex:1802-1810`,
inconsistently) stores, which all define and use an explicit
`scoped_to_tenant/1`. Representative unscoped-by-primary-key fetches: lines
587, 596, 615 (`Repo.get(FinanceInvoice, invoice_id)`), 716, 769
(`Repo.get(Membership, membership_id)`), 2299, 2415, 2966
(`Repo.get(MembershipPackageSubscription, ...)`), 3036
(`Repo.get(Membership, ...)`), and 3966/3982
(`get_finance_settings/0`/`update_finance_settings/1`, `Repo.one(from s in
FinanceSetting, limit: 1)` — no predicate at all).
`apps/api/lib/milos_training/finance.ex:138` — `defdelegate get_invoice(invoice_id),
to: FinanceStore` is a **public, unscoped 1-arity API**, distinct from the
correctly-scoped 2-arity `get_invoice(context, invoice_id)` at line 139.
`apps/api/lib/milos_training_web/controllers/admin_finance_controller.ex:1198,1222`
calls the unscoped 1-arity form and only *afterward* checks `invoice.organization_id
== context.organization_id` — the fetch itself is unscoped; the safety net is a
manual post-hoc equality check, not structural scoping.

**Failure scenario:** Combined with F-04 (RLS COALESCE-to-legacy fallback) and
F-07/superuser-in-dev-and-CI (this audit's separate infra finding — see
`02-tenant-surface-matrix.md`), any Finance query issued without correctly-set
`app.organization_id` — whether from a bug, a partially migrated job, or a
maintenance script — silently operates against the legacy organization's
financial data (invoices, payments, credit ledger, entitlements) rather than
failing. Any *future* call site added to the unscoped `Finance.get_invoice/1`
delegate that omits the manual post-hoc check would be a direct, unmitigated
cross-tenant IDOR on financial records — the single most severe category named
in the audit brief.

**Impact:** Finance is the highest-scrutiny domain per the audit brief
("perform an especially strict review"); it is also the domain with the
weakest defense-in-depth in the entire codebase. The only thing currently
preventing exploitation is (a) the two known controller call sites happening to
add a manual guard, and (b) RLS being technically "enforced" per
`mix milos.tenancy.audit` — but RLS enforcement for Finance has never been
exercised by any test, because tests run as a Postgres superuser (see
`02-tenant-surface-matrix.md` / `08-test-gap-plan.md`), which unconditionally
bypasses RLS regardless of `FORCE ROW LEVEL SECURITY`.

**Production data risk:** Cannot be ruled out without a live, read-only audit
of production financial rows for legacy-org attribution anomalies — see
`07-read-only-diagnostic-queries.sql` query 4.

**Recommended remediation direction:** Add an explicit `scoped_to_tenant/1`
(mirroring Messaging/Gamification) to every Finance query function; remove the
unscoped `Finance.get_invoice/1` 1-arity delegate or make it require a context
argument; make `get_finance_settings/0` take `organization_id` and filter
explicitly, replacing the singleton `limit: 1` pattern (multi-tenant finance
settings should never be a single unscoped row).

**Recommended validation test:** Two-organization Finance isolation test:
create invoices/settings for Org A and Org B; from an Org-B-authenticated
context, attempt `Finance.get_invoice(org_a_invoice_id)` via every public
Finance API function (not just the controller); expect rejection or `nil`
for every one, run under a **non-superuser** database role (see F-08).

---

## F-06 — Tenant admin can issue a valid `owner`-role invitation with no role-ceiling check (privilege escalation)

**STATUS (2026-08-06): FIXED.** Product decision (explicitly asked, not
inferred): an account can never grant a role more privileged than its own,
applied uniformly across owner/admin/coach/member/athlete, not just at the
admin/owner boundary. `MembershipPolicy.can_grant_role?/2` implements this
via the existing `@roles` ordering, wired into `IssueInvitation` as a check
ahead of persisting the invitation. Verified failing-then-passing: an admin
inviting an owner is rejected with `{:error, :role_ceiling_exceeded}` (403
`role_ceiling_exceeded` at the HTTP layer), while an admin inviting up to
admin, and an owner inviting a peer owner, both still succeed.

**Severity:** Critical · **Confidence:** Confirmed (read directly)
**Invariant affected:** "Gym administrators must not be able to escalate themselves or another account into a role equal to or greater than their own."

**Evidence:** `apps/api/lib/milos_training/organizations/commands/issue_invitation.ex:12-24`:
```elixir
def call(context, params, issued_at) do
  with :ok <- TenantAuthorization.authorize(context, [:owner, :admin]) do
    ...
    invitation_params = %{
      organization_id: context.organization_id,
      ...
      role: normalize_role(value(params, :role)),
      ...
```
`TenantAuthorization.authorize/2` only checks that the **issuer** holds
`:owner` or `:admin`; `normalize_role/1` only validates the requested role is
a member of `MembershipPolicy.roles()` (all five tenant roles, including
`:owner`) — there is no comparison of the requested role against the issuer's
own role. `MembershipPolicy.can_manage_invitations?/1`
(`apps/api/lib/milos_training/organizations/domain/membership_policy.ex:11`)
exists and would be a natural place to encode a ceiling check, but it is
**dead code** — confirmed by repo-wide grep, its only callers are its own unit
test. No test anywhere exercises "an admin issues an owner invitation" — the
gap is both unenforced and untested.

**Failure scenario:** A tenant `admin` (deliberately given lesser authority
than `owner` by product design) calls `POST
/api/org/:organization_slug/invitations` with `{"role": "owner"}`. The
resulting invitation is fully valid, redeemable by any account (further
compounded by F-11), and grants full tenant-owner authority — either to a
second account the admin controls (self-escalation) or to an accomplice. This
directly matches the audit brief's explicit required test case: "gym admin
cannot assign roles equal to or greater than their own."

**Impact:** Full within-tenant privilege escalation from `admin` to `owner`,
reachable by any account an org owner has ever granted `admin` to. Cannot
escalate to a *global*/platform role (the role set is restricted to tenant
roles), so this does not cross the tenant/platform boundary, but it fully
defeats the intended `owner` > `admin` hierarchy within a tenant.

**Recommended remediation direction:** In `IssueInvitation.call/3`, reject
(or clamp) any requested `role` that exceeds the issuer's own membership role
in the role hierarchy `owner > admin > coach > member/athlete`. Wire
`MembershipPolicy.can_manage_invitations?/1` (or a new ceiling-check function)
into this command and add the missing test.

**Recommended validation test:** An `admin`-role member issues an invitation
with `role: "owner"`; the command must reject it. Repeat for `admin` issuing
`admin` (should also be rejected per "equal to or greater than their own"
unless product intends admins to create peer admins — confirm with product,
but the current code enforces neither restriction).

---

## F-07 — Dev, test, and CI database connections run as PostgreSQL superuser, which unconditionally bypasses Row-Level Security (CONFIRMED NOT to extend to production)

**STATUS (2026-08-06): FIXED for verification integrity.** Three pieces
landed: (1) `test/support/rls_case.ex` — a reusable `ExUnit` case template
(`MilosTraining.RLSCase`) that self-provisions a dedicated non-superuser,
non-BYPASSRLS Postgres role and hands tests a raw `Postgrex` connection that
genuinely enforces RLS; (2) `MilosTraining.Infrastructure.Tenancy.PrivilegeGuard`,
a boot-time check wired into `MilosTraining.Application.start/2` that queries
`rolsuper`/`rolbypassrls` for the running connection and **raises (refuses to
boot) if the app is running in `:prod` with a superuser/bypassrls
connection**; it only warns outside prod, since dev/test/CI are expected to
run as superuser today; (3) a genuine RLS-enforcement test added for every
T4 context that previously had none: Execution (F-23, from the earlier fix),
Scheduling (`class_types`), Messaging (`messaging_threads`), Workouts
(`master_workouts`), Feedback (`reviews`), Analytics (`analytics_events`),
Gamification (`seasonal_challenges`), and Finance (`memberships`) — 8 tests
total, each proving cross-org access and no-context access both return zero
rows via a real non-superuser connection, not the superuser-backed suite. To
confirm these tests are meaningful and not just always-green, one
(`messaging_threads`) was verified to genuinely fail when RLS was manually
disabled on that table, then restored and reconfirmed green. **Deliberately
not done, and reasonably out of scope for "fully fix":** a dedicated CI job
that provisions the non-superuser role ahead of time rather than each test
self-provisioning it idempotently on first use — functionally equivalent for
correctness, but the self-provisioning approach means the very first test in
a fresh CI run pays a small one-time role-creation cost instead of a
separate pipeline step doing it up front.

**Severity:** Critical for dev/test/CI's verification integrity (undermines confidence in every RLS-based claim in this audit and in TD-038) · **Downgraded to Informational for production specifically, per live verification below** · **Confidence:** Confirmed (live `pg_roles` query against both the local dev DB and, on 2026-08-05, live production)
**Invariant affected:** "Do not treat passing tests as proof of tenant isolation."

**Production verification update (2026-08-05):** Read-only query executed
against the live production database via the running `milos-api` pod's own
Ecto/Repo connection (Kubernetes namespace `tenant-m4`; see
`10-production-verification.md`):
```
SELECT current_user, rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user;
-- app | false | false
```
**Production's runtime connection is confirmed to be a non-superuser,
non-BYPASSRLS role** (`app`, the CloudNativePG-managed application-owner
role). Both the migration `initContainer` and the runtime `api` container in
`milos-api.yaml` use the same `milos-db-app` secret — there is no separate
elevated migration role, but critically there is also **no
`milos-db-superuser` secret present in the cluster at all**, meaning neither
migrations nor runtime traffic have superuser access in this deployment. This
directly resolves the open question flagged in this audit's original
executive summary ("this audit could not access production and cannot rule
out the dev/CI superuser misconfiguration also existing there") — **it does
not exist in production.** RLS is genuinely active and enforced (subject to
each individual policy's own correctness, per F-04/F-05/F-21/F-22/F-23) for
real production traffic. The dev/test/CI gap below remains fully valid as a
**verification-integrity** finding (nothing in automated testing has ever
exercised RLS, so a *regression* could ship undetected), but it is no longer
evidence that production itself is unprotected.

**Evidence:** `apps/api/config/dev.exs:5-6`, `apps/api/config/test.exs:9-10`
default `DB_USER`/`DB_PASSWORD` to `postgres`/`postgres`.
`.github/workflows/ci.yml:15-16,36,44` provisions a `postgres:16-alpine`
service with `POSTGRES_USER: postgres` and sets `DB_USER: postgres` for the
test job (confirmed independently during this audit). Live query against the
local dev database used throughout this audit:
```sql
SELECT rolname, rolsuper, rolbypassrls FROM pg_roles;
-- postgres | t | t
```
The non-owner `milos_runtime` role documented in
`docs/operations/tenant-lifecycle-and-recovery.md:9-28` and provisioned by
`ops/postgres/init/010-milos-runtime-role.sh` **does not exist** in this
database. `docker-compose.yml`'s `api` service (line 7) *does* correctly wire
`DATABASE_URL` to `milos_runtime`, so a properly deployed instance where an
operator has run `provision_postgres_runtime_role.sh` and set
`DB_RUNTIME_PASSWORD` would connect as a non-superuser at runtime — but nothing
in CI or automated testing exercises that configuration, and there is no
automated check that fails a deploy if the runtime role is missing or is
accidentally a superuser/has `BYPASSRLS`.

PostgreSQL superusers bypass RLS unconditionally, regardless of `FORCE ROW
LEVEL SECURITY`. Consequently: **every** `tenant_isolation_test.exs` file in
the suite (Finance, Messaging, Gamification, Analytics, Scheduling, Feedback,
Workouts) — all of which passed when run during this audit — has never
actually exercised RLS as an enforcement mechanism. They validate the
application-layer `where` clauses only, wherever those exist (and per F-05,
Finance largely doesn't have any).

**Failure scenario:** A future code change accidentally removes or weakens an
RLS policy, or removes an application-layer predicate in a context that (like
Finance) has no independent app-layer check. The full test suite still passes,
because it runs as superuser and was never actually gated by RLS. The
regression ships to production, where — *if* the runtime role is correctly
provisioned — RLS alone might still catch it, or might not, and nobody would
know until a real cross-tenant incident occurs.

**Production data risk:** Cannot be assessed from code alone; requires
confirming in production that `milos_runtime` (a) exists, (b) is the role the
API actually connects as, and (c) has `rolsuper=false` and
`rolbypassrls=false`. See `07-read-only-diagnostic-queries.sql` query 1 — this
should be the **first** query run against any production-adjacent environment
before trusting any other finding's "RLS enforced" conclusion.

**Recommended remediation direction:** Add a CI/test-suite step (or a
`mix milos.tenancy.audit`-adjacent task) that runs the isolation test suite (or
at least a representative subset) against a genuinely non-superuser,
non-BYPASSRLS role, so RLS is actually exercised by automation. Add a
production readiness/health check that queries `pg_roles` for `current_user`
and fails startup (or pages) if `rolsuper`/`rolbypassrls` is true.

**Recommended validation test:** A CI job that connects with the same
privilege class production uses, runs a subset of `tenant_isolation_test.exs`
files, and additionally attempts a raw cross-tenant `SELECT` with no ORM
involved, expecting zero rows.

---

## F-08 — `users` table has an RLS policy defined but Row-Level Security was never enabled for it


**STATUS: FIXED 2026-08-07 (P3.3).** `users_owner_policy` dropped rather than enabled - it had never been active, and `id = app.user_id` would break login, tenant resolution and the admin directory. `users` is application-layer-only by design and the audit task now reports that exemption explicitly.
**Severity:** High · **Confidence:** Confirmed (live `pg_class`/`pg_policies` query)

**Evidence:** Policy `users_owner_policy` created in
`apps/api/priv/repo/migrations/20260803223000_add_t4_ownership_foundation.exs:202-206`,
but no migration anywhere calls `ALTER TABLE users ENABLE ROW LEVEL SECURITY`.
Live confirmation: `pg_class.relrowsecurity = false` for `users`, while
`pg_policies` still lists the inert policy.

**Failure scenario:** Any query against `users` (a global-personal/global
authentication table, but one containing PII: nicknames, password hashes,
security version, calendar tokens) is unaffected by the defined policy — it
was never load-bearing. Whether this matters depends on whether any
application code relied on this policy as its scoping mechanism (own-account
access is normally enforced at the application layer via `current_resource`),
but a policy that looks active in `pg_policies` and is not is a dangerous
false sense of security, and directly explains why `mix milos.tenancy.audit`
(which doesn't check `users` at all — it's absent from `@ready_tenant_tables`/
`@ready_personal_tables`) never caught it.

**Recommended remediation direction:** Either enable RLS for `users` with the
existing policy (after confirming its predicate is correct for the app's
own-account access patterns) or remove the orphaned policy and document that
`users` is intentionally protected at the application layer only.

**Recommended validation test:** Add `users` to `mix milos.tenancy.audit`'s
checked table list so a future regression here is caught automatically.

---

## F-09 — Frontend admin console has no organization identifier in the URL; tenant scoping depends entirely on a shared, mutable `localStorage` key and an attacker-controllable request header

**STATUS: FIXED (2026-08-06), with one gap noted below.** Discovered
`apps/web/src/proxy.ts` already transparently rewrites any
`/org/:slug/<path>` request to serve the page at `<path>` (it strips the
`/org/:slug` prefix and rewrites, browser URL bar unaffected) - so the admin
console's page files under `src/app/admin/*` did **not** need to move; they
were already reachable at both `/admin/*` and `/org/:slug/admin/*`. What was
actually missing was every in-app navigation source producing a
slug-prefixed URL in the first place:

- `organization-selector.tsx`'s switch handler pushed to bare `/admin` for
  admin-capable roles, unconditionally dropping the org slug on every
  switch - this was the direct cause of the cross-tab-bleed failure
  scenario. Now pushes to `/org/:slug/admin` and calls `queryClient.clear()`
  on every switch (chosen over per-key `staleTime`/namespace surgery across
  ~164 query keys - see "gap" below).
- `TopNav.tsx`'s admin nav links, the dashboard dropdown, and its
  active-path matching now resolve and preserve the current organization
  slug (path → `localStorage` → first membership - the same fallback chain
  `organization-selector.tsx` already used) so navigating between admin
  sections keeps the URL, and therefore `apiRequest`'s tenant resolution,
  pinned to the organization the user is actually in.

**Gap not closed:** `queryClient.clear()` on switch closes the practical
stale-cross-tenant-data risk the finding's evidence described, but it is a
blunt instrument (clears everything, not just the switched org's data) and
doesn't address the ~10 component files (`AdminDashboard.tsx`,
`admin-finance.tsx`, `AdminUserProfile.tsx`, etc., ~80+ occurrences) that
still build **internal deep links** with bare `/admin/...` hrefs (e.g. a
user-profile panel linking to `/admin/workouts`). Clicking one of those
drops the user out of the `/org/:slug/...` URL space back to bare `/admin`,
where `apiRequest` correctly falls back to `localStorage`/JWT (not a
regression from today's behavior, and correct in the common single-org-per-
user case), but it reopens the cross-tab-bleed window for multi-org users
until they navigate via a TopNav link again. Backend-generated deep links in
push notifications (`push_message_builder.ex`,
`admin_profile_policy.ex`) have the same bare-path gap. Systematically
slug-prefixing every internal admin link was judged disproportionate to
finish in this pass; tracked as follow-up in the roadmap.

**Severity:** High · **Confidence:** Confirmed (frontend code read directly)
**Invariant affected:** ADR-058's `/org/:slug` path-identifies-context model; "changing tenants must not leave data from the previous tenant visible or actionable."

**Evidence:** `apps/web/src/app/admin/*` (users, finance, class-schedule,
workouts, settings, metrics, coaching-assignments, etc.) has **no organization
slug anywhere in its route paths**. The only thing scoping every `/admin/*`
request to a tenant is `apps/web/src/api/client.ts:52-86`
(`organizationSlugForRequest()`), which resolves the org as: **(a)** URL path
`/org/:slug` (never present under `/admin`) → **(b)** `localStorage["milos:selected-organization-slug"]`
→ **(c)** first membership in the decoded JWT — then sends it as the
`X-Organization-Slug` header (this is the exact header trusted server-side per
F-01). `apps/web/src/lib/realtime.ts:42-48` resolves the WebSocket's org via a
**different** fallback chain (URL path → JWT-first-membership, no
localStorage), meaning REST and realtime can target different organizations
simultaneously after a switch.

**Failure scenario (cross-tab bleed):** A platform owner or multi-org admin has
two browser tabs open to `/admin`. Switching organizations in tab 1 (via
`organization-selector.tsx:106` or the platform "open organization" action)
overwrites the single shared `localStorage` key. Tab 2's next `/admin` request
silently targets the new organization without any user action in tab 2.

**Failure scenario (stale cache):** `apps/web/src/components/organization-selector.tsx:100-116`
only writes `localStorage` and navigates — it never calls
`queryClient.invalidateQueries()`/`resetQueries()` (confirmed by grepping every
`invalidateQueries` call site — none fire on org switch). Combined with global
TanStack Query `staleTime: 15_000` (`components/query-provider.tsx:8-18`) and
**zero organization-scoped query keys anywhere in the app** (164 `queryKey:`
usages inspected, none include an org id/slug), a user who switches from Org A
to Org B and lands on `/admin` within 15 seconds sees **Org A's cached
finance/user/settings data rendered under Org B's UI** until the next
background refetch.

**Impact:** Real, demonstrable frontend data-leakage/data-confusion bug for
financial and member data, not merely a UX nit. Server-side authorization
(where it correctly re-validates membership) still prevents a genuine
unauthorized *write*, but a user can visually see and act on the wrong
tenant's data in the interim, and the underlying architectural pattern is what
makes F-01 possible on the backend (the header this UI sends is the header
the backend trusts as a fallback).

**Recommended remediation direction:** Migrate `/admin/*` routes to
`/org/:slug/admin/*` (paired with the backend fix in F-01); include
organization id/slug in every TanStack Query key under the admin surface; call
`queryClient.clear()` or targeted `invalidateQueries` on every organization
switch; unify the REST and WebSocket org-resolution logic into one shared
source of truth.

**Recommended validation test:** Switch organizations, then within the
`staleTime` window navigate to an admin page that was previously rendered for
the old org; assert the UI does not render stale cross-tenant data before the
refetch resolves (or assert the cache was invalidated on switch, making this
scenario impossible).

---

## F-10 — `intended_email_digest` is computed and stored on every invitation but never checked during redemption


**STATUS: FIXED 2026-08-07 (P2.8).** Accounts gained a mandatory, unique email; invitations bound to an address are only redeemable by an account holding it.
**Severity:** Medium · **Confidence:** Confirmed (grep across the full write and read paths)

**Evidence:** Populated at issuance in all three invitation-creation paths
(e.g. `issue_invitation.ex:23`). Never read back: confirmed by repo-wide grep,
it appears only in write-side/schema-cast code and the OpenAPI
`intended_email` param. `apps/api/lib/milos_training/application/redeem_registration_invitation.ex:4`
(`def call(%{id: user_id}, token), do: Organizations.redeem_invitation(token,
user_id)`) and `EctoOrganizationStore.redeem_invitation/3` never compare it
against the redeeming account's email.

**Failure scenario:** Possession of the opaque token is sufficient to redeem it
as *any* authenticated account, or to register a brand-new account with an
unrelated email (registration doesn't even collect an email in the invited-user
flow) — not just the intended recipient. This matches ADR-057's literal wording
("possession of an unexpired token authorizes its intended registration") but
means the stored `intended_email_digest` field currently does nothing, which
is either an intentional design choice (manual distribution, so email
verification wasn't the point) or an oversight — worth an explicit product
decision either way, since a token that leaks in transit (manual delivery,
per TD-034) currently has no secondary binding to the intended person.

**Recommended remediation direction:** Either enforce the email match at
redemption when an `intended_email_digest` is present (allowing an explicit
opt-out for anonymous/manual distribution), or remove the unused field and
document that possession-only redemption is the intended model.

**Recommended validation test:** Issue an invitation with `intended_email`,
attempt redemption from an authenticated account whose email doesn't match;
assert the product's chosen policy (reject or explicitly allow) is what
actually happens.

---

## F-11 — No membership suspend/revoke command exists despite the schema's `status` enum implying one


**STATUS: FIXED 2026-08-07 (P2.2).** `Commands.SetMembershipStatus`, owner/admin gated with the F-06 ceiling and a self-change guard.
**Severity:** Medium · **Confidence:** Confirmed (grep across all Organizations commands/ports)

**Evidence:** `organization_memberships.status ∈ {invited, active, suspended,
revoked}` (`apps/api/lib/milos_training/organizations/organization_membership.ex`),
but no function in `organizations/commands/`, `organizations/ports/organization_store.ex`,
or the Ecto adapter transitions a membership to `suspended` or `revoked` —
confirmed by grep for `suspend_membership`/`revoke_membership` (zero results).
Only `update_membership_role/3` (role change) and `add_membership/1` exist.

**Failure scenario:** An organization currently has no way to de-authorize a
compromised, offboarded, or misbehaving member/admin/coach short of deleting
the underlying **global** `users` account — which would also remove that
person's access to every other organization they belong to and their
global-personal data (Journal, PRs). This is an availability/incident-response
gap more than a direct exploit, but it means "revoking a role invalidates or
refreshes effective authorization" (an explicit required test in the audit
brief) currently cannot be exercised at all.

**Recommended remediation direction:** Add `SuspendMembership`/`RevokeMembership`
commands, gated to `owner`/`admin` (with the same role-ceiling fix as F-06),
and ensure `TenantAuthorization.build/4`'s existing `authorized_status?/1`
check (already correctly restricted to `:active`) takes effect immediately.

**Recommended validation test:** Revoke a member's org membership; confirm
their next request to any tenant-scoped endpoint for that org is rejected.

---

## F-12 — No `platform_owners` revocation path exists


**STATUS: FIXED 2026-08-07 (P2.2).** `Organizations.revoke_vendor/1` and `mix milos.platform.revoke_vendor`, mirroring the grant task's shell-only surface.
**Severity:** Low-Medium · **Confidence:** Confirmed (grep across Organizations context)

**Evidence:** `grant_platform_owner/1` exists and is correctly restricted to the
`mix milos.platform.grant_owner` Mix task (no HTTP path, verified). No
`revoke_platform_owner` function exists anywhere. The `status` enum on
`platform_owners` (`active`/`revoked`) implies a revoke workflow that isn't
implemented.

**Impact:** Operational risk — offboarding a platform operator currently
requires direct database manipulation, which the audit brief's working
constraints (and this codebase's own architecture rules) treat as something to
avoid.

**Recommended remediation direction:** Add a symmetrical
`mix milos.platform.revoke_owner` Mix task using the same idempotent,
audited pattern as the grant task.

---

## F-13 — Coverage gaps in `mix milos.tenancy.audit` and `mix milos.architecture` make TD-038's "complete" claim materially overstated


**STATUS: FIXED 2026-08-07 (P2.7).** The audit now fails on any unclassified table carrying `organization_id` (which immediately found two), reports root tables and materialized views explicitly, and guards against the COALESCE fallback returning. `mix milos.architecture` covers all eleven context stores plus a materialized-view predicate check.
**Severity:** Medium (process/tooling — produces false confidence, not itself an exploit) · **Confidence:** Confirmed (source read directly)

**Evidence:** `apps/api/lib/milos_training/infrastructure/tenancy/audit.ex:4-29`
— `@ready_tenant_tables`/`@ready_personal_tables` are static, hand-maintained
lists; `organizations`, `organization_memberships`, `organization_settings`,
`users`, `user_pr_history`, `platform_owners`, and the three tenant-owned
materialized views (`finance_aggregates`, `coaching_aggregates`,
`weekly_leaderboard`) are absent from both lists, so the audit never inspects
them, and `@transitional_tenant_tables` is permanently `[]` — the gate can
never report an incomplete context by design, only tables someone remembered
to add to the "ready" list. `apps/api/lib/mix/tasks/milos.architecture.ex:57-80`
(`tenant_scope_violations/0`) hardcodes exactly two files
(`scheduling_store.ex`, `ecto_scheduling_store.ex`) and checks for two literal
substrings — it says nothing about Finance, Messaging, Notifications,
Gamification, Analytics, or Wellbeing, the six contexts TD-038 cites this task
as having validated.

**Failure scenario:** A developer reads `docs/technical_debt.md` TD-038 ("...
`mix milos.tenancy.audit` and `mix milos.architecture` pass") and reasonably
concludes RLS/tenant enforcement is fully verified for those six contexts. In
reality, passing those two tasks proves only that a hand-curated subset of
tables have the RLS booleans set and that two specific Scheduling files contain
two specific substrings — neither tool detects the COALESCE-to-legacy fallback
(F-04), the missing Finance predicates (F-05), the disabled `users` policy
(F-08), or the superuser test/CI gap (F-07).

**Recommended remediation direction:** Expand `@ready_tenant_tables`/
`@ready_personal_tables` to the full ownership inventory (including root
tenant tables and materialized views, with an explicit "platform-administered,
no per-row RLS expected" classification where appropriate rather than silent
omission); extend `mix milos.architecture`'s tenant-scope check beyond
Scheduling to every T4 context; add the COALESCE-fallback detection from F-04.

**Recommended validation test:** N/A directly (this is a tooling gap); its
resolution is validated by F-04/F-05/F-07/F-08's tests newly failing the
audit tooling until fixed, then passing once fixed.

---

## F-14 — No dedicated cross-tenant isolation test exists for Notifications, Wellbeing, or Coaching, despite TD-038 claiming "two-tenant tests" for adjacent contexts

**STATUS: FIXED 2026-08-07.** Added `coaching/tenant_isolation_test.exs`,
`notifications/tenant_isolation_test.exs`, and
`wellbeing/tenant_isolation_test.exs`. Coaching and the organization-scoped
Notifications paths verified clean. Writing the tests surfaced **two gaps the
finding did not anticipate** — see **F-28** below, one of which is a confirmed
cross-tenant read of medical data that survives RLS in production.

**Severity:** Medium · **Confidence:** Confirmed (directory listing + content grep)

**Evidence:** `apps/api/test/milos_training/` contains
`analytics/tenant_isolation_test.exs`, `feedback/tenant_isolation_test.exs`,
`finance/tenant_isolation_test.exs`, `gamification/tenant_isolation_test.exs`,
`messaging/tenant_isolation_test.exs`, `scheduling/tenant_isolation_test.exs`,
`workouts/tenant_isolation_test.exs`, and `execution/owner_isolation_test.exs`
— but **no** `notifications/`, `wellbeing/`, or `coaching/` equivalent.
Grepping the existing Coaching/Wellbeing/Notifications test files for
`cross.tenant|other_org|another_org|forged|organization_id` found only
`coaching_test.exs`/`admin_coaching_controller_test.exs` with any hits;
Notifications and Wellbeing test files matched nothing.

**Impact:** These three contexts' tenant-scoping correctness rests entirely on
code review and RLS (itself weakened by F-04/F-07), with no automated
regression protection against a future cross-tenant leak specific to their
query/command layers.

**Recommended remediation direction:** Add a `tenant_isolation_test.exs` for
each of Notifications, Wellbeing, and Coaching following the existing pattern
in Finance/Messaging/Gamification.

**Recommended validation test:** Two-organization isolation test per context:
create data in Org A and Org B, assert an Org-B-scoped read/write cannot touch
Org A's rows through any public context API function.

---

## F-15 — `execution` RLS policy includes session-GUC bypass flags (`app.admin_mode`, `app.execution_authorization_check`) that widen the trust surface


**STATUS: RESOLVED 2026-08-07.** Verified against the live policy: the `app.admin_mode` branch requires an active owner/admin/coach membership in the execution's *own* organization (F-23's fix), so the flag requests the widened policy but cannot grant it. `app.execution_authorization_check` is set only by `ExecutionStore.with_authorization_context/2`, reached from exactly two audited call sites. The flag is now also derived from the membership role wherever a tenant context exists.
**Severity:** Medium · **Confidence:** Reported by delegated research, not independently re-verified against the live migration text — recommend a follow-up read of `apps/api/priv/repo/migrations/20260804161500_allow_execution_admin_and_authorization_reads.exs` and `apps/api/lib/milos_training/infrastructure/execution/ecto_execution_store.ex:254-262` before acting.

**Evidence (as reported):** `scoped_to_user/1` in the execution store
deliberately returns an unfiltered query when `app.admin_mode == "true"` or
`app.execution_authorization_check == "true"` is set on the session, mirrored
by a corresponding RLS policy widening in the cited migration.

**Failure scenario:** Any code path that sets either GUC on a connection —
correctly or by mistake — gets full unscoped execution-record access at both
the application and database layer simultaneously, with no remaining backstop
for that session.

**Recommended remediation direction:** Confirm these flags are set only in
narrowly-scoped, audited admin/authorization code paths (not general request
handling); consider requiring the acting admin's own organization id as an
additional predicate rather than a blanket bypass.

**Recommended validation test:** Confirm no general-purpose request pipeline
sets `app.admin_mode`/`app.execution_authorization_check` by default.

---

## F-16 — Root tenant tables (`organizations`, `organization_memberships`, `organization_settings`, `organization_domains`, `registration_invitations`) have no Row-Level Security at all


**STATUS: RESOLVED 2026-08-07 (P3.4)** via the documented-exception route. RLS on the tenant root would be circular - resolving a tenant requires reading `organizations` and `organization_memberships` before any session GUC exists. They are reported under `platform_administered` by the audit task, and `unclassified_tables/0` fails the audit if a new tenant table appears unclassified.
**Severity:** Medium (defense-in-depth gap; these are platform-administered tables so application-layer scoping is the primary control) · **Confidence:** Confirmed (live query)

**Evidence:** Live `pg_class` query during this audit: `relrowsecurity=false,
relforcerowsecurity=false` for all five tables. This is architecturally
defensible (they are the tenant *root*, legitimately queried
cross-organizationally by platform-owner surfaces), but it means the second
layer of defense-in-depth ADR-056 describes is entirely absent here — a single
missing application-layer predicate in a future `organization_memberships`
query would have no RLS backstop at all, unlike every other tenant-owned
table.

**Recommended remediation direction:** Either add RLS scoped to
"platform-owner sees all, tenant member sees only their own org's row," or
explicitly document these tables as "application-layer-only by design" in the
ownership inventory so the exception is deliberate, not an oversight.

---

## F-17 — Materialized views are not covered by any RLS or by `mix milos.tenancy.audit`


**STATUS: FIXED 2026-08-07 (P2.7).** Materialized views are reported by the audit task with RLS marked inapplicable, and `mix milos.architecture` now fails any raw SQL naming one without an `organization_id` predicate - verified by injecting the F-22 regression.
**Severity:** Low · **Confidence:** Confirmed (`pg_matviews` cannot host RLS; audit script table list checked directly)

**Evidence:** `finance_aggregates`, `coaching_aggregates`, `weekly_leaderboard`
are tenant-owned per `docs/architecture/tenant-ownership-inventory.md` but
PostgreSQL cannot apply RLS to materialized views (confirmed: `relkind='m'`).
`coaching_aggregates` reads are explicitly filtered by `organization_id` in
`ecto_coaching_store.ex:9-22` (good), but this relies entirely on that one
call site remembering to filter — there is no structural backstop, and the
audit script doesn't track these views at all.

**Recommended remediation direction:** Add an explicit code-review/test
requirement that every read of these three views includes an
`organization_id` predicate; consider a lint rule or wrapper function that
makes an unscoped read impossible to write.

---

## F-18 — Un-scoped legacy-arity Scheduling/Workouts store functions are hardcoded to operate only against the legacy organization


**STATUS: LARGELY FIXED 2026-08-07 (P3.1).** Assignment archiving and the calendar feed now use organization-scoped arities. The legacy no-context arities remain for other callers and are labelled as such; note they resolve via a hardcoded `legacy-milos-training` slug that does not exist in production, so any surviving un-scoped path fails rather than silently reading another tenant.
**Severity:** Low (functional inequality for new tenants, not a security leak — RLS still bounds these calls to the legacy org) · **Confidence:** Confirmed (code comment + function inspection)

**Evidence:** `apps/api/lib/milos_training/workouts/workout_store.ex:10-11`:
> "Scoped variants are the tenant-aware public boundary. The legacy arities
> remain temporarily for jobs and callers still being migrated; RLS limits
> those to legacy."
Mirrored throughout `apps/api/lib/milos_training/scheduling/scheduling_store.ex`'s
un-scoped function arities.

**Impact:** Any Oban job or caller still using these legacy arities only
functions for the legacy organization — meaning newly onboarded tenants get
*zero* functionality from any unmigrated call site, an operational/functional
inequality against the "all gyms must have equal application-level
capabilities" invariant, even though it poses no cross-tenant leakage risk.

**Recommended remediation direction:** Track remaining legacy-arity call sites
as migration debt; migrate them to the tenant-aware arities before onboarding
additional non-legacy tenants that would depend on that functionality.

---

## F-19 — Realtime broadcast helpers silently default to the legacy organization when a payload omits `organization_id`

**STATUS: FIXED** (2026-08-06). The finding undersold the scope: every
booking/slot event relayed through `RealtimeEventHandler` (`booking_submitted`,
`booking_resolved`, `booking_timed_out`, `slot_created`, `slot_updated`,
`slot_deleted`) omitted `organization_id` unconditionally, not just as an edge
case — so schedule realtime events for every non-legacy organization were
being silently misrouted to the legacy org's PubSub topic. Fixed by threading
`organization_id` from the already-available `booking`/`slot`/`workout`
structs (all of which carry the field) into the PubSub payloads in
`realtime_event_handler.ex` and `publish_workout.ex`. The one remaining
legacy call path, `DeleteWorkout.call/1` (no tenant context, part of the
F-18 legacy-arity debt), now reads `organization_id` from the
`app.organization_id` session GUC via `RepoContext.current_setting/1` instead
of the admin DTO map (which doesn't carry that field at all). Chose
"log a warning, keep the fallback" over a hard raise, since the fallback is
still legitimately needed for that one remaining legacy-arity call site and a
raise there would turn a Medium silent-misrouting bug into a hard outage for
it. Covered by `test/milos_training/application/schedule_realtime_test.exs`.

**Severity:** Medium · **Confidence:** Confirmed (read directly)

**Evidence:** `apps/api/lib/milos_training_web/realtime.ex:5-15,52-54` and
`apps/api/lib/milos_training/application/schedule_realtime.ex:5-19`:
```elixir
organization_id =
  Map.get(payload, :organization_id) ||
    Map.get(payload, "organization_id") ||
    legacy_organization_id()
```
No log, no error — silent fallback.

**Failure scenario:** A future caller that forgets to include
`organization_id` in a broadcast payload has its event routed to the legacy
org's PubSub topic instead of failing visibly, hiding the underlying bug
(topic names are per-org, so this is not a cross-tenant data leak, but it is
a silent-failure pattern the audit brief explicitly asks to be treated with
suspicion).

**Recommended remediation direction:** Raise/log-and-drop instead of falling
back to the legacy org ID.

---

## F-26 — `ProcessWorkoutCompletionJob` fetches its execution record with no tenant/owner context; likely fails silently for every execution once Oban is enabled

**STATUS: FIXED** (2026-08-06). Confirmed by direct read exactly as
reported. `ExecutionStore.with_authorization_context/2` and the
`app.execution_authorization_check` RLS bypass clause on `workout_executions`
already existed for exactly this case, but `RepoContext.run/2` had no clause
that accepted `execution_authorization_check` without an accompanying
`organization_id`/`user_id` — the job's only identifying data is
`execution_id`, so calling it with an otherwise-empty context always hit
`{:error, :missing_ownership_scope}` and never reached the closure, meaning
the RLS bypass was reachable at the DB level but not from any Elixir call
site. Added the missing `RepoContext.run/2` clause and wired the job to use
`with_authorization_context/2`. Proved with two tests since an ordinary
`mix test` run (Postgres superuser, bypasses RLS) can't catch this class of
bug at all: a direct `RepoContext.run/2` unit test
(`test/milos_training/infrastructure/tenancy/repo_context_test.exs`), and an
`RLSCase`-based test against a real non-superuser connection showing the
execution is invisible without the GUC and visible with it
(`test/milos_training/execution/rls_enforcement_test.exs`).

**Severity:** Medium (functional regression, not a leak) · **Confidence:** Reported by delegated research, not independently re-verified — recommend confirming against `apps/api/lib/milos_training/workers/process_workout_completion_job.ex` and `execution/queries/get_execution.ex` directly before acting.

**Evidence (as reported):** `ProcessWorkoutCompletionJob` calls
`Execution.get_execution(execution_id)` (a plain `defdelegate` to
`GetExecution.by_id/1`) with no `RepoContext.run`/`with_user_context`
wrapper. Since `workout_executions` is FORCE-RLS with no session GUC set in
this path, the policy's `user_id =`/`organization_id =`/`admin_mode`/
`execution_authorization_check` branches are all false, so the query returns
`nil` and the job hits `{:cancel, :execution_not_found}` every time.

**Impact:** If accurate, the asynchronous gamification-completion pipeline
(streaks, achievements, challenge progress advancement) is dead whenever Oban
is enabled — a severe functional regression from the RLS rollout that was
not caught by any test (consistent with F-07/F-13's tooling-coverage gaps).

**Recommended remediation direction:** Wrap the job's execution fetch in the
correct owner/tenant `RepoContext.run` context using the `user_id`/
`organization_id` already present in the job args.

**Recommended validation test:** Enqueue and run this job in a
test environment with Oban enabled (not `Oban.Testing` inline mode, which may
mask the RLS-context gap); confirm it successfully processes a real
execution rather than cancelling with `:execution_not_found`.

---

## F-27 — Shared, unfiltered Meilisearch member search index relies entirely on one call site's post-filter for tenant isolation

**STATUS: FIXED** (2026-08-06). Confirmed by direct read exactly as
reported, including the dead-code `call/1` no-filter fallback and the
correct `MeilisearchPRIndex` pattern to mirror. Added a bulk
`Organizations.list_membership_organization_ids/1` query, tagged every
search document with `organization_ids`, added it as a filterable
attribute, and `AdminSearchUsers.call/2` now passes the caller's
`organization_id` into the index filter so isolation is enforced at the
query layer — the existing post-filter stays in place as defense-in-depth,
not removed. Real Meilisearch isn't reachable in this environment (no
running instance), so this couldn't be proven end-to-end over HTTP; instead
proved with two narrower tests that don't need it: the existing
fake-index (`OrgCapturingIndex`) pattern already used by
`admin_search_users_test.exs`, confirming `organization_id` actually reaches
the search params, and a direct test of `AdminMemberSearchDocuments.build_all/0`
confirming documents carry the right `organization_ids`.

**Severity:** Medium · **Confidence:** Reported by delegated research, not independently re-verified — recommend confirming against `apps/api/lib/milos_training/infrastructure/search/meilisearch_member_index.ex` and `application/admin_search_users.ex` directly.

**Evidence (as reported):** `MeilisearchMemberIndex` uses one platform-wide
index (`admin_members`) with no organization-filterable attribute; tenant
isolation is enforced only by `AdminSearchUsers.call/2` post-filtering
results down to the caller's own org members after the search returns. A
context-less `call/1` fallback exists with no filtering (currently dead code,
no live call site). Contrast with `MeilisearchPRIndex`, which correctly
enforces scoping at the query layer via an index `filter:
"user_id = \"..."` expression.

**Failure scenario:** Any future caller of the member search index that
skips the `AdminSearchUsers` post-filter step — a new endpoint, a script, a
different application service — would return cross-tenant member PII
(nickname, membership status, package info) with no structural protection
against it.

**Recommended remediation direction:** Add an `organization_id` filterable
attribute to the Meilisearch index and filter at the query layer, mirroring
the PR index's pattern, rather than relying solely on an application-layer
post-filter with a single correct caller.

**Recommended validation test:** Call the underlying index search function
directly (bypassing `AdminSearchUsers`) with a cross-tenant query; assert it
either requires an org filter parameter or returns no results without one.

---

## F-20 — JWT `"memberships"` claims can go stale after a role/membership change with no automatic invalidation (informational)


**STATUS: FIXED 2026-08-07 (P3.5)** by removing the claim rather than refreshing it. It was never read back - not for authorization, not by the client - and embedded the account's full organization/role list in a credential that gets logged.
**Severity:** Low (confirmed cosmetic/UI-only, not an authorization bypass) · **Confidence:** Confirmed (read directly)

**Evidence:** `apps/api/lib/milos_training/infrastructure/auth/guardian_token_issuer.ex:21-32`
embeds a `"memberships"` claims array at token-issue time; confirmed by
repo-wide grep that it is **never read back for authorization** anywhere
(`TenantContext` is always rebuilt from live DB state per request). Role
changes trigger a best-effort `"role_changed"` realtime broadcast
(`application/update_user_role.ex:38-48`) but not token reissuance;
`security_version` (the actual invalidation mechanism) is bumped only by
explicit `sign_out_all_devices`. Additionally, `guardian.ex:34-37` accepts
tokens with **no `"sv"` claim at all** for any user whose `security_version`
is still `1` (the default for accounts that have never called
`sign_out_all_devices`) — broader acceptance than strictly necessary, though
still requires a validly signed JWT.

**Impact:** UI navigation (e.g. which orgs appear in a switcher) can lag a
real membership/role change until natural token refresh; server-side
authorization is unaffected since it never trusts these claims.

**Recommended remediation direction:** Consider triggering token reissuance
(not just a realtime broadcast) on membership/role change for UX freshness;
low priority given no security impact.

---

## F-28 — Owner-scoped reads are not constrained by the tenant boundary: a member reads their own records across every organization they belong to


**STATUS: RESOLVED 2026-08-07.** Product decision: personal records follow the member across organizations. The Wellbeing owner branch is intentional and documented as the tenancy model's one sanctioned cross-organization read; the notification inbox stays cross-organization but now carries its origin so the client can flag it. The admin-facing injury list and analytics summary were split onto a fail-closed `scoped_to_tenant/1` - a real defect this finding had folded in with the product question.
**Severity:** High for `injury_reports` (medical data, confirmed to survive RLS
in production); Medium for `notifications` · **Confidence:** Confirmed
(reproduced under real non-superuser RLS in
`apps/api/test/milos_training/wellbeing/rls_enforcement_test.exs`)

**Discovered:** 2026-08-07, while implementing F-14's isolation tests. Not
anticipated by F-14, which assumed these contexts were correct-but-untested.

### Wellbeing (`injury_reports`) — confirmed cross-tenant read

Both the application layer and the RLS policy express the owner/tenant scope as
a disjunction, and the two are **identical**, so neither constrains the other:

`apps/api/lib/milos_training/infrastructure/wellbeing/ecto_wellbeing_store.ex`
(`scoped_to_owner_or_tenant/1`):

```elixir
where(query, [row], row.user_id == ^user_id or row.organization_id == ^organization_id)
```

`injury_reports_owner_or_tenant_policy`
(`priv/repo/migrations/20260804160000_finalize_personal_and_wellbeing_t4_boundaries.exs`):

```sql
USING (
  user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
  OR organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
)
```

Because `list_injuries_for_user/1` and `get_injury_for_user/2` then add an
explicit `user_id == ^user_id` filter, the whole predicate collapses to the
owner branch and the organization term never applies.

**Failure scenario (reproduced):** a member belongs to Org A and Org B and has
filed an injury report in each. Reading with only Org B open returns **both**,
including Org A's. `get_injury_for_user/2` likewise returns the Org A record by
ID — a cross-tenant IDOR on medical data.

**Why RLS does not save this:** the policy carries the same `OR`, so the leak is
present in production against a correctly-provisioned non-superuser role. This
is materially different from F-05, where RLS was at least a partial backstop.

**Does not affect the admin path:** when an admin reads a member's dossier, the
owner branch (`user_id = <admin>`) cannot match the member's rows, so the
organization term is the only one that can satisfy the predicate and scoping is
correct. Confirmed by test.

### Notifications — same shape, lower blast radius

Every inbox read in
`apps/api/lib/milos_training/infrastructure/notifications/ecto_notification_store.ex`
(`list_for_user/1`, `list_inbox_page/2`, `count_unread_inbox/1`,
`mark_all_read/1`, `mark_read/2`) applies `scoped_to_user/1` but never
`scoped_to_organization/1` — which exists in the same module and is used at
exactly one call site (`delete_booking_pending_for_booking/1`). A member's inbox
therefore spans organizations, surfacing Org A notification titles/bodies in an
Org B session.

**Impact:** Cross-tenant disclosure of personal health records (Wellbeing) and
of notification content (Notifications). For a gym operator this is
member-identifiable health data crossing a customer boundary.

### Requires a product decision before remediation

The correct boundary is **not** self-evident, which is why this is filed rather
than fixed:

- **Partition per tenant** — a member's records belong to the organization they
  were filed in. Strictest, matches the rest of the tenancy model, but changes
  what existing users see and needs a backfill story for records already filed.
- **Follow the member** — health records are the member's own data, deliberately
  portable across the gyms they attend. Defensible for a health record, harder
  to defend for notifications, and needs an explicit exemption in the tenancy
  model rather than an accidental `OR`.

**Recommended remediation direction (assuming partition-per-tenant):** change
both layers together — `AND` the organization term rather than `OR`-ing it in
`scoped_to_owner_or_tenant/1`, add `scoped_to_organization/1` to the
notification inbox reads, and ship a migration replacing
`injury_reports_owner_or_tenant_policy` (and the matching
`injury_status_events` policy). Shipping only the application-layer half would
leave the policy permissive; only the policy half would break self-service reads
where no organization is open.

**Validation tests:** already written and currently asserting the *unfixed*
behaviour, tagged `:documents_current_behaviour` —
`wellbeing/tenant_isolation_test.exs`, `notifications/tenant_isolation_test.exs`,
and `wellbeing/rls_enforcement_test.exs`. Flipping those assertions to `refute`
is the regression test for the fix.

---

## F-29 — Tenant admin can change any account's **global** role, for accounts outside their organization, with no role ceiling

**STATUS: FIXED 2026-08-07 (P1.8).**

**Severity:** High (cross-tenant privilege escalation + IDOR) · **Confidence:**
Confirmed (read directly, then reproduced in
`apps/api/test/milos_training/organizations/set_membership_role_test.exs`)

**Discovered:** 2026-08-07, while auditing what still reads the global
`users.role`. Not in the original audit.

**Evidence:** `PATCH /api/org/:organization_slug/admin/users/:id/role` is
mounted under the `admin_only` pipeline and called
`Application.UpdateUserRole.call/2`, which resolved the target with
`Identity.find_by_id(user_id)` and then wrote `users.role` via
`Identity.update_role/2`.

Three separate failures in one endpoint:

1. **No membership check.** The target was looked up by id alone. A tenant
   admin could change the role of an account that had never been a member of
   their organization — an IDOR across the whole user table.
2. **No role ceiling.** Nothing compared the requested role against the
   acting admin's own. An `admin` could grant `admin`, or demote an `owner`,
   contradicting the F-06 product decision that an account may never grant a
   role more privileged than its own.
3. **Global effect.** `users.role` is account-wide, so a change made by Org A's
   admin applied to the account in **every** organization it belonged to.

**Failure scenario:** an admin of Org A issues
`PATCH /api/org/org-a/admin/users/<victim>/role {"role": "admin"}` for an
account whose only membership is in Org B. The account becomes globally
`:admin`, which Org B's surfaces then honour.

**Root cause:** role was modelled twice — `users.role` (account-wide) and
`organization_memberships.role` (per organization) — and the admin-facing
endpoint wrote the wrong one. The tenancy model treats role as a property of a
membership; this endpoint treated it as a property of the account.

**Remediation applied (2026-08-07):** replaced with
`Organizations.Commands.SetMembershipRole`, which:

- resolves the target's membership **within `context.organization_id`**, so an
  account outside the acting organization has no membership to find and gets
  `:not_found`;
- applies `MembershipPolicy.can_grant_role?/2` against **both** the requested
  role and the target's current role, so an admin can neither promote above
  themselves nor demote an owner;
- refuses self-change, matching F-11's lockout guard;
- carries over the previous role's state reconciliation (cancelling future
  bookings when leaving `:member`, archiving assignment access when leaving
  `:athlete`), now scoped to the acting organization.

`UpdateUserRole` and its route binding were deleted outright — there is no
longer any admin-facing path that writes the global role.

**Residual:** assignment archiving still calls a legacy un-scoped arity
(`Workouts.archive_active_assignments_for_athlete/1`) and so still reaches
across organizations. Marked `TODO(F-18)` in the source and tracked under P3.1.

**Also fixed under this finding:** `GetScheduleCalendar.booking_nickname_cache/2`
decided whether to expose other members' nicknames from the global account
role, bypassing the `admin_role?/2` helper beside it that correctly prefers the
tenant membership role.

**Still reading the global role (lower severity, not cross-tenant leaks):**
`GetLeaderboardSnippet` (admins see the leaderboard regardless of opt-in — the
leaderboard data itself is org-scoped since P0.1, so this grants a visibility
perk, not another tenant's data) and `GetCalendarFeed` (token-authenticated,
no tenant context in scope; its real problem is the un-scoped
`Scheduling.get_calendar_week/1` arity, i.e. F-18). Both are tracked under
P3.1 rather than left silent.
