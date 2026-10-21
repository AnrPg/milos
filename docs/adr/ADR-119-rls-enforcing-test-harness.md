# ADR-119: Controller Tests Run Under the RLS-Enforcing Runtime Role
Date: 2026-10-12
Status: Accepted

## Context
The test suite connects to Postgres as a superuser (`rolbypassrls = true`).
Row Level Security therefore never applies in ordinary tests, so a query that
skips `RepoContext.run/2`, or a policy that is narrower than the code assumes,
passes locally and returns nothing (or refuses the write) in production, where
`PrivilegeGuard` requires a non-superuser role. This let all nine platform
organization commands ship broken (TD-046). `RLSCase` could prove a single
policy on a raw connection, but it could not run application code.

## Decision
1. Every `PaleeWeb.ConnCase` test dispatches requests through
   `PaleeWeb.RLSEnforcedEndpoint`. That test-only endpoint runs each
   request inside the sandbox transaction as the non-superuser
   `palee_test_runtime` role (`SET LOCAL ROLE`) and then restores the role.
   Fixtures and assertions outside the request keep the superuser role, so
   existing tests did not need rewriting, while the controller → application →
   store path runs exactly as it does in production.
2. A test opts out only with `@tag rls_enforced: false` and a comment naming
   the debt item that explains why.
3. Application- and store-level tests can enforce RLS for the whole test with
   `@moduletag :rls_enforced`, using `bypass_rls/1` only for fixture setup.
   `PALEE_TEST_ENFORCE_RLS=1` applies this to every DataCase test, as a probe
   for migrating further tests.

## Rationale
Scoping enforcement to the request puts it where production runs as the
restricted role, without forcing hundreds of fixtures to model RLS. A
mutation test confirmed the harness catches the bug class: removing a single
`RepoContext.run/2` wrap from `ListProvisionedOrganizations` fails the
enforced suite, while the old superuser mode stays green.

## Alternatives Considered
- **A separate CI job running the whole suite as the runtime role:** the probe
  failed 382 of 819 tests, almost all fixture setup rather than production
  code. It would need a fixture rewrite before it could be a gate.
- **Opt-in tagging of root-tenant-table test files only** (the minimum
  TD-046 asked for): rejected once enforcing every request proved feasible.
  Opt-in coverage decays as new controllers are added.

## Consequences
- Any new controller test exercises RLS by default.
- Channel tests still connect sockets as the superuser (sockets are not
  dispatched through `call/2`); the endpoint delegates PubSub functions.
- Whole-suite DataCase enforcement remains future work (TD-078).

## Implementation Notes
Turning enforcement on surfaced these production defects, all fixed in this
change:
- **Workout execution start was refused (403) for self-selected, class-booking
  and assigned workouts.** `/api/executions` is user-scoped, and tenant
  derivation read `master_workouts`/`assigned_workouts` without an
  organization scope. The organization is now derived by reading the workout
  inside each of the actor's active memberships.
- **Staff were never notified of member-triggered events, and Oban event jobs
  could not write notifications.** `organization_memberships` RLS shows a
  member only their own row, and `notifications` is owner-only, including on
  INSERT. Fixes:
  - a narrow `SECURITY DEFINER` function, `palee_organization_user_ids/2`,
    returns an organization's active (optionally role-filtered) user ids, and
    only to sessions inside that organization;
  - staff and co-member lookups use it within a tenant scope;
  - each notification is written inside its recipient's user scope.
- **System tenant resolution failed in jobs** (`:organization_not_found`). An
  additive read-only policy lets a session scoped to an organization read that
  organization's own row, and `FindOrganization.by_id` reads in that scope
  (resolves TD-076).
- **Missing `RepoContext.run/2` wraps:** invitation issue/revoke, membership
  role and status changes, active-member listing (admin directory, finance
  search, member user search), gamification preferences read/write, and
  notification click facts (now recorded in the notification's organization;
  organization-less clicks are only marked read).
- **Policy gap, not fixed:** staff cannot read members' PRs because
  `user_pr_records` is owner-only and ADR-055's sharing grants are not
  implemented. The single affected dossier test opts out and points at TD-077.
- **Harness bug fixed during development:** `use Phoenix.VerifiedRoutes`
  overwrites `@endpoint`, so ConnCase now assigns it after that `use`.
