# Legacy Data and Code Retirement Plan

Date: 2026-08-05. **This is a plan only — no retirement, deletion, or
migration was executed as part of this audit.** Every phase below lists
prerequisites, validation, rollback, and risk. Do not begin Phase 3+ until the
Critical/High findings in `04-findings.md` (especially F-04, F-05, F-21, F-22,
F-23, F-07) are remediated — retiring legacy compatibility paths before fixing
the underlying isolation gaps would remove the (partial, accidental) safety
net those gaps currently sit behind without having replaced it with real
enforcement.

## Retirement candidate inventory

| Item | Category | Classification |
|---|---|---|
| RLS COALESCE-to-legacy-org fallback (F-04) | Compatibility behavior baked into "enforce"-stage migrations | **Requires code deployment before data deletion** — must be replaced with strict-equality policies first |
| `DEFAULT milos_legacy_organization_id()` column defaults (F-04) | Migration-era compatibility default | **Requires data migration before deletion** — confirm no write path still depends on the default before dropping it |
| `x-organization-slug` header trust in `ResolveTenantContext`/`me_controller.ex` (F-01) | Compatibility/fallback behavior | **Requires code deployment before removal** — every `/api/admin/*` caller (backend tests, frontend) must migrate to slug-scoped routes first |
| Legacy `/api/admin/*` route family (~140 endpoints) | Compatibility route surface | **Requires code deployment before removal** — mirror to `/api/org/:slug/admin/*`, migrate frontend, then retire |
| Legacy no-context Scheduling/Workouts store arities (F-18) | Compatibility behavior, acknowledged migration debt | **Requires code deployment before removal** — migrate remaining Oban job callers to context-aware arities |
| `RequireRole` plug (global-role, F-02) | Dead code | **Safe deletion candidate** — confirmed never wired into any router pipeline |
| `MembershipPolicy.can_manage_invitations?/1` | Currently dead code, but should become *live* code as part of the F-06 fix, not deleted | **N/A — repurpose, do not delete** |
| Global `users.role` field and its authorization-relevant read sites (F-02) | Legacy global role, per ADR-055 "must not become a fallback" | **Requires code migration for each of the 5 flagged call sites before the field can be demoted to display-only, then a data/schema decision (keep as non-authoritative metadata vs. remove) is a separate follow-up ADR** |
| `assignment_messages` table | Explicitly marked "Removed legacy table" in the ownership inventory | **Verify actually dropped** (query 20 in `07-read-only-diagnostic-queries.sql`); if still present, safe deletion candidate |
| Legacy object-storage keys (`invoices/...`, public avatar URLs) | Stale data, pre-tenancy paths | **Already has an operator-controlled migration tool** — `mix milos.storage.migrate_legacy_objects` (dry-run default); not a new item, tracked as TD-039/resolved, included here for completeness of the inventory |
| Stale/expired unredeemed invitations | Historical/audit data candidate | **Historical/audit data that should be retained** for a defined retention window, then archived — do not hard-delete without a retention policy decision |
| `mix milos.organizations.ensure_legacy` task and the legacy organization record itself | Migration tooling / seed data | **Requires product decision, not just engineering** — the legacy org holds real historical tenant data (the original single-gym deployment's actual customer). It should never be *deleted*; it should be treated as tenant #1 with no special runtime privilege once F-04 is fixed. Retiring the *fallback mechanisms* (above) is the goal, not retiring the org. |
| Duplicate `ReviewController` mounting (`/api/org/:slug/me/reviews` vs `/api/reviews` under `:user_only`) | Configuration coupling / dead-or-live ambiguity | **Possibly active; requires runtime evidence** — confirm whether the `:user_only` mount has any real traffic before removing |

## Phased plan

### Phase 1 — Establish observability and backups
- Confirm the production backup procedure in
  `docs/operations/tenant-lifecycle-and-recovery.md` has been exercised
  (restore drill) since the T4 rollout landed (2026-08-03/04) — the runbook's
  own drill checklist (`mix milos.tenancy.audit`, two-organization
  cross-surface verification) has never actually validated RLS given F-07.
  2026-08-08 update: Compose now provides PostgreSQL WAL archiving,
  `postgres-backup`, and `postgres-restore-drill` services, and CI runs the
  backup script syntax checks plus a containerized base-backup/restore-drill
  gate. Production still needs its first recorded operator drill entry.
- Add the production role-hygiene check from F-07's remediation (fail startup
  or page if the runtime DB role is superuser/has BYPASSRLS) before touching
  anything else — this is the single highest-leverage safety net for every
  later phase.
