# ADR-119: PR visibility for gym coaches and explicit sharing grants
Date: 2026-10-12
Status: Accepted

## Context
ADR-055 keeps Pantheon personal records (PRs: `user_pr_records`,
`user_pr_history`) owned by the global user, "with optional organization
provenance and explicit sharing grants". The grants were never built, and the
only RLS policy on both tables is owner-only (`user_id = app.user_id`). The
TD-046 harness showed the consequence (TD-070): in production no staff member
can read a member's PRs, so the admin dossier PR tab is always empty; its
controller test had to opt out of RLS enforcement.

Investigating TD-070 also showed that the member's own Pantheon endpoints
(`/api/prs`) ran without any ownership scope: under the production runtime
role every create was rejected by `user_pr_records_owner_policy` and every read
was empty. Nothing ever wrote a PR's `organization_id` either, so "provenance"
existed only as a column.

The owner decided the visibility rules:

1. Every coach of a gym can read members' PRs, gym-scoped: a coach of
   organization A sees only PRs whose `organization_id = A`, of users with an
   active membership in A. PRs without provenance (personal) are never visible
   to coaches.
2. Owners and admins cannot see PRs unless they are also coaches.
3. Coach visibility is on by default; each user can turn it off for all their
   gyms (owner-only setting). Off means coaches see nothing of theirs.
4. A user can share their whole PR table, read-only, with any accounts they
   pick, regardless of gym, and revoke it.
5. Single-PR sharing (`SharePR`, in-app or out-of-app) stays unchanged.

Multi-role memberships (a role set per membership, coach scope, coaching
relationships) are being built separately, so this decision must not change
the membership/role model.

## Decision
Enforce PR visibility in PostgreSQL with additional permissive `FOR SELECT`
policies, keep every write owner-only, and route every "is the session user a
coach of org X" decision through one seam.

- **Coach seam.** `milos_acting_user_coaches(org_id uuid)` (SQL, `STABLE`,
  `SECURITY DEFINER`, `SET search_path = public, pg_temp`) is the single
  database answer. Today: an active membership of the session user in `org_id`
  with `role = 'coach'`. Its application mirror is
  `Organizations.acting_user_coaches?/1` (delegating to
  `Organizations.Domain.TenantAuthorization.coaches?/1`, `role == :coach`).
  Owners and admins are therefore not coaches under the single-role model.
