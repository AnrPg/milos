# Remediation Roadmap

Date: 2026-08-05. **This is a backlog, not an implementation — nothing here
was implemented as part of this audit.** Priorities reflect severity plus
practical dependency ordering. "Tests required before merge" references the
specific tests in `08-test-gap-plan.md`.

## P0 — Hotfix immediately (confirmed live cross-tenant leaks / IDOR)

**STATUS (2026-08-06): P0.1 and P0.2 are both fixed, migrated locally, and
tested (full 575-test suite green, including new tenant-isolation tests for
all three findings). Not yet deployed to production.** See `04-findings.md`
F-21/F-22/F-23 for exact migrations, code changes, and how each was verified.
A residual gap remains in F-22 (`prs_this_month` stays globally scoped since
`user_achievements` carries no `organization_id`) — tracked as follow-up, not
blocking. P1–P3 remain open.

### P0.1 — Fix `finance_aggregates` and `weekly_leaderboard` unfiltered materialized-view queries (F-21, F-22)
- **Dependency:** none — can ship independently of everything else.
- **Affected modules:** Finance (`ecto_finance_store.ex financial_summary/1`), Gamification (`ecto_gamification_store.ex get_leaderboard/2`).
- **Approach:** Add `organization_id` predicate to both raw SQL queries, sourced from `RepoContext.current_setting("app.organization_id")`, mirroring the existing correct `coaching_aggregates`/`meilisearch_pr_index.ex` patterns. Add an organization-membership gate to the leaderboard route (currently `:user_only` with no tenant check at all).
- **Tests required before merge:** test-gap-plan #1, #2.
- **Deployment considerations:** Hotfix-only release; consider whether an incident notification to affected tenants is warranted given confirmed live exposure — a product/legal decision outside engineering scope.

### P0.2 — Fix Execution `admin_mode` RLS bypass being org-blind (F-23)
- **Dependency:** none.
- **Affected modules:** Execution (`repo_context.ex maybe_put_admin_mode/2`, the RLS policy in `20260804161500_...exs`, `get_workout_execution.ex`).
- **Approach:** Replace the blanket `admin_mode = true` bypass with an organization-scoped predicate; require the acting admin to hold an active coach/admin membership in the target execution's organization (mirror `active_athlete_membership?/2` from Coaching).
- **Tests required before merge:** test-gap-plan #3.

## P1 — High priority, land within the next few releases