- Run `07-read-only-diagnostic-queries.sql` queries 1–6 against production (or
  a fresh restore of a production snapshot) to get a real baseline of
  unmapped rows, legacy-org row counts per table, and RLS policy content.
  **Prerequisite for every subsequent phase.**

### Phase 2 — Stop creating new legacy-shaped data
- Fix F-21, F-22, F-23 (the three confirmed live cross-tenant leaks) —
  these are hotfixes, not part of the retirement sequence, but must land
  before Phase 2 is considered "stopped the bleeding."
- Fix F-04's COALESCE fallback and F-05's Finance predicate gap so no new
  writes silently attribute to the legacy org.
- Fix F-24/F-25 (Finance jobs, Messaging) so per-tenant automation actually
  writes real tenant data instead of legacy-org data or failing closed.

### Phase 3 — Deploy compatibility-removal code
- Migrate `/api/admin/*` to `/api/org/:slug/admin/*` (backend + frontend
  F-09 fix in the same release, since they're coupled).
- Remove the `x-organization-slug` header fallback from
  `ResolveTenantContext`/`me_controller.ex`.
- Migrate remaining legacy-arity Scheduling/Workouts store call sites.
- Add the missing role-ceiling check (F-06) and membership
  suspend/revoke commands (F-08 in the role matrix / F-11 numbering).

### Phase 4 — Backfill or repair tenant ownership
- Re-run query 3/13/14/15/16 from `07-read-only-diagnostic-queries.sql`
  against production to confirm zero unmapped rows and zero cross-tenant FK
  violations after Phase 2/3 changes land.
- Investigate any row whose `organization_id` is the legacy org but whose
  actual owning entity graph (user, invoice, etc.) suggests it was created by
  a real tenant's operation through one of the now-fixed fallback paths —
  these rows need manual reattribution, not a blanket script, since blanket
  reattribution risks corrupting the legitimate legacy org's own data.

### Phase 5 — Validate memberships and role scope
- Add the missing two-organization isolation tests (F-14: Notifications,
  Wellbeing, Coaching) and the admin_mode-scoped Execution test (F-23).
- Re-run `mix milos.tenancy.audit` with its coverage expanded per F-13's
  remediation (full table list including root tenant tables and
  materialized views).

### Phase 6 — Remove or archive obsolete records
- Confirm `assignment_messages` is dropped (query 20).
- Review stale/expired unredeemed invitations against a defined retention
  policy; archive (do not hard-delete) per the existing no-hard-delete
  policy in `docs/operations/tenant-lifecycle-and-recovery.md`.

### Phase 7 — Tighten database constraints
- Drop the `DEFAULT milos_legacy_organization_id()` column defaults once
  Phase 3's write-path fixes are confirmed (no remaining caller depends on
  the default).
- Add RLS to the root tenant tables (F-16) if the product decides
  application-layer-only protection there is insufficient, or explicitly
  document the exception.
- Add RLS support for materialized views is not possible in Postgres —
  instead, add a `mix milos.architecture`-style static check that flags any
  raw SQL query against `finance_aggregates`/`coaching_aggregates`/
  `weekly_leaderboard` lacking an `organization_id` literal in the query
  text, as a permanent guardrail against F-21/F-22 recurring.

### Phase 8 — Remove dead code and flags
- Delete `RequireRole` plug (confirmed dead).
- Remove the legacy `/api/admin/*` routes once Phase 3's replacement has
  been live and verified for a full deprecation window.
- Remove the un-scoped Finance `Finance.get_invoice/1` 1-arity delegate
  once all call sites are migrated to the context-aware 2-arity form.

### Phase 9 — Validate production invariants
- Full read-only pass of `07-read-only-diagnostic-queries.sql` against
  production; zero results expected on every cross-tenant/orphan/duplicate
  query.
- Live cross-tenant penetration pass per the audit brief's required test
  list (`08-test-gap-plan.md`), executed against a staging environment
  seeded with two real organizations.

### Phase 10 — Monitor and retain rollback capability
- Keep the pre-Phase-2 backup retained per the installation's retention
  policy.
- Monitor the production role-hygiene check (Phase 1) continuously, not just
  at deploy time — a runtime credential change could silently reintroduce
  the F-07 gap.
- Track F-24/F-25-adjacent Oban jobs' per-tenant execution counts as an
  ongoing health signal (a job that only ever touches the legacy org's rows
  again would indicate a regression).

## Explicit non-goals of this plan

- **Do not delete the legacy organization or its data.** It is a real
  tenant's real historical data, not a migration artifact.
- **Do not run any of the retirement steps above until the corresponding
  Critical/High findings in `04-findings.md` are fixed and validated** —
  removing a fallback before fixing what it was silently compensating for
  converts a silent-fallback bug into a hard outage or, worse, an
  unprotected gap.
