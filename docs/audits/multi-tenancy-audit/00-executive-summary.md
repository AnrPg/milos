# Executive Summary — Multi-Tenancy Security Audit

Date: 2026-08-05 (updated same day with a production verification pass).
Repository: `/home/rodochrousbisbiki/MyApps/milos`. Full findings:
`04-findings.md`. Production verification detail: `10-production-verification.md`.
This audit performed no fixes, no production mutations, and no destructive
operations at any point. Local dev/test infrastructure (Postgres, Redis,
Meilisearch, MinIO) was started solely to run the existing automated test
suite and read-only diagnostic queries against a schema copy. **A follow-up
pass later the same day gained read-only access to the live production
deployment** (Kubernetes namespace `tenant-m4`, app at
`https://milos.4kq.net/`, GitOps config at
`/home/rodochrousbisbiki/MyApps/deployed-milos/gitops`) with explicit user
approval before every `kubectl exec`; only `SELECT`-only queries were run,
executed through the running application's own database connection, and no
secret values were ever read or displayed. See `10-production-verification.md`
for the full method and results — several conclusions below are updated from
the original code-only pass based on that live verification.

## Overall assessment

The multi-tenancy refactor is **substantially, carefully designed** — the ADR
series (055–060, 083, 087, 088) documents a coherent shared-schema-plus-RLS
model with an honest, staged expand/backfill/enforce rollout, and large parts
of the implementation (Coaching's drill-down authorization, Wellbeing's
owner-or-tenant RLS split, Pantheon's fetch-then-check-owner pattern, the
invitation token/redemption transaction) are genuinely well-built and match
their design intent.

However, the implementation is **not yet trustworthy as a tenant-isolation
boundary**. This audit confirmed three currently-live, unauthenticated-effort
cross-tenant data leaks (two of them requiring no more than using the product
as documented), one confirmed within-tenant privilege-escalation bug, and a
verification-integrity gap that means the test suite has never actually
exercised the database-level enforcement mechanism (Row-Level Security) it
was written to validate. Several of the codebase's own internal claims of
completion (`docs/technical_debt.md` TD-038, and `mix milos.tenancy.audit`
passing) are materially overstated relative to what those checks actually
verify.

## Can tenant isolation currently be trusted?

**No, not without the P0/P1 fixes in `09-remediation-roadmap.md`.** Isolation
is correctly enforced on the majority of surfaces reviewed (Scheduling,
Coaching, Wellbeing, Pantheon, most of Finance's per-request controller flow,
most of Workouts). But three surfaces have confirmed, currently-exploitable
cross-tenant/cross-user data exposure, and the mechanism meant to catch
regressions of this kind (RLS + the isolation test suite) has a structural
blind spot (F-07) that let these three specific bugs ship unnoticed.

## Does the legacy gym still have a special position?

**Partially, and in the most consequential way possible.** No entitlement,
subscription, or feature-flag privilege is granted to the legacy organization
at creation. But the database-level enforcement layer treats it as the
**implicit default tenant**: every "enforce"-stage RLS policy across roughly
30 tenant tables falls back to the legacy organization's ID whenever a
database session doesn't have tenant context set (F-04), and the legacy
organization is the fallback target for HTTP tenant resolution on ~140 admin
routes (F-01) and for WebSocket connections without an explicit organization
parameter. This is not merely historical residue — it is live, current-code
behavior that directly contradicts the stated invariant that "historical
origin must never grant a tenant additional authorization." It does not leak
*other* tenants' data to each other, but it does mean the legacy tenant is
reachable and mutable by any code path that fails to propagate tenant context
correctly, while no other tenant has that property.

## Do the role and invitation models satisfy the stated invariants?

**Mostly, with one confirmed critical exception.** The core primitives are
sound: membership-based tenant roles (not a global user property), a correct
`TenantContext` choke point for the majority of routes, opaque one-time
invitation tokens with sound transactional redemption, and a platform-owner
authority that is genuinely separate from tenant roles and reachable only
through an operator Mix task (no HTTP path exists to self-escalate to
platform owner — confirmed).

The confirmed exception: **a tenant `admin` can issue a fully valid `owner`
invitation for their own organization** (F-06) — `IssueInvitation` checks
that the issuer holds `owner`/`admin` but never checks that the *granted*
role doesn't exceed the issuer's own, directly violating "a gym administrator
must not be able to escalate ... into a role equal to or greater than their
own." This is within-tenant only (cannot reach a global/platform role) but is
a full, untested, unenforced privilege-escalation path.

