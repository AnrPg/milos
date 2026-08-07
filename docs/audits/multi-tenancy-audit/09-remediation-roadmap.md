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

### P1.4 — Fix legacy `/api/admin/*` header-trust tenant resolution (F-01) + frontend org-in-URL migration (F-09) — **FIXED, CONTRACT PHASE COMPLETE (2026-08-06)**. See F-01/F-09 in `04-findings.md`.
- **Dependency:** these two shipped together as planned (backend contract phase + frontend navigation fix in the same session).
- **Affected modules:** `router.ex`, `resolve_tenant_context.ex`, `me_controller.ex`, `apps/web/src/api/client.ts`, `apps/web/src/components/TopNav.tsx`, `apps/web/src/components/organization-selector.tsx`. `apps/web/src/app/admin/*` did **not** need to move — the existing `apps/web/src/proxy.ts` already rewrites `/org/:slug/<path>` to `<path>` transparently.
- **Approach actually taken:** deleted the legacy `/api/admin/*` scope (every route had an exact org-scoped mirror already); hardened `ResolveTenantContext` to reject path-less requests instead of falling back to the header or legacy org; `apiRequest` now rewrites `/admin/*` and `/me/search/users` calls to the org-scoped path transparently for every existing caller; `organization-selector.tsx` now navigates to `/org/:slug/admin` and calls `queryClient.clear()` on switch instead of namespacing all ~164 query keys individually; `TopNav.tsx` resolves and preserves the org slug across admin nav.
- **Known remaining gap:** ~80+ internal deep-link hrefs across ~10 admin component files (and two backend push-notification link builders) still emit bare `/admin/...` paths. These don't reopen the backend vulnerability (closed unconditionally) but can still drop a multi-org user out of the `/org/:slug/...` URL space, reopening the cross-tab-bleed window until they navigate via TopNav again. Not fixed in this pass — see P1.6 below.
- **Tests required before merge:** test-gap-plan #4, #11 — backend: ~130 test call sites updated across 18 files, all green. Frontend: `client.test.ts`, `TopNav.test.ts`, `organization-selector.test.tsx` updated and green; **no live-browser verification was performed** — this still needs a manual/Playwright pass before considering the frontend side fully proven, per this file's own past guidance that automated tests here can't cover this class of change.
- **Deployment considerations:** Largest-surface-area change in this roadmap (~140 backend routes + the frontend admin shell). Shipped as a single cutover rather than a feature-flagged parallel rollout — justified here because the legacy routes had zero remaining callers once `apiRequest` was fixed in the same change, so there was no window where old and new needed to coexist.

### P1.6 — Slug-prefix the remaining internal admin deep links (follow-up from P1.4/F-09) — **FIXED 2026-08-07**
- **Approach actually taken:** rather than `useParams`, added a shared
  `useOrganizationSlug()`/`adminHref()` in
  `apps/web/src/lib/organization-slug.ts` and pointed all 12 components plus
  `TopNav.tsx` at it — `useParams` would not have worked, since the admin pages
  live at `src/app/admin/*` and are reached through the `proxy.ts` rewrite, so
  `organization_slug` is never a route param in their scope. The hook resolves
  URL → localStorage → first membership, matching what TopNav already did.
- **Backend:** added `Organizations.Domain.AdminPath` as the server-side mirror
  of `adminHref` (same degrade-to-bare-path behaviour) and threaded the slug
  from `conn.assigns.tenant_context` into the dossier endpoints and from the
  notification payload's `organization_id` at dispatch time.
- **Still not verified in a live browser** — same caveat as P1.4.
- **Dependency:** none; purely additive polish on top of the P1.4 fix.
- **Affected modules:** `AdminDashboard.tsx`, `AnalyticsMarketingHub.tsx`, `admin-analytics.tsx`, `admin-coaching.tsx`, `admin/finance/FinanceDashboard.tsx`, `admin/finance/FinanceOperations.tsx`, `admin-finance-member-profile.tsx`, `admin-finance-package-detail.tsx`, `admin-finance.tsx`, `admin-home.tsx`, `admin/users/AdminUserProfile.tsx`, `admin/users/AdminUsersDirectory.tsx`, plus `push_message_builder.ex` and `admin_profile_policy.ex` on the backend.
- **Approach:** thread `useParams<{organization_slug}>()` (client components already have it, no prop drilling needed since they render under `/org/:slug/admin/*`) through each file's hrefs; for the two backend link builders, thread the organization slug through to the URL builder the same way `organization_id` is already threaded through their calling context.
- **Tests required before merge:** none of the existing tests exercise these hrefs directly; add targeted tests per file as they're touched.

