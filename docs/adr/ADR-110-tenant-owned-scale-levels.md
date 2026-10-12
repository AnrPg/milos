# ADR-110: Tenant-Owned Scale Levels
Date: 2026-10-12
Status: Accepted

## Context
Scale levels (the `Scaled / Rx / Rx+` vocabulary that workout variations,
executions and training logs refer to) are meant to be configured per gym.
The schema predates multi-tenancy: `scale_levels` had no `organization_id`, no
RLS, and globally unique `slug` and active `sort_order` indexes. Because
`PUT /api/org/:slug/admin/scale-levels` (`ReplaceScaleLevels`) replaced that
single table, any gym's admin could rename, reorder or delete every other
gym's scale levels (TD-048, found during TD-044 / ADR-096). The DSL preflight
and the workout authoring path also resolved slugs against the global set.

The owner approved the schema change, including replacing the global unique
indexes with per-organization ones (normally a human-approval item).

## Decision
`scale_levels` becomes an ordinary tenant table owned by the Workouts
context:

- `organization_id` (FK `organizations`, `ON DELETE CASCADE`, `NOT NULL`),
  forced RLS with the sibling `organization_id = app.organization_id` policy,
  and the `milos_apply_tenant_context()` insert/update trigger.
- Uniqueness is per organization: `(organization_id, slug)` and
  `(organization_id, sort_order) WHERE is_active`.
- `exercise_variations.scale_level_id` becomes a composite FK
  `(organization_id, scale_level_id) -> scale_levels (organization_id, id)`,
  so a variation can only reference a level of its own organization.
- Migration `20261012160000` copies every global row into every existing
  organization (fresh ids), repoints each variation to its organization's copy
  by slug, deletes the global originals, then enforces the above.
- New organizations get `Workouts.Domain.DefaultScaleLevels`
  (`scaled/Scaled`, `rx/Rx`, `rx-plus/Rx+`, the set the platform has always
  seeded) from `Application.ProvisionOrganization`.
- Every read and write takes a tenant context:
  `Workouts.list_scale_levels/1`, `replace_scale_levels/2`,
  `seed_default_scale_levels/1`; the store additionally filters by the
  session organization and fails closed with
  `{:error, :organization_context_required}`.

## Rationale
Per-organization rows are the model the product already assumed (admins
configure "their" levels) and match every other tenant table, so the existing
RLS harness, purge/export policy (ADR-099) and tenancy audit cover them with
no special cases. Executions and training-log entries store the *slug*, which
each organization's copy keeps, so historical rows need no rewrite and keep
materializing correctly.

## Alternatives Considered
- **Vendor-only global vocabulary** (lock the endpoint to vendors): removes
  the cross-tenant write but contradicts the per-gym requirement and leaves
  gyms unable to name their own levels.
- **Global catalog plus per-org overrides table**: two sources of truth and a
  join on every read for no product benefit.
- **Keep global rows as shared defaults referenced by all tenants**: the
  original bug in another form; any write path would again be cross-tenant.

## Consequences
- A gym can freely rename, reorder or replace its levels without affecting any
  other gym; the removal guard ("still used by workout variations") only
  counts the acting gym's workouts.
- Scale slugs in the Quick Text DSL are preflighted against the acting
  tenant's set; `PublishWorkoutDsl.call/2` (context-free) was removed.
- Provisioning is two transactions in two contexts (organization, then scale
  levels). Seeding is idempotent and a fresh org's table is empty, so a failure
  means a database outage; the error is returned and the gym can still set its
  levels through the admin endpoint.
- `down` is lossy once gyms diverge (see Implementation Notes).

## Implementation Notes
- Migration: `20261012160000_scope_scale_levels_to_organizations.exs`
  (expand -> backfill -> enforce in one transaction). It runs as the migration
  owner/superuser role, like earlier tenant backfills. Any variation left
  pointing at a global row would fail the delete of the originals and abort the
  migration rather than orphan data.
- The composite FK keeps the name `exercise_variations_scale_level_id_fkey` so
  `foreign_key_constraint(:scale_level_id)` still maps it, and switches from
  `RESTRICT` to `NO ACTION` (checked at statement end) so deleting an
  organization can cascade through both `scale_levels` and
  `exercise_variations`; deleting a referenced level is still rejected.
- `down` collapses tenants back to one global set: the oldest organization
  that has levels supplies the global set, slugs used only by other
  organizations are kept as inactive rows (sort order 1000+) so every variation
  still resolves, and per-organization labels/order for shared slugs are lost.
- `scale_levels` is declared in `Workouts.Domain.TenantDataPolicy` (purged
  after `exercise_variations`) and listed as a ready tenant table in
  `mix milos.tenancy.audit`. It was removed from the clean-slate purge's
  preserved tables (ADR-094): it is tenant data now, and `TRUNCATE
  organizations CASCADE` would empty it anyway.
- `GetWorkoutExecution` now materializes the workout it already read in the
  execution's tenant scope (`Workouts.materialize_for_scale/2`) instead of
  re-reading it through the context-free `materialize_workout_for_scale/2`,
  which ran outside any tenant session.
- `priv/repo/seeds.exs` no longer creates a global set; it re-asserts the
  defaults (idempotently) for each existing organization.
- No OpenAPI or web changes: the endpoint contract is unchanged, only its
  scope.
- Tests: migration backfill (rolled back and forward inside the sandbox via
  `Ecto.Migration.Runner`), RLS-enforced two-tenant application test, ConnCase
  endpoint isolation and per-tenant execution materialization, provisioning
  seeds defaults, and organization deletion with scale-level references.
