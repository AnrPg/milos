# ADR-114: Tenant-Scoped Admin Fanout Replaces Global Admin Lookups
Date: 2026-10-12
Status: Accepted

## Context
ADR-091 made the central Notifications fanout tenant-scoped, but twenty-two
application services still resolved realtime and notification recipients with
`Identity.list_by_role(:admin)`. That lookup reads the global `users.role`
column, so a workout, challenge, review, injury, assignment, settings, or scale
level change in one organization pushed refresh events to every admin account
on the platform, and never reached tenant staff (owners, admins, coaches) whose
global role is not `admin`. This was TD-044.

## Decision
Every application-level admin fanout resolves recipients through
`Palee.Application.TenantStaffRecipients.user_ids/1`. It takes an
ordered list of ownership sources — the caller's tenant context first, then
the entity the operation produced — and returns the active
owner/admin/coach memberships of the first organization found
(`Organizations.list_staff_user_ids/1`). Without ownership it returns no
recipients; it never falls back to global admins.

Services that previously had no tenant-context arity gained one, and their
admin controllers now pass `conn.assigns.tenant_context`.

## Rationale
The tenant context is the authoritative ownership signal on admin routes, and
several write paths return maps whose `organization_id` is assigned by the
database rather than echoed back (drafts, challenges), so the entity alone is
not reliable. Checking the context first and the entity second covers both
admin routes and user-scoped routes (executions, assignments, injuries) where
the entity carries provenance. One resolver keeps the fail-closed policy in a
single place and makes regressions greppable.

## Alternatives Considered
- Resolving the organization from the ambient `app.organization_id` session
  setting: rejected because it couples Application services to the
  Infrastructure repo context and hides missing propagation.
- Fanning personal records out to staff of every organization the user
  belongs to: rejected because ADR-055 keeps self-authored wellbeing facts and
  org-less executions user-owned and visible to tenants only through explicit
  grants; staff would be notified about records they cannot read.
- Demoting `users.role` in the same change: deferred; `list_by_role/1` is still
  used by non-fanout identity queries.

## Consequences
- Admin fanout is now strictly per tenant. Personal (org-less) records reach no
  tenant staff, which is intended.
- The injury API response gains an optional, nullable `organization_id` so
  member-side flows can route provenance-bearing injuries to the right tenant.
- A regression test fails if `list_by_role(:admin)` reappears under
  `lib/palee/application/`.

## Implementation Notes
- `CreateWorkoutWithSections` had no callers and was removed rather than
  migrated.
- Admin challenge update/delete, review status, workout reopen/duplicate,
  assignment rejection, and scale-level replacement previously ran without an
  explicit tenant repo scope; the new context arities wrap them in the owning
  context's `with_tenant_context/2`. Other unwrapped reads (for example
  `AdminChallengeController.show/2`) are the TD-046 bug class and are handled
  with the restricted-role test harness.
- Scale levels remain a global table that any tenant admin can replace; the
  refresh is now scoped to the acting tenant, but the cross-tenant mutation
  itself is logged as new debt (TD-063), resolved by ADR-128 (tenant-owned
  scale levels).
- Covered by `tenant_staff_recipients_test.exs` (resolver, fail-closed, and the
  grep guard) and `tenant_scoped_admin_fanout_test.exs` (two tenants plus a
  global admin across drafts, challenges, settings, scale levels, and
  member-healed tenant injuries).