### P1.5 — Add non-superuser RLS-enforcing test/CI lane (F-07) — **FIXED 2026-08-06**: `RLSCase` helper + boot-time `PrivilegeGuard` health check + a genuine RLS-enforcement test for all 8 T4 contexts (Execution, Scheduling, Messaging, Workouts, Feedback, Analytics, Gamification, Finance). See `04-findings.md`.
- **Dependency:** should land early since it makes every subsequent fix's tests actually trustworthy.
- **Affected modules:** `config/test.exs`, `.github/workflows/ci.yml`, possibly a new `docker-compose.test.yml` provisioning a `milos_runtime`-equivalent role for CI.
- **Approach:** Add a CI job (or extend the existing one) that provisions a non-superuser, non-BYPASSRLS role for at least the isolation-test subset; add a startup/health check that fails if the production runtime connection is a superuser or has BYPASSRLS.
- **Tests required before merge:** the health check itself needs a test (connect as superuser in a test harness, assert the check fails).

### P1.8 — Fix per-organization role assignment (F-29) — **FIXED 2026-08-07**
- Tenant admins could change any account's **global** role — including accounts
  that had never belonged to their organization, and with no role ceiling.
  Replaced with `Commands.SetMembershipRole` (membership-scoped, ceiling-checked
  against both the requested and the current role, self-change refused); the
  global-role mutation path (`UpdateUserRole`) was deleted outright.
- Also fixed `GetScheduleCalendar.booking_nickname_cache/2`, which decided
  nickname visibility from the global role while the helper beside it already
  resolved the tenant role correctly.
- **Residual:** `GetLeaderboardSnippet` and `GetCalendarFeed` still read the
  global role. Neither exposes another tenant's data, and both are entangled
  with F-18's un-scoped arities, so they are folded into P3.1.
- **Tests:** `set_membership_role_test.exs` (9), covering cross-org isolation,
  the ceiling in both directions, self-change, and the previous role's state
  reconciliation.

## P2 — Medium priority

### P2.1 — Add missing two-organization isolation tests: Notifications, Wellbeing, Coaching (F-14)
- **STATUS: FIXED** (2026-08-07). All three `tenant_isolation_test.exs` files
  added. Coaching and the org-scoped Notifications paths verified clean.
- **Surfaced a new finding — see P1.7 / F-28 below.** Writing the tests exposed
  that owner-scoped reads are not constrained by the tenant boundary in
  Wellbeing (confirmed cross-tenant read of medical data, survives RLS) and
  Notifications (inbox spans organizations). The tests currently assert the
  unfixed behaviour, tagged `:documents_current_behaviour`.
- **Tests required before merge:** test-gap-plan pattern applied to these three contexts. ✅ done.

### P1.7 — Constrain owner-scoped reads to the tenant boundary (F-28) — **RESOLVED 2026-08-07**
- **Product decision:** personal records **follow the member** across every
  organization they belong to, rather than being partitioned per tenant. Health
  records belong to the member, not the gym.
- **Wellbeing:** the owner branch is therefore intentional and is now documented
  as such at both the application layer and in `rls_enforcement_test.exs`. It is
  the tenancy model's one sanctioned cross-organization read, safe because it
  can only ever match the acting account's own rows.
- **A real defect the original writeup folded in with it, now fixed:** the admin
  injury list and analytics summary shared that owner-scoped predicate, so an
  admin's own reports filed at another gym appeared in this organization's
  listing and inflated its counts. Split out to a fail-closed
  `scoped_to_tenant/1`.