Additionally, the legacy global `users.role` field (`:member`/`:athlete`/
`:admin`) is still read as a real authorization gate on several surfaces
independent of organization membership (F-02) — most seriously, it drives
the `admin_mode` RLS bypass that produces the Execution IDOR (F-23).

## Confirmed cross-tenant vulnerabilities (the five highest-risk findings)

1. **F-21 — `finance_aggregates` materialized-view query has zero tenant
   filter.** Any organization admin's finance dashboard returns platform-wide
   revenue/membership/promotion/referral/credit-ledger data for every tenant.
   Critical, confirmed, live, no exploitation technique required.
2. **F-22 — `weekly_leaderboard` materialized-view query has zero tenant
   filter and no auth gate at all.** Any authenticated user — no organization
   membership required — retrieves member identities and activity data across
   every tenant. Critical, confirmed, live.
3. **F-23 — Execution `admin_mode` RLS bypass is derived from the legacy
   global role and has no organization constraint.** Any global-role-`admin`
   account can fetch any user's any execution record in any organization by
   ID. Critical, confirmed, textbook IDOR.
4. **F-04 — RLS "enforce"-stage policies COALESCE to the legacy organization
   when tenant context is unset**, across roughly 30 tables spanning Finance,
   Messaging, Notifications, Gamification, Analytics, Wellbeing, Feedback.
   Critical: this is the structural root cause that makes the legacy org an
   implicit default tenant at the database layer, and it means a missing
   tenant-context propagation bug fails *silently into the legacy org's data*
   rather than failing loudly.
5. **F-06 — Tenant `admin` can issue a valid `owner` invitation** with no
   role-ceiling check; `MembershipPolicy.can_manage_invitations?/1` exists to
   prevent exactly this and is dead code. Critical, confirmed,
   within-tenant privilege escalation.

Close runners-up, each independently confirmed: **F-05** (Finance's store has
essentially no application-layer tenant predicates, relying entirely on the
compromised F-04 backstop) and **F-07** (dev/test/CI database connections run
as PostgreSQL superuser, so RLS — the mechanism most of this audit's "OK"
verdicts ultimately rest on — has never actually been exercised by any
automated test; production correctness depends on an operator having manually
run a role-provisioning script that nothing currently verifies at runtime).

## Would production legacy-data deletion currently be safe?

**No**, though the live verification pass narrows the concern. The general
no-hard-delete policy in `docs/operations/tenant-lifecycle-and-recovery.md`
still applies, and the legacy organization is architecturally the database's
*implicit default tenant* (F-04) — its RLS fallback function currently
resolves to `NULL` in production only because the organization's slug was
independently renamed away from `legacy-milos-training` (an accidental, not
deliberate, mitigation — see `10-production-verification.md`), and the
fallback would silently reactivate if that slug ever exists again. Production
is confirmed to be single-tenant today (1 organization, 5 users), so there is
currently no *other* tenant's data that could have been misattributed into
this org via the fallback — but this org's own data still cannot be treated
as a safe deletion candidate until F-04 is properly fixed (not just
accidentally inert) and the backfill/repair validation in
`06-legacy-data-and-code-retirement-plan.md` Phase 4 has run.

## Production verification update (2026-08-05, same day)

After the initial report below was written, the user granted read-only
access to the live production deployment. Key results (full detail in
`10-production-verification.md`):

- **Production's database connection is confirmed non-superuser**
  (`rolsuper=false`, `rolbypassrls=false`, role `app`) — F-07's dev/test/CI
  superuser gap does **not** extend to production. RLS is genuinely active
  for real production traffic.
- **F-04's legacy-org RLS fallback is confirmed present in 40 production
  policies**, but currently resolves to `NULL` (inert) due to an unrelated
  organization-slug rename — an accidental, fragile non-fix, not a real
  mitigation.
- **Production is single-tenant today** (1 organization, 5 users, 3
  memberships) — a pre-launch/early-access state. This means the confirmed
  cross-tenant leaks (F-21, F-22, F-04) have had **no actual second-tenant
  victim yet**, but remain fully live in the deployed code and will activate
  immediately upon a second organization's provisioning, with zero
  additional trigger. F-23 (cross-*user* IDOR) is not similarly protected by
  the single-tenant state.