- **Coach read policy.** `user_pr_records_coach_read_policy` admits a row when
  `milos_pr_visible_to_acting_coach(user_id, organization_id)` holds: the PR
  has provenance, the provenance equals the session's `app.organization_id`
  (a coach reads only inside that gym's tenant scope), the session user coaches
  that gym (via the seam), the PR owner has an active membership there, and the
  owner has not opted out. It is `SECURITY DEFINER` because the coach's session
  can see neither the owner's membership nor their preference row.
- **Opt-out.** `user_pr_sharing_preferences` (`user_id` primary key,
  `coach_visibility boolean default true`), owner-only RLS. No row means the
  default (visible to coaches).
- **Explicit grants.** `user_pr_share_grants` (`id`, `user_id` owner,
  `grantee_user_id`, `created_at`, `revoked_at`), a personal table without
  `organization_id`. RLS: the owner manages their grants
  (`user_pr_share_grants_owner_policy`); a grantee can read grants naming them
  (`user_pr_share_grants_grantee_read_policy`). A partial unique index allows
  one active grant per pair; a check forbids self-grants; both user FKs cascade
  on account deletion. `user_pr_records_grantee_read_policy` admits every PR of
  an owner who has an active grant naming the session user - independent of
  gym and of the coach opt-out. Revocation stamps `revoked_at` (kept as a
  record of past sharing).
- **History follows its record.** `user_pr_history_shared_read_policy` admits a
  history row when its parent PR is visible to the session under any
  `user_pr_records` policy.
- **Provenance is written.** `POST /api/prs` accepts an optional
  `organization_slug`; it must resolve to one of the caller's active
  memberships (`422 pr_organization_unavailable` otherwise). Provenance is set
  only at creation; updates and corrections never change it. The web form
  defaults to the selected gym and offers "Personal".
- **Ownership scope everywhere.** Every Pantheon application service runs in an
  explicit `RepoContext` scope through `Pantheon.with_user_context/2` (owner and
  grantee operations) or `Pantheon.with_tenant_context/2` (coach reads).
  `pantheon/pr_store` joined the `mix milos.architecture` tenant-scope gate.
- **Dossier.** `GET /api/org/:slug/admin/users/:id/prs` now admits
  owner/admin/coach (new `:tenant_staff` pipeline; the rest of the dossier stays
  owner/admin-only). A coach receives `visibility: "coach"` and the PRs recorded
  in this gym (with history). Staff who are not coaches receive
  `visibility: "coach_role_required"` and an empty list without any PR read -
  a role-safe empty state rather than `403`, so the dossier composes uniformly
  and can explain why the panel is empty.
- **Sharing API** (user-scoped, global): `GET /api/pr-sharing`,
  `PUT /api/pr-sharing/coach-visibility`, `POST /api/pr-sharing/grants`,
  `DELETE /api/pr-sharing/grants/:id`, `GET /api/pr-sharing/shared-with-me`.
- **UI.** Profile gets a "PR sharing" section (coach-visibility toggle; grant
  management using the existing tenant user search); the Pantheon page gets a
  read-only "Shared with me" section; the dossier PR panel shows the
  coach-only notice for non-coach staff.

## Rationale
Database enforcement keeps the rule true for every code path, including
future ones, which is the lesson of TD-046/TD-070. Permissive SELECT-only
policies widen reads without touching the owner-only write path, so grantees
and coaches are read-only by construction (an update attempt by a grantee hits
the owner policy and finds nothing). Requiring the provenance to equal the
session's tenant keeps coach visibility gym-scoped even for a person who
coaches in several gyms. A single seam function makes the multi-role swap a
one-line change in one place instead of an edit to every policy.

## Alternatives Considered
- **Additive `coaches` flag on `organization_memberships`** (the original
  TD-070 brief for "owner/admin who also coaches"): dropped by the owner
  because multi-role memberships are implemented separately; it would have
  been a second, conflicting role model.
- **Application-only filtering** (staff reads as superuser or with a widened
  session): rejected - it is exactly what failed silently before (TD-070) and
  leaves any new query unprotected.
- **Opt-out as a `users` column**: rejected - `users` is Identity's table and
  exempt from RLS; a Pantheon-owned personal table keeps the preference inside
  the bounded context and owner-only under RLS.
- **Hard-deleting revoked grants**: rejected in favour of `revoked_at`, which
  keeps who-had-access history at negligible cost.
- **`403` for non-coach staff on the dossier PR route**: rejected - the dossier
  shell composes sections independently; a typed empty state lets the UI
  explain the rule instead of rendering an error.

## Consequences
- **Multi-role swap (one line).** When memberships carry a role set
  (`organization_memberships.roles`, branch `claude/loving-franklin-vuxz19`),
  replace the last predicate of `milos_acting_user_coaches/1`:

  ```sql
  AND om.role = 'coach'            -- today
  AND 'coach' = ANY (om.roles)     -- after multi-role (or: om.roles && ARRAY['coach']::varchar[])
  ```

  and mirror it in `TenantAuthorization.coaches?/1`
  (`:coach in membership.roles`). Nothing else changes: the policies call only
  the helper. "Owner/admin who is also a coach" then becomes true automatically
  - an owner whose role set contains `coach` passes the seam - so there is no
  owner-with-flag rule or test today; it is covered by the swap.
- **Coach scope and coaching relationships must not narrow PR visibility.** The
  owner's rule is that *all* coaches of the gym see members' PRs.
  `coach_scope = 'own'` and `coaching_relationships` (multi-role branch) govern
  other coaching surfaces; the PR seam must not consult them.
- After the multi-role merge, the dossier PR route maps to the capability that
  branch assigns to `AdminUserController.prs` (`:view_client_training`); the
  database still restricts actual rows to coaches.
- Legacy PRs (created before provenance was written) stay personal: there is no
  backfill, because the gym they were set in is unknown. Owners can re-record
  them, or share them explicitly.
- Account deletion removes grants in both directions (FK cascade) and the
  preference row. Grants and preferences carry no `organization_id`, so they are
  personal tables in the tenancy audit, not part of any `TenantDataPolicy`;
  tenant export/purge (ADR-107) neither exports nor deletes them, exactly as
  for other user-keyed personal tables.
- Coaches currently reach only the dossier PR endpoint; the rest of the dossier
  shell and the user directory remain owner/admin-only, so a coach-facing
  dossier UI arrives with the multi-role capability model.

## Implementation Notes
- Migration `20261014170000_add_pr_coach_visibility_and_sharing_grants`
  (assigned range 20261014170000-20261014179999; the originally assigned
  20261012170000 range collided with a parallel branch). It is additive: two
  new tables, two helper functions, three new SELECT policies; existing
  policies are untouched.
- Found and fixed while implementing: the `/api/prs` endpoints were broken under
  the runtime role (no ownership scope). The services now take a context first
  (`ListUserPRs.call(context, opts)`, `CreatePR.call(context, params)`, ...);
  the user-id arities remain for callers that already run in the owner's scope.
  `PRControllerTest` covers the whole owner flow under RLS.
- `GetAdminUserPRs` filters to the tenant's organization explicitly as well
  (`Pantheon.list_organization_records/2`), so a coach who also holds a grant
  from the member still sees only this gym's PRs in the dossier; grant-based
  reads live only in "Shared with me".
- The read-only projection for non-owners is `Pantheon.Domain.PRView`
  (PR fields + history); the PR store normalizer now includes
  `organization_id`.
- Tests: `PRVisibilityRLSTest` (application services as the RLS-enforcing role)
  covers coach-sees-gym-A, no gym-B/personal for a gym-A coach, tenant-scoped
  session, owner/admin see nothing (service and DB), opt-out hides from coaches
  but not grantees, grantee sees everything read-only, revoked grant hides,
  owner-only revocation, inactive membership hides, self/unknown grantee
  refusal, provenance validation, and single-PR sharing. The dossier controller
  test no longer opts out of RLS (`@tag rls_enforced: false` removed).
- The grantee picker reuses the tenant user search (`/me/search/users`), so in
  the UI a user picks among co-members of the selected gym; the API accepts any
  existing account id.
- Deferred: a coach-facing dossier/directory surface (multi-role capability
  work); provenance backfill for legacy PRs (needs the owner's input per PR);
  surfacing provenance (gym name) on Pantheon cards.
