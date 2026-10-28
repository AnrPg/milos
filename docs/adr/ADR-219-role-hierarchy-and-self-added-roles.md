# ADR-219: Role Hierarchy and Self-Added Roles
Date: 2026-10-28
Status: Accepted

## Context
ADR-099 says nobody grants a role above their own, and
`docs/architecture/rights-per-account-type.md` is the hierarchy. ANR asked
(2026-10-28) that higher roles change only lower ones, that the vendor sits
at the top, and that a person may add a role below their own to themselves
(an owner who also coaches) without ever changing the role they hold. An
audit of the code found:

- `SetMembershipRoles` checked only the roles being added or removed, not
  the person: an admin could add or remove lower roles of a fellow admin or
  of an owner (e.g. drop the owner's *member* role).
- `SetCoachScope` (head coach) had no hierarchy check: an admin could make
  an owner or a fellow admin head coach.
- Every change to one's own membership was refused, so nobody could add a
  role to themselves; the console's roles editor on one's own profile failed
  on save.
- The vendor console set only one role (five of the eight), replacing the
  set, and could remove a gym's last owner.

## Decision
- **Tiers.** `MembershipPolicy.tier/1`: owner 4 › admin 3 › staff (coach,
  front desk, accountant, janitor) 2 › clients (member, athlete) 1. Roles of
  one tier are peers. The vendor is above every tier.
- **On someone else** (`authorize_role_change(actor, current, requested,
  :other)`): the actor must outrank the person's top role
  (`can_manage_member?/2`) and be allowed to grant every role added or
  removed (`can_grant_role?/2`). Owners also manage co-owners (ANR chose
  this on 2026-10-28, as the document already said), and a gym always keeps
  an active owner. Head coach follows the same rule; status and branches
  already did through the grant ceiling.
- **On oneself** (`:self`): anyone adds or drops only roles ranked below
  their own top role; the top role and its peers never change
  (`own_top_role_locked`). No right to grant roles to others is needed, and
  one's branches stay as they are.
- **Endpoints.** `PUT /api/org/:slug/me/roles` for every member of the gym
  (Settings › «Οι ρόλοι μου»); `PUT /admin/users/:id/roles` also accepts the
  signed-in person's own id. The vendor's
  `PATCH /api/platform/organizations/:id/memberships/:membership_id/role`
  takes a role set (`roles`), any of the eight roles, and refuses to remove
  the last owner (`last_owner`).
- **Web.** `lib/role-hierarchy.ts` mirrors the policy. The console's roles
  editor shows only what the signed-in person may change (nothing on a
  fellow admin or an owner; only lower roles on oneself, without branches);
  Settings has «Οι ρόλοι μου», hidden for members and athletes; the vendor
  console edits role sets with the shared `RoleChipsEditor`.

## Rationale
Checking the person as well as the roles makes "only downwards" hold for
every write path, and one domain function serves the API and is mirrored
in the web, so the UI never offers what the API refuses (ADR-214).
Self-added roles below one's top role cannot raise anyone's rights above
what they already hold, so they need no one else's approval.

## Alternatives Considered
- Strict peers for owners (no owner changes a co-owner): rejected by ANR; a
  gym would be stuck with a co-owner who left.
- Self-adding only roles one may grant to others: rejected; a janitor or
  accountant who also trains could not add *member*, though that is below
  them.
- A separate membership per added role: rejected in ADR-099.

## Consequences
Role-owned state follows the role as before: dropping *member* or
*athlete* from oneself cancels future bookings or archives assignments.
Adding a staff role still takes a staff seat when the person held none
(ADR-170) and is gated in demo mode (ADR-184). The vendor path does not
reconcile role-owned state; it is a support tool.

## Implementation Notes
`MembershipPolicy` (`tier/1`, `top_tier/1`, `can_manage_member?/2`,
`self_assignable_role?/2`, `authorize_role_change/4`),
`SetMembershipRole`, `SetCoachScope`, `UpdateMembershipRole`,
`MyRolesController`. Web: `lib/role-hierarchy.ts`,
`components/roles/{RoleChipsEditor,MyRolesSection}.tsx`,
`MemberRolesEditor.tsx`, `PlatformOrganizationsPage.tsx`. Tests:
`MembershipPolicyTest`, `SetMembershipRoleTest`, `RolesAndCoachScopeTest`,
`PlatformOrganizationControllerTest`, vitest for the hierarchy and both
editors, and `e2e/my-roles.spec.ts`.
