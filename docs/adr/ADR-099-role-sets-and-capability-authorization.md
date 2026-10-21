# ADR-099: Role Sets and Capability Authorization
Date: 2026-10-12
Status: Accepted

## Context
A gym membership holds one `role` (owner, admin, coach, member, athlete) and
routes are guarded by role lists. ADR-098 gave coaches admin rights until a
rights-per-role report existed; that report is now
`docs/architecture/rights-per-account-type.md`. The product also needs one
person to hold several roles in the same gym (a coach who trains as a member,
an owner who coaches), three new staff roles (front desk, accountant,
janitor, ADR-102) and a clear line between owners, who act across their gyms,
and admins, who run one gym.

## Decision
- **Role set.** A membership holds `roles` (non-empty set) instead of one
  role. Roles: `owner`, `admin`, `coach`, `front_desk`, `accountant`,
  `janitor`, `member`, `athlete`. The old `role` column stays as the
  *primary role* (the highest-ranked role in the set), kept in sync by the
  store, for the session payload and legacy reads.
- **Capabilities.** `Organizations.Domain.AccessPolicy` maps roles to
  capabilities with a scope (`:all`, `:own`, `:status`). Rights are the union
  of the roles; an unscoped grant beats a scoped one. Routes and application
  services ask for capabilities (`can?(context, :manage_finance)`), not role
  lists. The matrix in the report is the specification and is asserted by
  tests.
- **Owners and admins.** Only owners create gyms, delete a gym, transfer
  ownership, pay the platform subscription and grant or remove owner/admin.
  Admins run one gym and grant only staff roles below admin. Nobody grants a
  role above their own; coaches grant none (they invite clients, ADR-100).
- **Coaches** lose the temporary admin rights of ADR-098: they get coaching,
  workouts, content and challenges, scoped to their own clients and classes
  unless they are head coaches (ADR-100), and only membership *status* for
  money.
- **Role changes** go through one command, `SetMembershipRoles`, which
  validates the ceiling for every added or removed role, keeps at least one
  owner per gym, and re-aligns the account role (ADR-095).
- The `TenantContext` carries `roles`, `capabilities` and the coach scope, so
  every layer reads the same answer.

## Rationale
Capabilities decouple "what a screen or endpoint needs" from "who has it", so
adding front desk, accountant and janitor, or narrowing a role later, changes
one matrix instead of every router pipeline and service. A role set covers
real gym staffing without duplicate accounts or memberships, and keeps the
membership the single authorization source per gym.

## Alternatives Considered
- One membership per role in the same gym: rejected; duplicates profile,
  finance and history per person and breaks every "membership of user in gym"
  lookup.
- Fine-grained per-user permission toggles: rejected for now; roles plus the
  head-coach and notes-visibility toggles cover the product's needs and stay
  explainable.
- Keeping role lists in router pipelines: rejected; the lists would diverge
  from the report as roles grow.

## Consequences
Every admin route is guarded by a capability instead of the coach-inclusive
`admin_only` list; coaches, front desk and accountants reach only their
areas. The web shell receives roles and capabilities and gates surfaces with
them (ADR-103). Invitations carry a role set. Tests assert the matrix.

## Implementation Notes
Implemented in `0f8f700`, `25ab625`, `6102095` and `a37ab33`.

- Migration `20261013100000_membership_role_sets` adds `roles` (array) and
  `coach_scope` to memberships; `role` stays as the primary role.
- `Organizations.Domain.AccessPolicy` holds the matrix
  (`capabilities/2`, `all_capabilities/0`); `TenantAuthorization`
  answers `can?/2` from the `TenantContext`, which carries
  roles, capabilities and coach scope. `AccessPolicyTest` asserts the
  report.
- Routes: the `RequireRouteCapability` plug reads the capabilities of each
  controller action from `PaleeWeb.RouteCapabilities` (any one
  suffices). `RouteCapabilitiesTest` fails when a route under
  `/api/org/:slug/admin` or `/staff` has no capability or names an unknown
  one.
- Role grants per gym: owners and admins unlock `manage_billing`,
  `manage_promotions`, `manage_packages` and `view_finance_reports` for
  front desk (`SetRoleGrants`, stored in the organization settings under
  `role_grants`; web: Settings › Role access, `RoleAccessSettings.tsx`).
  The memberships payload carries the resulting capabilities.
- `SetMembershipRoles` enforces the grant ceiling and keeps one owner per
  gym; an invitation adds its role to an existing membership. Web: the user
  profile has a roles editor (`MemberRolesEditor.tsx`) limited to what the
  signed-in person may grant, with the head-coach switch.
- Owner actions (`OwnerOrganizationActions`; web: Settings › Organization,
  `OrganizationOwnerSettings.tsx`): an owner creates another gym and owns
  it; transfers ownership to an active member and stays as admin; archives
  the gym after typing its slug. Archiving closes the gym to everyone; only
  the vendor deletes a gym for good (ADR-087), so there is no hard delete
  for owners. The platform subscription is not built yet.
