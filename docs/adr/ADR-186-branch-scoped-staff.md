# ADR-186: Branch-scoped staff and the branch manager
Date: 2026-10-23
Status: Accepted

## Context
A business with several branches (ADR-141 locations) has staff who work at
only some of them: a front desk at Κηφισιά, a coach at Κηφισιά and Μαρούσι, a
manager who runs one shop. Until now every staff membership worked at every
location, so a Κηφισιά front desk could check people in at Μαρούσι, and the
only way to let someone run a branch was to make them an admin of the whole
business. ANR approved option C1: a branch scope on the membership, enforced by
one domain policy, plus a branch manager built on top of it (milestone M4).

## Decision

### 1. One branch scope per membership
- `organization_memberships.all_locations` (default `true`) is the explicit
  «Όλα τα καταστήματα» flag. When it is `false`, `membership_location_scopes`
  lists the membership's branches, one row per branch. The table is tenant
  scoped (RLS, `palee_apply_tenant_context` trigger, classified in the tenancy
  audit), with composite foreign keys to `(organization_memberships.id,
  organization_id)` and `(facility_locations.id, organization_id)`, so a scope
  can never name another business's branch.
- Archived branches drop out when the scope is read (the rows stay, so
  un-archiving gives the branch back). A scoped membership whose branches are
  all archived has an empty scope: it sees nothing located, never everything.
- The scope belongs to the membership, not to each role: one person has one
  set of branches for all of their staff roles. Per-role scopes were rejected
  as a matrix nobody can read in the UI and a source of contradictions (coach
  at A but front desk at B is rare; two memberships are not possible, so the
  rare case uses the union).
- Owners are always `:all`, and so are memberships with only client roles
  (member, athlete): clients are not affected by branch scope.

### 2. One policy, one context field
- `Palee.Organizations.Domain.LocationScopePolicy` (pure) holds every rule:
  `effective/3`, `covers?/2`, `authorize/2`, `filter/3`, `restrict/2`,
  `desk_location/2`, `narrow_capabilities/2`, the grant rules and parsing.
- `TenantContext.location_scope` (`:all` or sorted ids) is computed once per
  request in `ResolveTenantContext`. Only scoped memberships cost a read.
- Areas call it through `Palee.Organizations` (`authorize_location/2`,
  `filter_by_location_scope/2,3`, `desk_location/2`, ...). Class and
  appointment checks are centralised in `Application.ClassLocation`.
- Capability narrowing: scoped staff lose the capabilities that act on the
  whole business (`LocationScopePolicy.organization_wide/0`: gym settings,
  finance settings, clubs, creating businesses, lifecycle, platform
  subscription, granting admin). Since §7/§8, reports, packages and
  promotions are no longer withheld: they follow the branches instead. A new `manage_locations` capability (admin and owner) lets a branch
  manager edit their own branches without `manage_settings`; creating and
  archiving branches stay `manage_settings`. The narrowed capability map is
  what the memberships payload sends, so the web gates follow automatically.

### 3. Enforcement per area
Located things are checked against their branch; "no branch" means
all-scoped staff only unless the table says otherwise.

| Area | Enforcement | Without a branch |
|---|---|---|
| Class slots (create, edit, move, delete, workout link) | location authorized; a move checks both ends | all-scoped only |
| Bookings, attendance, placing members, trials queue/accept/decline | slot's branch | all-scoped only |
| Schedule calendar (staff view) and its locations list | filtered | hidden |
| Injury warnings, goal feedback on a slot | slot's branch | all-scoped only |
| Desk check-in, check-in list, visitors | `desk_location`: one-branch staff default to it, wider scopes must choose | not allowed for scoped staff |
| Door display / kiosk, posters, NFC tags | location authorized | — |
| Location settings | list filtered; update needs the branch in scope | — |
| Appointment slots and bookings | slot's branch; a client always cancels their own | the slot's own coach |
| Events (`location_id`) | staff list filtered; edit/cancel need scope | all-scoped staff or the event's creator (ADR-185 organisers keep their own events) |
| Cleaning areas and entries | area's branch | all-scoped only |
| Machines and machine events | machine's branch | all-scoped only |
| Supplies | unscoped | shared stock |
| Finance summary and queues, statistics, coaching athletes and programming week | filtered by branch (§7) | people count at their home branch; facts with neither count only for all-scoped staff |
| Packages, promotions, programme assignments | covering scope (§8) | valid everywhere = visible to all staff; created or changed only inside the scope |
| Seasons, referral programmes | all-scoped only (§8) | business-wide |
| Inventory spending report | all-scoped only | stays single-branch (§7) |
| People, directory, payments | unscoped | members roam between branches |
| Community moderation | capability narrowed (`manage_community`) | the club is shared |

