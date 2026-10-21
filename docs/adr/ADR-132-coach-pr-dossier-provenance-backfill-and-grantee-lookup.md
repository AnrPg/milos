# ADR-132: Coach PR dossier surface, legacy PR provenance backfill and exact-nickname grantee lookup
Date: 2026-10-13
Status: Accepted

## Context
ADR-129 made members' PRs readable by every coach of the gym they were
recorded in, through one database seam (`palee_acting_user_coaches/1`). It left
four items (TD-091):

1. **The multi-role seam swap.** Once memberships carry a role set, the seam
   must test `'coach' = ANY(om.roles)` so an owner or admin who also coaches is
   a coach. The multi-role merge already did this (migration
   `20261015100000_make_membership_lookups_role_set_aware`, and
   `TenantAuthorization.coaches?/1` reads the role set), but no test covered an
   owner+coach account reading a member's PR.
2. **A coach-facing surface.** The dossier PR endpoint
   (`GET /api/org/:slug/admin/users/:id/prs`, `:tenant_staff` pipeline) admits
   coaches and ignores coach scope, but a coach could not get there: coaches
   have no Users link (navigation-by-role.md: "Home · Coaching"), the directory
   and the full profile shell (`GET .../admin/users/:id`) are narrowed to a
   coach's own clients (ADR-100), and the dossier page rendered "could not be
   loaded" whenever the profile was refused. So in practice a coach saw only
   their own clients' PRs - coach scope narrowed PR visibility, contrary to the
   owner's rule.
3. **Legacy PRs have no provenance.** PRs recorded before ADR-129 have
   `organization_id IS NULL` and are therefore personal - invisible to every
   coach. ADR-129 skipped a backfill because "the gym is unknown".
4. **Grantees outside one's gyms.** The API accepts any account id as a grantee,
   but the picker searches only co-members of the selected gym.

## Decision
- **Seam swap: regression tests only.** `PRVisibilityRLSTest` now proves that
  an owner+coach and an admin+coach account pass the seam in the service and in
  the database, and that a coach with `coach_scope: :own` and no coaching
  relationship still reads the member's gym PR. No code change.
