# ADR-131: Background and system paths under RLS
Date: 2026-10-13
Status: Accepted

## Context
Production connects as the non-superuser runtime role (`milos_runtime`) with
forced row-level security. Every tenant or owner table admits rows only
through the session settings that `RepoContext.run/2` sets
(`app.organization_id`, `app.user_id`, ...). Code that reaches such a table
outside a scope reads nothing and has its writes rejected - while the test
suite, connecting as a superuser, passes.

ADR-119 made every `ConnCase` request run as the RLS-enforcing role, and the
latest merge fixed several request paths. TD-092 asked for an audit of the
remaining user-scoped paths ("check other user-scoped paths that may fail
under the production database role"), naming `Gamification.increment_advancement`
outside a scope as the example found in Pantheon.

The audit found that the biggest remaining gaps were not in request handlers
but in everything around them, plus a test-harness blind spot:

* **Oban jobs and projections** run with no session scope at all. The workout
  completion projection (`ProcessWorkoutCompletionJob` ->
  `CompleteWorkout.process_completion/1`) read no settings, executions or
  challenges and then crashed on the first `user_achievements` insert - no
  streak, total, badge or challenge progress was ever recorded in production.
  Every per-tenant cron job started from `OrganizationStore.list_organizations/0`,
  which returned no rows without a scope, so reminders, subscription expiry,
  overdue invoices, corporate invoicing, entitlement reconciliation, coaching
  reply alerts, inventory digests and the abandonment sweep all did nothing.
* **Materialized view refreshes** require ownership of the view. The views
  belong to the migration role, so every refresh (leaderboard, coaching and
  finance aggregates) failed with "must be owner of materialized view".
* **Cross-user maintenance** (staff pending-booking notices, nickname
  propagation into other users' notifications, the admin member search
  index) touched other users' or other tenants' rows from a session that
  could not see them.
* **Request paths hidden by the harness**: tests set `app.organization_id` /
  `app.user_id` on the shared sandbox connection for fixtures, and the request
  issued afterwards inherited that ambient scope. The member landing page, the
  leaderboard opt-in, the public theme, the admin settings read, the admin
  analytics dashboard and the challenge detail all passed their tests this way
  while reading nothing in production.

## Decision
1. **Every path that runs outside a request opens its own scope**, derived
   from server-side ownership (the execution's organization and user, a job's
   `organization_id` argument, the booking's organization), never from client
   input. Application services take the tenant context and wrap their reads
   and writes in the context's `with_tenant_context/2`.
2. **Legitimate cross-tenant or cross-user operations go through narrow
   `SECURITY DEFINER` functions** that answer one question or perform one
   operation and nothing else (additive migrations, `SET search_path`,
   `EXECUTE` left to `PUBLIC` like the existing `milos_*` helpers):
   * `milos_active_organization_ids()` - ids of active organizations, for cron
     fanout; each job then enters one organization at a time;
   * `milos_refresh_materialized_view(text)` - refreshes one of an allow-list
     of three views as their owner;
   * `milos_public_theme_slug(text)` - the theme slug of an active gym, for
     the unauthenticated theme endpoint;
   * `milos_propagate_notification_nickname(text, text)` - rewrites snapshotted
     nicknames only for a real rename (new nickname held by an account, old
     one by none).
   One additive policy, `organization_settings_scoped_self_read_policy`,
   mirrors the existing `organizations_scoped_self_read_policy` so a session
   scoped to an organization (a job) can read that organization's settings.
3. **Requests in tests start from a clean session**: `RLSEnforcedEndpoint`
   clears every `app.*` setting before dispatching (and restores the test's
   own afterwards), exactly like a pooled production connection.
4. **Background paths have their own runtime-role tests**
   (`BackgroundUserScopeRLSTest`, `@moduletag :rls_enforced`), including a
   guard that runs every per-tenant cron worker under the runtime role with no
   session scope.

## Rationale
* Scoping each operation to the owner it acts for keeps the RLS model intact:
  the policies stay as strict as they are, and every fix is visible at the
  call site.
* Definer functions are the established pattern for the few reads that must
  cross the boundary (`milos_organization_user_ids`,
  `milos_organization_member_roles`). Each new one exposes no row data beyond
  its single answer (ids of active organizations, a theme slug) or performs a
  fixed, idempotent operation.
* Clearing the session per request turns a whole class of silent production
  failures into failing tests at almost no cost (two existing tests changed
  behaviour; both were real bugs).

## Alternatives Considered
* **A request-wide scope plug** (open `RepoContext` for every tenant route):
  would have fixed the landing page and similar reads in one place, but it
  hides which code depends on which scope, does not help jobs, and changes the
  transaction/connection behaviour of every request. Rejected for now.
* **Running jobs or refreshes as a privileged role** (a second pool with
  `BYPASSRLS`, or granting view ownership to the runtime role): broad, and
  makes the runtime able to bypass every policy. Rejected.
* **Loosening policies** (e.g. letting any session read `organizations`):
  rejected by the brief and unnecessary.
* **Converting all ~380 DataCase tests to `MILOS_TEST_ENFORCE_RLS`**: out of
  scope; most failures are fixture setup. New background tests are enforced
  instead, and the opt-in `MILOS_TEST_DETECT_UNSCOPED=1` diagnostic reports
  unscoped queries issued by requests.

## Consequences
* Cron jobs now visit organizations through
  `Organizations.list_active_organizations_for_system/0` and must not call
  `OrganizationStore.list_organizations/0` without a vendor scope.
* `/api/landing/leaderboard-opt-in` and `/api/challenges/:id/...` moved under
  `/api/org/:organization_slug/...` (the web client already prefixed
  `/landing`; `/challenges` was added to its tenant-scoped prefixes). The
  unscoped routes are gone because they could never work under RLS.
* `GET /api/theme` reads the gym from the `X-Organization-Slug` header the web
  client sends with every request (same convention as `/api/me/search/users`);
  without it the default theme applies.
* The admin member search index documents are rebuilt per organization; a
  document still holds a single finance profile (first gym wins), as before.
* Definer functions assume the migration role owns the views and bypasses RLS
  (true for the shipped `postgres` migration role). A deployment migrating with
  a non-superuser owner would need that owner to have `BYPASSRLS` for the
  aggregates to include every tenant - the same assumption the migration-time
  `REFRESH MATERIALIZED VIEW` already made.

## Implementation Notes
Bugs found and fixed (production symptom -> fix):

| Path | Symptom under the runtime role | Fix |
|---|---|---|
| `ProcessWorkoutCompletionJob` / `CompleteWorkout.process_completion/1` (executions and training-log entries) | Job crashed on the `user_achievements` insert after reading no settings/executions/challenges: no stats, streaks, badges or challenge progress, ever | Projection runs in `%{organization_id, user_id}` of the completion |
| Per-tenant cron jobs (9 workers) | `list_organizations/0` returned nothing: every job was a no-op | `milos_active_organization_ids()` + `list_active_organizations_for_system/0`, each org read in its own scope |
| `refresh_leaderboard`, coaching and finance aggregate refreshes | "must be owner of materialized view": leaderboard and dashboards never refreshed | `milos_refresh_materialized_view/1` |
| `GetLandingPage` (member landing) | Stats, badges, challenges, leaderboard, recent executions all empty | Payload built in the tenant context |
| Leaderboard opt-in | Web called a route that did not exist (`/api/org/:slug/landing/leaderboard-opt-in`); the unscoped route raised an RLS violation (500) | Org-scoped route, service runs in tenant scope |
| Challenge leaderboard / opt-in / opt-out | Unscoped routes: every challenge 404 | Org-scoped routes and services |
| `GetAdminChallenge` (admin challenge detail) | 404; and participants were every account on the platform | Tenant scope; participants are the gym's active members |
| `GET /api/theme` | Always the default theme | `milos_public_theme_slug/1` by `X-Organization-Slug` |
| `GetAdminSettings` / settings save without gamification changes | Gamification settings shown as defaults | Read in tenant scope |
| `GetAdminAnalyticsSummary` | Whole dashboard empty (its test passed because `nil >= 1` is true) | Built in tenant scope; assertion fixed |
| `ListFinanceMembers` | Listed every non-admin account on the platform (nickname, id) to any gym's finance desk | Only the gym's active members |
| Withdraw / reject / attendance / `ReconcileBookingReleaseJob` entitlement transitions | Reservation invisible: class visits never returned or finalized (silent `:not_required`) | Context-scoped `Finance.*_entitlement_source/6` |
| `delete_booking_pending_notifications` | Staff "new booking" notices never removed (wrong session, and rows carried no organization) | Staff resolved server-side, deleted in each recipient's scope; booking notices now carry `organization_id` |
| `Workouts.list_workout_change_targets` in publish/delete | Assigned athletes never told about workout changes/deletion | Scoped variant |
| `GetAdminUserMessages` unread count | Always 0 | Inside the tenant scope |
| `PropagateNicknameJob` notification rewrite | Matched nothing | `milos_propagate_notification_nickname/2` |
| `AdminMemberSearchDocuments.build_all/0` | Documents without gyms or finance data: indexed admin search matched nobody | Built per active organization |
| `CorporateInvoicing` sender settings | Brand name / locale ignored | Scoped settings read (+ self-read policy for jobs) |

Audited and found correctly scoped: Pantheon services (ADR-129), gamification
preferences, notification inbox/push subscriptions/push dispatch and outcome
recording, `NotificationEventJob`, `DispatchMessageJob`, `BookingTimeoutJob`,
`ClassSeriesExtensionJob`, export/purge jobs (ADR-117), the abandonment sweep
internals, finance/scheduling calls made by the cron jobs, chat/execution/class
timer channels, `RealtimeEventHandler`, `RecordNotificationDelivered`.

Diagnostics: with `MILOS_TEST_DETECT_UNSCOPED=1` the test suite reports every
Ecto query a request issues against a forced-RLS table with no organization
(or no scope at all). After these fixes the only reports are deliberate
carve-outs (invitation redemption, slug-alias lookup, provisioning) and
best-effort analytics events for personal actions (see follow-ups).

Deferred:
* `notification_read` and personal wellbeing analytics events have no tenant
  provenance and are skipped by `RecordAnalyticsEvent.call_unsafe/2`.
* The admin member search document model is single-tenant (one finance
  profile per user); per-organization documents would remove the first-gym-wins
  merge.
* Raw-SQL queries (no Ecto `source`) are invisible to the diagnostic.
* The web calls `/my-workouts/assignments/:id/messages` and
  `/schedule/slots/:id/message`, which have no API routes at all (unrelated to
  RLS, found while comparing web paths to the router).