Members and athletes keep their own views (bookings, self check-in, member
schedule) untouched.

### 4. Branch manager («Υπεύθυνος καταστήματος») = admin + branch scope
No new role. A branch manager is an `admin` membership with a branch scope.
Reasons: the capabilities are exactly the admin's minus the whole-business
ones, which the scope already removes; scope is an orthogonal dimension, so a
new role would duplicate the matrix (`AccessPolicy`, route capabilities, the
rights document, every web gate) and invite drift; and "front desk at one
branch" or "coach at two" need the same mechanism anyway. The UI offers it as
a preset (admin + branches).
- The role ceiling of ADR-099 stays: only owners grant `admin`, so only owners
  appoint branch managers.
- Nobody grants a scope wider than their own (`authorize_grant`).
- A branch-scoped granter manages only memberships whose stored scope is
  inside theirs (clients always): they cannot change a person who also works
  at another branch, nor widen anyone, nor themselves. The check runs on the
  role, coach-scope and branch-scope commands alike.
- Owners cannot be branch-scoped (`owner_location_scope`).

### 5. Invitations
- `registration_invitations` gains `roles` (subset of the eight roles),
  `all_locations` and `location_ids` (1–200), with check constraints. The
  single `role` stays (it holds the primary role), so old links and clients
  keep working: a request with only `role` behaves as before, and an
  invitation without branches gets the issuer's own scope (`:all` for owners
  and all-scoped admins).
- Every staff role can be invited, including front desk, accountant and
  janitor; each role passes the issuer's ceiling.
- On redemption the membership gains the roles and the scope. A client-only
  membership takes the invited branches; existing staff get the union; `:all`
  wins.

### 6. Admin UI
- Admin › Χρήστες › profile: a branch picker («Όλα τα καταστήματα» or a set of
  branches) next to the roles, and an owner-only «Υπεύθυνος καταστήματος»
  preset. The invitation dialog lets staff invitations pick roles and
  branches.
- The schedule, check-in desk and location lists show only the person's
  branches because the API filters them; the slot location picker drops "any
  branch" for scoped staff.
- A business with at most one active branch sees no new UI.

### 7. Page branch filter on reports (follow-up, 2026-10-23)
The finance, statistics and coaching admin pages get a header control
«Καταστήματα: Όλα ▾»: a themed checklist in `ui/Popover`, remembered per page
in the browser. It shows only to staff who see at least two active branches.

- Endpoints accept `location_ids` (a list or one comma-separated string),
  narrowed to the person's scope (`Organizations.report_filter/2`). Asking
  for a branch outside the scope never widens it; it drops out.
- Facts with a branch (check-ins, class attendance) are filtered by it.
  Facts without one (payments, invoices, memberships, reviews, injuries,
  workouts, coaching threads) are filtered by person.
- Each person has at most one **home branch**
  (`Organizations.Domain.BranchAttribution`):
  1. Among the branches their packages allow, the one where they had the
     most check-ins plus attended classes in the last 90 days.
  2. With no activity, the only branch their packages allow, when they allow
     exactly one.
  3. Otherwise none.
  One home per person keeps per-branch splits additive. People without one
  count only in the business totals that all-scoped staff see.
- When two or more branches are shown, the response carries `branches`: one
  row per branch (finance: active memberships, paid revenue, open invoices;
  statistics: check-ins, attended classes, active memberships, paid revenue).
  `branch_filter` echoes what was applied.
