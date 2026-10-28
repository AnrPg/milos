# ADR-217: People are shown by their roles in the business; staff have no finance profile
Date: 2026-10-28
Status: Accepted

## Context
ANR (2026-10-28) saw a box owner in «Χρήστες» as «Μέλος box» with finance
status «Δοκιμαστικό», and owners/independent coaches listed in the finance
ledger as if they were on a trial. Staff need no package and must never show
in the finance ledger or finance analytics.

Nothing assigned a trial package. The causes:
1. The Users list, the admin profile and the finance ledger read
   `users.role`, the account-wide role from before role sets (ADR-099). It is
   `member` for every account that is not an athlete, owners included, so the
   owner read as a box member and got member-only sections (Finance).
2. The finance ledger listed every active person of the gym, staff included,
   and the web showed `"trial"` as the status of anyone without a finance
   profile. A click on a staff row (status, package) then created a real
   finance profile (`user_type_snapshot: "member"`, status `trial`), which
   counted in the analytics.
3. The setup checklist counted the owner's own account as a client, so
   «Invite» looked done before anyone was invited.

## Decision
1. **The roles a person holds in a business (`organization_memberships.roles`,
   ADR-099) are the only source of their standing there.** Lists, profiles,
   finance, analytics and permissions read them; `users.role` stays an
   account-level fact (auth, platform), never a business one.
   - `Organizations.member_roles_by_user/1`, `list_client_user_ids/1` and
     `client_role/2`; `MembershipPolicy.client?/1`, `staff?/1`,
     `client_role/1`; `TenantUserAccess.tenant_roles/2`.
   - `AdminProfilePolicy` takes a role set. Staff-only people get no Finance
     or coaching sections; someone who is staff and also holds a client role
     gets the client's sections.
   - The Users list returns `role` (primary role in the box), `roles`,
     `coach_scope`, `staff` and `client`. It shows a «Ρόλοι» column (head coach
     = coach with `coach_scope: all`), tints staff rows, and filters
     Everyone · Box members · Athletes · Staff. Staff rows show no
     membership status.
   - The admin profile header and overview list every role in the box.
2. **Only clients (member or athlete role) have a finance profile.**
   `UpdateFinanceMember`, `AssignFinanceMemberPackage`, beneficiaries and
   staff-given corporate seats refuse anyone else with `422 not_a_client`.
   Nothing creates a profile or package automatically; a staff member gets one
   only after a member or athlete role was given to them explicitly. A new
   profile starts `active`, never a placeholder `trial`. The finance ledger
   and the finance people picker list clients only; a missing profile shows
   «Χωρίς οικονομικό προφίλ», never a made-up status.
3. **Cleanup** (migration `20261227100000`): finance profiles of people who are
   staff-only in that gym and never moved money (no invoice, payment,
   reversal, refund, credit, entitlement use or referral reward) are deleted
   with their package rows. A staff-only person with money history keeps the
   record, since that money is real, but is no longer listed.

## Consequences
- The search index document still carries the account-wide role; in a gym
  the search answer replaces it with the client role there.
- Role assignment rules (downward only) are ADR-216's.