This updates two of the "Immediate containment recommendations" originally
listed below (superuser-role confirmation is now done; its outcome is
favorable) without changing the P0/P1 remediation priority — see the revised
list.

## Immediate containment recommendations

1. Ship **F-21/F-22/F-23 hotfixes** (P0 in the roadmap) before onboarding any
   second organization — these are confirmed-live-in-production cross-tenant/
   cross-user defects that will activate the moment a second tenant exists
   (F-21/F-22) or can already be exploited cross-user today (F-23).
2. Remove the **F-04 legacy-org RLS fallback properly** rather than relying
   on its current accidental inertness — a routine, documented-as-safe
   `mix milos.organizations.ensure_legacy` re-run, or any future org named/
   slugged `legacy-milos-training`, would silently reactivate it in
   production.
3. Add the **non-superuser RLS-enforcing CI lane** (F-07/P1.5) so dev/test/CI
   can catch RLS regressions before they reach the now-confirmed-correctly-
   configured production role.
4. ~~Confirm production's runtime database role~~ — **done**, see above;
   production is confirmed non-superuser. This item is resolved.
5. Do not provision additional independent commercial tenants (per the
   runbook's own existing guidance) until at least the P0 and P1.1–P1.3
   items in `09-remediation-roadmap.md` have shipped and been validated with
   the tests in `08-test-gap-plan.md`. This is now a harder requirement than
   originally stated: live verification confirms F-21/F-22/F-04 are dormant
   only because no second tenant exists yet, not because of any protective
   mechanism.

## Audit limitations

- **Production access was later granted and used, but only partially.** The
  original pass had no production access; a same-day follow-up (see
  `10-production-verification.md`) ran a targeted set of read-only `SELECT`
  queries against live production through the application's own DB
  connection, and reviewed the GitOps/Kubernetes deployment configuration.
  It did **not** perform a full re-run of `07-read-only-diagnostic-queries.sql`
  against production (only a subset of equivalent ad hoc queries relevant to
  F-04/F-07/F-21/F-22 were run), did not attempt live HTTP exploitation of
  any endpoint against `https://milos.4kq.net/`, and did not review access
  logs (recommended follow-up for F-23). A full run of
  `07-read-only-diagnostic-queries.sql` against production remains
  outstanding and is recommended as the next verification step.
- **Delegated research passes** (six background research agents covering
  Identity/Organizations, RLS verification, invitations, legacy-gym search,
  per-context scoping, and frontend) produced the bulk of the raw evidence;
  every finding rated **Confirmed** in `04-findings.md` was independently
  re-verified against the actual source by direct reading during this audit.
  Findings explicitly marked **Confidence: Reported by delegated research, not
  independently re-verified** (F-15, F-24, F-25, F-26, F-27) should get a
  direct-read follow-up before remediation work begins, though their
  underlying mechanism (RLS COALESCE fallback, job/application context
  patterns) was independently confirmed in the adjacent findings they build
  on.
- **Not exhaustively reviewed:** full line-by-line coverage of every Workouts
  command/query module, `analytics_events`/`communication_threads` write
  paths, and `notification_click_events`/`push_dispatch_attempts` write paths
  was not completed — flagged in `02-tenant-surface-matrix.md` as follow-up
  areas.
- **No live penetration test was performed** against a running instance
  (staging or production) — all findings are static/code-level plus one local
  dev-database live-query pass. The audit brief's required "live cross-tenant
  penetration test" step remains outstanding and is recommended as part of
  Phase 9 in `06-legacy-data-and-code-retirement-plan.md`.
- **Financial provider integration is not yet implemented** (manual-payment
  only per TD-001/TD-022), so the "external provider IDs cannot be associated
  with the wrong tenant" checks in the audit brief are not yet applicable;
  query 17 in the diagnostics file is a forward-looking template for when that
  integration lands.

## Generated audit files

- `00-executive-summary.md` (this file)
- `01-architecture-and-data-model.md`
- `02-tenant-surface-matrix.md`
- `03-role-and-permission-matrix.md`
- `04-findings.md`
- `05-legacy-gym-inventory.md`
- `06-legacy-data-and-code-retirement-plan.md`
- `07-read-only-diagnostic-queries.sql`
- `08-test-gap-plan.md`
- `09-remediation-roadmap.md`
- `10-production-verification.md` (added same day, after live production access was granted)