- **Coach PR dossier surface.**
  - `GET /api/org/:slug/admin/pr-members` (`:tenant_staff`, next to the dossier
    PR route; `RouteCapabilities` lists it under `:view_client_training`)
    returns the gym's active members (id, nickname, avatar, role, joined_at;
    the acting user excluded) when the caller coaches the gym, and
    `visibility: "coach_role_required"` with an empty list otherwise - the
    same role-safe shape as the PR endpoint. Coach scope does not narrow it.
  - The PR endpoint now also returns `member` (id, nickname, avatar) when the
    person is an active member of the gym, so the page can title a dossier the
    full profile refused.
  - Web: the coach home (and the owner/admin dashboard when they also coach)
    gets a **Members' PRs** section with a nickname filter, linking to
    `/admin/users/:id#prs`. The dossier page fetches the PR panel for any
    coach; when the profile is refused (client scope) and the PR endpoint names
    an active member, it renders a **PR-only dossier** (header + PRs + a note
    that the rest belongs to the member's own coaches and managers). Every other
    section stays capability- and scope-gated exactly as before. Navigation is
    unchanged (no Users link for coaches), as the role navigation spec wants.
- **Legacy provenance backfill**: data migration
  `20261016120000_backfill_legacy_pr_provenance`. PR records have no link to a
  source execution or workout (they are typed in by hand), so the gym is
  inferred from the owner's own data and only when unambiguous:
  1. *Execution evidence*: the owner's workout executions that started within
     one day either side of `beaten_on` (UTC; the window absorbs time zones)
     all belong to exactly one organization -> that organization.
  2. *Membership evidence*: no execution evidence at all, the owner has exactly
     one organization membership (any status), and it was joined no later than
     the PR was recorded -> that organization.

  Everything else stays personal. History rows of a backfilled record take the
  record's provenance (as new snapshots do). Only rows with
  `organization_id IS NULL` are touched, so it is idempotent; `down` is a no-op.
- **Global grantee lookup**: `GET /api/pr-sharing/grantee-lookup?nickname=`
  (user-scoped, own 30/min rate-limit bucket) returns `{grantee: {id,
  nickname, display_nickname}}` for an EXACT normalized nickname match, and
  `{grantee: null}` for unknown nicknames and for oneself. No prefix or fuzzy
  matching, no avatar, no email, no gyms. The PR sharing settings show a
  "Find by exact nickname" button next to the co-member search; the result is
  granted through the existing `POST /api/pr-sharing/grants`.

## Rationale
- A dedicated member list keeps ADR-100 intact: the directory and the full
  profile still show coaches only their clients, while the PR rule (all coaches
  of the gym) gets its own, narrower door that reveals only public co-member
  identity - which any member already sees through `/me/search/users`.
- Reusing the dossier route with a PR-only fallback means one URL per member,
  the same `#prs` deep link for owners/admins who coach, and no new page.
- The backfill only widens visibility where the gym is unambiguous, and the
  database still requires an active membership and honours the opt-out, so a
  wrong guess cannot expose a PR to a gym the person does not belong to.
- Nickname existence is already public (`GET /api/auth/nickname-available`), so
  an exact-match lookup that returns only the id adds no enumeration surface.

## Alternatives Considered
- **Widen the directory for coaches** (all members, not just clients):
  rejected - it would undo ADR-100 for every directory consumer and leak
  finance status.
- **Add a Users/Clients link to the coach navigation**: rejected - the role
  navigation spec deliberately hides Users from coaches; the home section is
  where coaches already find "My clients".
- **Return the full profile shell to coaches with only `prs` available**:
  rejected - it changes the profile endpoint's scope semantics for every
  consumer; the PR endpoint carrying `member` is narrower.
- **Mix task / Oban job for the backfill**: rejected - application code runs
  under the RLS-enforcing role, and PR records are owner-only; a one-off
  maintenance pass would need a new bypass scope. The migration role already
  bypasses RLS and runs once per environment.
- **Execution-only inference**: considered; the single-membership rule was kept
  because most legacy accounts belong to one gym and rarely log an execution on
  the PR day. It requires the membership to predate the PR.
- **Email or prefix search for grantees**: rejected - email lookups are an
  account-existence oracle for addresses, and prefix search enumerates
  accounts.

## Consequences
- After the migration, legacy PRs of single-gym members become visible to that
  gym's coaches (unless the member opted out). This is the owner's ADR-129 rule
  applied to old data; members keep the opt-out.
- A coach can list every active member of the gym (public identity). Owners
  and admins who are not coaches get an empty list, matching PR visibility.
- The grantee lookup confirms that an exact nickname exists - already public
  through the nickname-availability check.

## Implementation Notes
- Migration range assigned: 20261016120000-20261016129999; used 20261016120000.
- The backfill's history update touches only history rows with
  `organization_id IS NULL` whose record now has provenance.
- `ListPRDossierMembers` and `GetAdminUserPRs` resolve membership through
  `TenantUserAccess` (`list_active_membership_user_ids`, SECURITY DEFINER
  backed), so they work in a coach's RLS session.
- Tests: `PRVisibilityRLSTest` (owner+coach, admin+coach, coach scope),
  `AdminUserDirectoryControllerTest` (coach lists members and opens the PR
  panel while the profile is 403; owner gets the empty state; owner+coach gets
  the list and the PRs; members get 403), `PRControllerTest` (exact lookup:
  normalized match, no prefix, no self, no unknown, 400 for blank),
  `PRProvenanceBackfillMigrationTest` (single gym + history, execution
  evidence, ambiguous cases, pre-membership PRs, existing provenance kept,
  idempotent re-run); web unit tests for `dossierMode` and
  `filterDossierMembers`.
- Deferred: surfacing provenance (gym name) on Pantheon cards (ADR-129); a way
  for the owner to correct provenance on a backfilled PR (provenance is fixed
  at creation by design - owners can re-record or opt out).