- Every tab of the finance operations page follows the page filter
  (2026-10-23). The list endpoints accept `location_ids` the same way and
  echo `branch_filter` (`BranchReport.resolve_list/2`), but a list names no
  branch by default: without `location_ids` it stays as before, since
  people roam (§3) and covering items are already scoped (§8).
  - Members (`/finance/members`): the people whose home branch is in the
    filter, through the same attribution.
  - Packages and promotions: the ones valid at one of the chosen branches
    or everywhere (`BranchReport.covering_only/3`); each row shows a branch
    badge.
  - Queues tab: the same read as the attention summary.
  - Referral events (referrer or referred) and rewards (recipient), and
    refund receipts (their person), by home branch as the queues count them.
  - Business-wide, with a note under the tabs: seasons and referral
    programmes (§8), corporate clients, payment reconciliation and
    accounting exports.
- `view_finance_reports`, `view_business_analytics`, `manage_packages` and
  `manage_promotions` leave `organization_wide/0`. Gym settings, finance
  settings, clubs, lifecycle, platform subscription and granting admin stay
  narrowed.
- Check-in, inventory and cleaning stay single-branch.

### 8. «Ισχύει για» on create forms (follow-up, 2026-10-23)
Create forms of staff who see two or more branches get «Ισχύει για» chips.
They default to the person's branches (or the page filter, where there is
one). The server re-checks every chip against the scope.

- **One-place items** (class, class series, appointment slot): N chips
  create N separate items in one transaction, all or nothing
  (`ClassLocation.create_all/4` on `Scheduling.transaction/2` /
  `Appointments.transaction/2`). The response adds `slots` / `series_list`,
  and the UI confirms «Δημιουργήθηκαν N μαθήματα: …» with links. Editing
  keeps the single branch picker: an item lives at one branch.
- **Covering items** are one item valid at the chosen branches:
  - packages: `facility.location_ids`;
  - promotions and programme assignments: new `all_locations` +
    `location_ids` columns (migration `20261208100000`).
  Staff see a covering item when it is valid everywhere or at one of their
  branches. They create or change it only inside their scope
  (`Organizations.authorize_covering/2`). A branch staff member who names no
  branches gets their own. «Όλα τα καταστήματα» (dynamic, future branches
  included) is for all-scoped staff only.
- A promotion valid at some branches applies only to a subscription whose
  package is valid at one of them (or everywhere). Otherwise the redemption
  fails with `promotion_location_not_included` (422).
- Seasons and referral programmes are business-wide: only all-scoped staff
  create or change them.

## Alternatives considered
- **A new `branch_manager` role.** Rejected (section 4).
- **Scope per role.** Rejected (section 1).
- **Postgres RLS on the location.** Rejected: RLS is the tenant boundary;
  branch scope is an authorization rule with per-area exceptions (events by
  creator, appointment slots by coach, supplies shared) that belongs in the
  domain, and members must still see every branch.
- **Array column on the membership.** Rejected: no foreign keys, so deleted
  or foreign locations could not be prevented.

## Consequences
- Every new located feature must call `Organizations.authorize_location/2` or
  `filter_by_location_scope/2,3` (or `ClassLocation`), and decide what "no
  branch" means; this ADR's table is the place to record it.
- Reports follow the branch filter (§7, resolves TD-187 for finance,
  statistics and coaching; the inventory spending report stays all-scoped).
- A branch-manager admin who also trains sees the filtered staff schedule;
  other scoped staff who also train keep the member view (TD-186).

## Implementation notes
- Migrations `20261207100000_membership_location_scopes`,
  `20261207110000_invitation_role_sets_and_location_scope`.
- Store `Palee.Organizations.LocationScopeStore` (port, facade, Ecto adapter).
- `PUT /api/admin/users/:id/location-scope` (`grant_staff_roles`).
- New errors: `location_out_of_scope` 403, `location_scope_exceeded` 403,
  `location_required` 422, `invalid_location_scope` 422,
  `owner_location_scope` 422, `cannot_change_own_membership` 403.
- Tests: `location_scope_policy_test.exs`, `branch_scoped_staff_test.exs`.
- §7/§8: `Application.BranchReport`, `CoveringBranches`, `PackageBranches`;
  migration `20261208100000_covering_branch_scopes`; tests
  `branch_attribution_test.exs`, `multi_branch_test.exs`; web
  `admin/BranchFilter.tsx`, `admin/AppliesToBranches.tsx`.