### P1.1 — Remove RLS COALESCE-to-legacy-org fallback (F-04) — **FIXED 2026-08-06**, see `04-findings.md`. Column DEFAULTs intentionally left in place, gated on P2.3/P2.4.
- **Dependency:** must land before P1.2 (Finance predicates) is meaningful, and before any Phase 7 constraint-tightening in the retirement plan.
- **Affected modules:** every enforce-stage migration across Finance, Messaging, Notifications, Gamification, Analytics, Wellbeing, Feedback, Attendance.
- **Approach:** New migration replacing `COALESCE(session_var, milos_legacy_organization_id())` with bare `session_var` equality in every affected policy; drop the `DEFAULT milos_legacy_organization_id()` column defaults once no write path depends on them (verify via P2.3/P2.4's job fixes first, or sequence this after them).
- **Tests required before merge:** test-gap-plan #12, plus a full re-run of every existing `tenant_isolation_test.exs` (should still pass — they don't currently depend on the fallback for correctness, only for accidental leniency).
- **Deployment considerations:** This is a behavior change for any code path that was silently relying on the fallback — audit Phase 4 (backfill/repair) in `06-legacy-data-and-code-retirement-plan.md` should run first in a staging environment to surface any such dependency before production deploy.

### P1.2 — Add explicit application-layer tenant predicates to the Finance store (F-05) — **FIXED 2026-08-06**, see `04-findings.md`.
- **Dependency:** independent of P1.1, but most valuable once P1.1 removes the false safety net.
- **Affected modules:** `ecto_finance_store.ex` (all `Repo.get`/`Repo.one` call sites lacking `scoped_to_tenant`), `finance.ex` (remove or gate the unscoped 1-arity `get_invoice/1`).
- **Approach:** Mirror the `scoped_to_tenant/1` helper pattern already used correctly in Messaging/Gamification/Feedback/Workouts.
- **Tests required before merge:** new Finance IDOR-style tests (an Org-B context attempting to fetch an Org-A invoice/membership/subscription by ID via every public Finance function, not just the controller).

### P1.3 — Fix `IssueInvitation` role-ceiling check (F-06) — **FIXED 2026-08-06** (product decision: an account can never grant a role more privileged than its own, uniformly across all roles). See `04-findings.md`.
- **Dependency:** none.
- **Affected modules:** `organizations/commands/issue_invitation.ex`, `organizations/domain/membership_policy.ex` (wire up the existing `can_manage_invitations?/1` or add a proper role-ceiling comparator).
- **Approach:** Reject any requested `role` that exceeds (or, per product decision, equals) the issuer's own membership role.
- **Tests required before merge:** test-gap-plan #6, #16. **Requires a product decision first**: can an `admin` create peer `admin`s, or only `owner` can create `admin`s? Flag to product before implementing.

### P1.4 — Fix legacy `/api/admin/*` header-trust tenant resolution (F-01) + frontend org-in-URL migration (F-09) — **EXPAND PHASE ONLY, 2026-08-06**: backend mirror routes exist; frontend migration and legacy-route/header removal still open. See `04-findings.md`. **Before cutover**, also audit every mirrored controller's `operation/2` OpenApiSpex specs for the `organization_slug` `CastAndValidate` gap found and fixed for Messaging during F-25 (P2.4) — untested POST/PATCH mirrored routes likely reject every request today.
- **Dependency:** these two should ship together (backend without frontend migration breaks the admin console; frontend without backend fix doesn't remove the vulnerability).
- **Affected modules:** `router.ex`, `resolve_tenant_context.ex`, `me_controller.ex`, `apps/web/src/app/admin/*`, `apps/web/src/api/client.ts`, `apps/web/src/lib/realtime.ts`, `apps/web/src/components/organization-selector.tsx`.
- **Approach:** Introduce `/api/org/:organization_slug/admin/*` mirroring existing routes; migrate the frontend admin console to `/org/:slug/admin/*` URLs; remove the `x-organization-slug` header fallback and the legacy-org default from `ResolveTenantContext`; add `organization_id`/slug to every admin-surface TanStack Query key; invalidate/clear the query cache on organization switch; unify REST/WebSocket org-resolution into one shared source of truth.
- **Tests required before merge:** test-gap-plan #4, #11, plus a frontend integration test for the cross-tab/stale-cache scenarios described in F-09.
- **Deployment considerations:** Largest-surface-area change in this roadmap (~140 backend routes + the entire admin frontend). Recommend a feature-flagged parallel rollout (old and new routes coexist during migration) rather than a flag-day cutover, consistent with this codebase's existing expand/contract migration discipline.

### P1.5 — Add non-superuser RLS-enforcing test/CI lane (F-07) — **FIXED 2026-08-06**: `RLSCase` helper + boot-time `PrivilegeGuard` health check + a genuine RLS-enforcement test for all 8 T4 contexts (Execution, Scheduling, Messaging, Workouts, Feedback, Analytics, Gamification, Finance). See `04-findings.md`.
- **Dependency:** should land early since it makes every subsequent fix's tests actually trustworthy.
- **Affected modules:** `config/test.exs`, `.github/workflows/ci.yml`, possibly a new `docker-compose.test.yml` provisioning a `milos_runtime`-equivalent role for CI.
- **Approach:** Add a CI job (or extend the existing one) that provisions a non-superuser, non-BYPASSRLS role for at least the isolation-test subset; add a startup/health check that fails if the production runtime connection is a superuser or has BYPASSRLS.
- **Tests required before merge:** the health check itself needs a test (connect as superuser in a test harness, assert the check fails).

## P2 — Medium priority

### P2.1 — Add missing two-organization isolation tests: Notifications, Wellbeing, Coaching (F-14)
- **Dependency:** none; can proceed in parallel with anything else.
- **Tests required before merge:** test-gap-plan pattern applied to these three contexts.

### P2.2 — Add membership suspend/revoke commands (F-11) and platform-owner revoke task (F-12)
- **Dependency:** none.
- **Affected modules:** `organizations/commands/`, `organizations/ports/organization_store.ex`, Ecto adapter, a new `mix milos.platform.revoke_owner` task.
- **Tests required before merge:** test-gap-plan #18 (currently impossible to write — this item unblocks it).

### P2.3 — Fix Finance cron/Oban jobs to iterate per-organization (F-24)
- **STATUS: FIXED** (2026-08-06). Jobs now iterate active organizations and
  run scoped per-org. Also closed a cross-tenant `Repo.update_all`
  corruption vector discovered during remediation — see F-24 in
  `04-findings.md` for the full writeup.
- **Dependency:** should land after P1.1 (COALESCE removal) or the jobs will start failing closed instead of silently no-op-ing — sequence carefully, ideally together.
- **Tests required before merge:** test-gap-plan #8. ✅ done (3 new job tests).

### P2.4 — Fix Messaging Application layer to open tenant context (F-25)
- **STATUS: FIXED** (2026-08-06). Mirrored `/api/threads/*` under
  `/api/org/:organization_slug/me`; also fixed a `CastAndValidate` gap this
  surfaced that likely affects other P1.4-mirrored POST/PATCH routes too —
  see F-25 in `04-findings.md`.
- **Dependency:** same sequencing note as P2.3.
- **Tests required before merge:** test-gap-plan #9. ✅ done.

### P2.5 — Fix `ProcessWorkoutCompletionJob` tenant/owner context (F-26) — confirm first via direct read
- **STATUS: FIXED** (2026-08-06). Confirmed exactly as reported. Added the
  missing `RepoContext.run/2` clause so `ExecutionStore.with_authorization_context/2`
  (already built, never reachable) actually works with no
  organization_id/user_id in context — see F-26 in `04-findings.md`.
- **Dependency:** none.
- **Tests required before merge:** an Oban-enabled integration test confirming the job completes successfully (not `:execution_not_found`). ✅ done, plus an RLSCase proof against real (non-superuser) RLS enforcement.

### P2.6 — Enforce Meilisearch member-index tenant scoping at the query layer (F-27) — confirm first via direct read
- **Dependency:** none.
- **Approach:** Mirror the PR index's `filter: "organization_id = ..."` pattern instead of relying solely on the application post-filter.

### P2.7 — Extend `mix milos.tenancy.audit` and `mix milos.architecture` coverage (F-13)
- **Dependency:** valuable to land early since it would have caught several of the above findings automatically, but not blocking for any of them.
- **Approach:** Add root tenant tables, `users`, materialized views to the audit's table list (with an explicit "platform-administered" classification where RLS isn't applicable); add COALESCE-fallback detection to the RLS policy check; extend the architecture task's tenant-scope check beyond Scheduling to every T4 context.

### P2.8 — Fix `intended_email_digest` enforcement or remove it (F-10)
- **Dependency:** product decision required first (is email-binding actually intended?).

### P2.9 — Fix realtime broadcast silent-fallback-to-legacy-org (F-19)
- **STATUS: FIXED** (2026-08-06). Chose the warning-only grace-period mode
  flagged as an open question below, rather than a hard raise: threaded
  `organization_id` through the booking/slot/workout payloads that were
  previously omitting it, and the one remaining legacy call path
  (`DeleteWorkout.call/1`) now reads it from the `app.organization_id`
  session GUC. The fallback still exists but now logs a warning instead of
  being silent — see F-19 in `04-findings.md`.
- **Dependency:** should land after P1.1 or it will start raising instead of silently misbehaving — decide whether that's acceptable immediately or needs a grace-period warning-only mode first.

## P3 — Low priority / cleanup

- P3.1 — Migrate remaining legacy-arity Scheduling/Workouts call sites (F-18).
- P3.2 — Delete dead `RequireRole` plug (F-02).
- P3.3 — Enable RLS on `users` or formally document it as application-layer-only (F-08 in findings numbering).
- P3.4 — Add RLS (or an explicit documented exception) to root tenant tables (F-16).
- P3.5 — Resolve JWT `"memberships"` claim staleness with reissuance on membership/role change (F-20).
- P3.6 — Investigate and resolve the duplicated `ReviewController` mounting (identified in the architecture map, not independently severity-rated as a security issue).

## Sequencing summary (Gantt-style dependency sketch)

```
P0.1, P0.2 ─────────────────────────────────────────────► ship immediately, independent
P1.5 (non-superuser CI) ────────► unblocks trustworthy validation for everything below
P1.1 (remove COALESCE fallback) ─┬─► P2.3 (Finance jobs)
                                  ├─► P2.4 (Messaging)
                                  └─► P2.9 (realtime fallback)
P1.2 (Finance predicates) ───────────────────────────────► independent, high value
P1.3 (invitation role ceiling) ──────────────────────────► independent, needs product input
P1.4 (admin routes + frontend) ──────────────────────────► largest single change, own release train
P2.1, P2.2, P2.5, P2.6, P2.7, P2.8, P2.9, P3.x ──────────► parallelizable, no hard cross-dependencies beyond what's noted
```