- **Notifications:** the inbox stays cross-organization (a member should not
  miss a notification because they had a different gym selected). The
  compensating requirement is provenance: `organization_id` is now exposed on
  inbox payloads and the client badges anything raised outside the active
  organization, colour-coded by that gym's own `brand_primary_color`.
- **RLS policy left as-is** — with this decision the `OR` is correct.

### P1.7 (original, superseded) — Constrain owner-scoped reads to the tenant boundary (F-28)
- **Priority note:** filed under P1 rather than P2 because the Wellbeing half is
  a confirmed cross-tenant read of member-identifiable medical data that is
  **not** backstopped by RLS — the policy carries the same permissive `OR` as
  the application layer.
- **Blocked on:** whether personal records (injury reports, notifications)
  should be partitioned per organization or deliberately follow the member
  across the organizations they belong to. See F-28 for the two options and
  their trade-offs. Do not implement before this is answered — the two
  directions have opposite implementations.
- **Affected modules:** `ecto_wellbeing_store.ex` (`scoped_to_owner_or_tenant/1`),
  `ecto_notification_store.ex` (five inbox reads missing
  `scoped_to_organization/1`), plus a migration replacing
  `injury_reports_owner_or_tenant_policy` and the matching
  `injury_status_events` policy.
- **Sequencing:** both layers must change together — application-layer only
  leaves the policy permissive; policy-only breaks self-service reads where no
  organization is open.
- **Tests required before merge:** flip the `:documents_current_behaviour`
  assertions in `wellbeing/tenant_isolation_test.exs`,
  `wellbeing/rls_enforcement_test.exs`, and
  `notifications/tenant_isolation_test.exs` from `assert` to `refute`.

### P2.2 — Add membership suspend/revoke commands (F-11) and platform-owner revoke task (F-12)
- **STATUS: FIXED** (2026-08-07). `Commands.SetMembershipStatus` (owner/admin
  gated, F-06 role ceiling, refuses self-change to prevent owner lockout) and
  `Organizations.revoke_vendor/1` + `mix milos.platform.revoke_vendor`.
- **Naming note:** the task is `revoke_vendor`, not `revoke_owner` as written
  below — `platform_owners` was renamed to `vendors` (ADR-089) after this
  roadmap was drafted, because "platform owner" collided with the
  tenant-scoped `owner` role.
- **No migration needed:** both `status` enums already carried the required
  values (`:suspended`/`:revoked` and `:revoked`); only application code was
  missing, exactly as F-11/F-12 described.
- **Dependency:** none.
- **Tests required before merge:** test-gap-plan #18 (was impossible to write — this item unblocked it). ✅ done, 11 new tests.

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
  surfaced — later fixed generically for every org-scoped route (not just
  Messaging's) as part of P1.4's contract phase — see F-25 in `04-findings.md`.
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
- **STATUS: FIXED** (2026-08-06). Mirrored the PR index's filter pattern via
  a new `organization_ids` filterable attribute — see F-27 in
  `04-findings.md`. Not provable end-to-end (no Meilisearch instance in this
  environment); proved via the params reaching the index and the documents
  carrying the right data instead.
- **Dependency:** none.
- **Approach:** Mirror the PR index's `filter: "organization_id = ..."` pattern instead of relying solely on the application post-filter.

### P2.7 — Extend `mix milos.tenancy.audit` and `mix milos.architecture` coverage (F-13)
- **Dependency:** valuable to land early since it would have caught several of the above findings automatically, but not blocking for any of them.
- **Approach:** Add root tenant tables, `users`, materialized views to the audit's table list (with an explicit "platform-administered" classification where RLS isn't applicable); add COALESCE-fallback detection to the RLS policy check; extend the architecture task's tenant-scope check beyond Scheduling to every T4 context.

### P2.8 — Fix `intended_email_digest` enforcement or remove it (F-10) — **FIXED 2026-08-07**
- **Product decision:** enforce it, and add email to accounts to make that
  possible.
- **Why this was bigger than the finding implied:** `intended_email_digest` was
  the *only* email-related column in the entire schema — accounts are identified
  by nickname and carried no email at all, so the digest had nothing to compare
  against. Enforcement required adding `users.email` first.
- **Approach:** nullable `users.email` with a case-insensitive partial unique
  index. Nullable is deliberate — every existing account predates the column and
  there is nothing to backfill from, so enforcement keys off "does this account
  hold a matching address", not "does every account have one". An account
  without an email cannot redeem a bound invitation; invitations issued without
  an address keep their existing open behaviour.
- **Normalization consolidated** into `Domain.InvitationEmail`; issuing and
  redemption previously had separate copies, and they must agree byte-for-byte
  or the comparison silently never matches.
- **Checked before the store transaction** so a wrong account cannot consume the
  invitation and deny the legitimate invitee, and returns `:ok` for unknown
  tokens so it never becomes an oracle for which tokens exist.
- **Follow-up not done:** email is optional at registration. Making it mandatory
  is a separate product/UX decision, and existing accounts would need a prompt
  to supply one.

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

- P3.1 — **FIXED 2026-08-07 (partial).** `archive_active_assignments_for_athlete`
  now has an organization-scoped arity, closing the cross-organization sweep the
  F-29 fix depended on. **Still open:** `GetLeaderboardSnippet` and
  `GetCalendarFeed` read the global account role, and `GetCalendarFeed` uses the
  un-scoped `Scheduling.get_calendar_week/1`. Neither exposes another tenant's
  data (the leaderboard is org-scoped since P0.1; the feed is token-scoped to
  one account), so they are the remaining F-18 tail rather than a live leak.
- P3.2 — **FIXED 2026-08-07.** Dead `RequireRole` plug deleted (F-02). It
  authorized on the *global* `user.role`, so wiring it up would have looked
  correct and silently bypassed the tenancy model.
- P3.3 — **FIXED 2026-08-07.** `users_owner_policy` dropped (F-08). It had been
  created without ever enabling RLS on the table, so it had never done anything;
  and it was also wrong (`id = app.user_id` would break login, tenant
  resolution, and the admin directory). `users` is application-layer-only by
  design, and `mix milos.tenancy.audit` now states that exemption explicitly.
- P3.4 — **FIXED 2026-08-07** via the documented-exception route (F-16). RLS on
  the root tenant tables would be circular: resolving a tenant requires reading
  `organizations` and `organization_memberships` *before* any session GUC
  exists. They are now reported under `platform_administered` by the audit task,
  so the exemption is a claim on the record rather than an absence, and
  `unclassified_tables/0` fails the audit if a new tenant table appears
  unclassified.
- P3.5 — **FIXED 2026-08-07** by removing the claim rather than refreshing it
  (F-20). The `"memberships"` claim was never read back — not for authorization
  (`TenantContext` is rebuilt from live DB state per request) and not by the
  client. A stale claim nobody consults invites someone to start trusting it
  later, and it embedded the user's full organization/role list in a credential
  that gets logged and stored.
- P3.6 — **FIXED 2026-08-07.** The duplicate flat `/api/reviews` mount ran under
  `:user_only` with no `ResolveTenantContext`, and `ReviewController.action/2`
  falls through without opening a tenant scope when none is present — so it
  wrote reviews with no organization at all. Deleted; the org-scoped mount and
  an `apiRequest` rewrite replace it. This turned out to be a tenancy defect,
  not the cosmetic duplication the audit assumed.

## Sequencing summary (Gantt-style dependency sketch)

```
P0.1, P0.2 ─────────────────────────────────────────────► ship immediately, independent
P1.5 (non-superuser CI) ────────► unblocks trustworthy validation for everything below
P1.1 (remove COALESCE fallback) ─┬─► P2.3 (Finance jobs)
                                  ├─► P2.4 (Messaging)
                                  └─► P2.9 (realtime fallback)
P1.2 (Finance predicates) ───────────────────────────────► independent, high value
P1.3 (invitation role ceiling) ──────────────────────────► independent, needs product input
P1.4 (admin routes + frontend) ──────────────────────────► FIXED 2026-08-06; P1.6 (deep links) is the deferred remainder
P2.1, P2.2, P2.5, P2.6, P2.7, P2.8, P2.9, P3.x ──────────► parallelizable, no hard cross-dependencies beyond what's noted
```
