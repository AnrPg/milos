# ADR-035: Admin Information Architecture and User Profiles
Date: 2026-07-15
Status: Accepted

## Context

The admin workspace has grown across finance, coaching, scheduling/classes, workouts, challenges, messages, analytics, and user drill-down surfaces. Earlier Phase 8 work introduced finance member drill-downs, coaching athlete drill-downs, admin search, wellbeing, feedback, communication, and analytics foundations. Those surfaces are useful but the navigation model no longer clearly separates people, operations, content, analytics, and marketing/gamification.

Admins need a canonical way to view all users, including members, athletes, and admins. A user profile must expose finance, training, PRs, scores, health incidents, coaching context, and communication history without forcing admins to know which domain-specific page originally owns each fact.

At the same time, the product should avoid a broad redesign. Existing pages for classes and personal coaching should keep their current design and behavior, with only IA naming changes in this pass. Finance operations should stay operational, while finance analytics should move into a more appropriate reporting area.

## Decision

Restructure the admin information architecture around these primary top navigation destinations:

1. Dashboard
2. Users
3. Finance
4. Classes
5. Personal Coaching
6. Workouts
7. Analytics & Marketing
8. Chat

`App configurations` replaces the visible Settings concept but is not a primary top navigation item. It is presented subtly inside Dashboard, preferably as a settings icon that reveals the full label on hover or focus.

`Users` becomes the canonical person directory and profile area for members, athletes, and admins. User profiles expose identity, role, finance information for members and athletes, training history, detailed PRs, scores, health incidents, class participation, personal coaching context, messages, and permitted admin actions.

`/admin/finance` becomes the canonical Finance Operations experience plus a succinct one-line operational attention strip under the hero. Finance is reserved for operational money work.

Finance analytics moves to `Analytics & Marketing`, including active membership counts, revenue charts, package distribution, trend reporting, and other broad analytical views.

`Classes` and `Personal Coaching` are renamed or relabelled in the IA only. Their existing page structure and behavior should remain unchanged in this pass.

`Workouts` remains a primary top-level entity because workout content is reused across classes and personal coaching.

`Challenges` is not a primary top navigation item. It moves under `Analytics & Marketing` because it is treated as a marketing, engagement, and gamification mechanism.

The Marketing subsection of `Analytics & Marketing` links to the existing operational Finance tabs:

- Promotions -> `/admin/finance?tab=promotions`
- Referrals -> `/admin/finance?tab=referrals`
- Packages -> `/admin/finance?tab=packages`

On small screens, the Dashboard button remains the main admin navigation hub with its current dropdown behavior. The preferred visible mobile destinations are Dashboard, Classes, Personal Coaching, and Chat; other destinations remain reachable from Dashboard's compact navigation.

## Rationale

This IA separates the admin workspace by job:

- Dashboard is triage and navigation.
- Users is the person-centered dossier.
- Finance is operational financial work.
- Classes is class operations.
- Personal Coaching is individualized programming operations.
- Workouts is reusable workout content management.
- Analytics & Marketing is reporting, engagement, challenges, and marketing surfaces.
- Chat is communication.

The split prevents Finance from mixing daily operator tasks with broad analytical reporting. It also prevents Users from becoming a replacement for every domain workspace: Users shows a person-centered view and deep links into domain actions where appropriate, while Finance, Classes, Personal Coaching, Workouts, Analytics & Marketing, and Chat remain the operational homes for their respective domains.

Keeping Classes and Personal Coaching structurally unchanged reduces implementation risk and preserves established design patterns. Moving Challenges under Analytics & Marketing matches the decision to treat challenges as engagement and marketing mechanics rather than a core content or scheduling entity.

Using query parameters for Promotions, Referrals, and Packages deep links keeps the Marketing area lightweight and avoids duplicating operational finance management UIs.

## Alternatives Considered

Keeping the existing Finance dashboard structure was rejected because analytical metrics such as active memberships and revenue trends obscure the operational finance workflow. Those metrics belong in Analytics & Marketing.

Making Challenges a top-level navigation item was rejected because challenges are important but not a primary entity on the same level as Users, Finance, Classes, Personal Coaching, Workouts, Analytics & Marketing, or Chat.

Putting Challenges under Workouts was rejected because the final product direction treats challenges as marketing, engagement, and gamification, not simply workout content.

Duplicating Promotions, Referrals, and Packages inside Analytics & Marketing was rejected because Finance already owns the operational management tabs. Analytics & Marketing should link to those operational surfaces rather than fork them.

Redesigning Classes and Personal Coaching was rejected for this pass because the requested change is IA naming and navigation alignment only.

Using one giant user profile endpoint for all detailed profile data was rejected as the default approach because profile tabs can become heavy and span many bounded contexts. A profile shell plus focused sub-endpoints better preserves performance, contract clarity, and context ownership.

## Consequences

The admin top navigation and Dashboard dropdown must be reorganized while preserving responsive behavior.

Routes may need redirects or aliases so existing links continue working during the IA transition, especially around schedule/classes naming and personal coaching naming. The product owner explicitly chose not to retain a legacy Finance Operations route alias.

OpenAPI contracts must be added before any new admin user directory or profile endpoints. Controllers must remain thin and call Application Services.

The user profile read model crosses Identity, Finance, Execution, Gamification, Wellbeing, Coaching, Scheduling, Workouts, and Messaging. Any composed profile or dossier endpoint must live in `MilosTraining.Application.*` and call public context APIs only.

The frontend should preserve existing design patterns and components wherever possible. This work should avoid a broad visual redesign.

Generated TypeScript API files must be regenerated from OpenAPI and never manually edited.

## Implementation Notes

Phase 1 (navigation shell and IA relabelling) started on 2026-07-15.

- Replaced the admin top-level labels with Dashboard, Users, Finance, Classes,
  Personal Coaching, Workouts, Analytics & Marketing, and Chat. Dashboard,
  Classes, Personal Coaching, and Chat remain visible at narrow widths;
  the other destinations remain available through the Dashboard navigation hub.
- Reworked the Dashboard dropdown and page navigation hub around operations,
  content, and Analytics & Marketing. Challenges is nested under Analytics &
  Marketing instead of appearing as a primary destination.
- Relabelled the existing class schedule and coaching assignment pages through
  their existing `pageTitle` props. Their components and behavior were not
  structurally changed.
- Renamed the Settings-facing UI to App configurations and added a compact
  settings-icon utility in its own row above the Dashboard hero. It reveals its
  label on hover or focus and is not part of the hero action group.
- Made `/admin/metrics` the Analytics & Marketing landing hub. It routes admins
  to Overview, Finance Analytics, Training Analytics, Coaching Analytics, User
  Engagement, Health / Incidents, Challenges, and Marketing. The previous
  broad analytics report remains available at `/admin/metrics/overview`, and
  the existing finance report is reused at `/admin/metrics/finance`.
- Added `/admin/metrics/marketing` with the final ADR deep links for Promotions,
  Referrals, and Packages. Phase 2 makes those `/admin/finance?tab=...` URLs
  select the matching operational tab directly.
- Added an admin-protected `/admin/users` route shell so the Phase 1 navigation
  destination is valid while the full directory and role-aware dossier remain
  scoped to Phase 3.
- Preserved existing APIs; no backend or OpenAPI changes were required for
  Phase 1. The legacy `/admin/finance/operations` frontend alias was removed at
  the product owner's request when Phase 2 made `/admin/finance` canonical.

Validation: targeted ESLint and TypeScript checks passed, the Next.js production
build passed, and the eight route destinations exercised for this slice returned
HTTP 200 from the built app. Responsive behavior is encoded at the existing
768px breakpoint with an overflow-safe narrow-screen link strip; browser-level
visual QA remains part of the phase live-test checklist.

No new technical debt was deferred during this slice. Phase 3 (Users directory
and profile dossier) remains outstanding.

Phase 2 (Finance and Analytics & Marketing repositioning) completed on
2026-07-15.

- `/admin/finance` now renders the operational members, packages, promotions,
  referrals, and queues tabs. The previous `/admin/finance/operations` route
  was removed rather than retained as an alias, per product-owner direction.
- Finance shows a compact, horizontally resilient attention strip immediately
  below its hero. It surfaces only available urgent queue signals: overdue
  invoices, pending payments, pending referral rewards, and overdue balance.
- Promotions, Referrals, and Packages use bookmarkable canonical URLs at
  `/admin/finance?tab=...`; invalid tab values safely fall back to Members.
- Finance reporting is preserved at `/admin/metrics/finance`. Dashboard finance
  analytics cards link there, while operational finance alerts link to the
  canonical Finance tabs.
- `/admin/metrics` is the Analytics & Marketing landing page, with Overview,
  Finance Analytics, Training Analytics, Coaching Analytics, User Engagement,
  Health / Incidents, Challenges, and Marketing destinations. Marketing links
  open the canonical Finance tabs rather than duplicating their management UI.

Phase 2 validation: targeted ESLint and TypeScript checks passed; the Next.js
production build passed; the Finance root, three Marketing tab deep links,
Analytics & Marketing hub, finance analytics, Marketing, and Challenges routes
returned HTTP 200 from the built app; the removed legacy Finance Operations
route returned HTTP 404. No new backend contract or technical debt was needed.

Phase 3 (Users directory and profile dossier) completed on 2026-07-15.

- Added contract-first `GET /api/admin/users` and `GET /api/admin/users/:id`
  operations to the existing admin-only controller boundary.
- `ListAdminUsers` composes Identity and Finance public APIs to provide all-role
  filtering, nickname search, pagination metadata, account state, and available
  finance status without importing foreign schemas.
- `GetAdminUserProfile` provides the common role-aware shell: identity,
  account state, available sections, attention placeholder, and links back to
  the owning operational workspaces.
- Replaced the temporary Users route with a live All/Members/Athletes/Admins
  directory and added the dynamic `/admin/users/:id` profile shell route.
- Added focused, admin-only dossier contracts for Finance, training history,
  PRs, health incidents, messaging, and coaching context. The public routes are
  `/api/admin/users/:id/finance`, `/training-history`, `/prs`, `/incidents`,
  `/messages`, and `/coaching-context`; each has a stable `user_id` boundary and
  returns role-safe empty states rather than leaking role assumptions.
- Kept cross-context stitching in six `MilosTraining.Application.*` read
  services. They call only the public Identity, Finance, Workouts, Execution,
  Pantheon/Gamification, Wellbeing, Coaching, and Messaging APIs. No new table,
  migration, direct Repo access, or cross-context schema import was introduced.
- Extracted the role-to-section and operational-link rules into the pure
  `Identity.Domain.AdminProfilePolicy`. This keeps role interpretation out of
  controllers and gives the common shell and focused reads one policy source.
- Training history treats class-linked workout executions as the durable class
  participation evidence available to this dossier and flattens persisted
  section scores into a dedicated score surface. Athlete assignment context is
  reused from the established coaching drill-down instead of implementing a
  second assignment interpretation.
- Messaging returns thread references, participant IDs, counts, and the latest
  message summary. The dossier links to the existing Chat workspace for
  full conversation operations rather than duplicating thread management.
- The frontend loads each focused section independently with TanStack Query, so
  the profile shell can render immediately and unavailable role sections do not
  issue requests. Finance, training, PRs, scores, incidents, coaching, class
  participation, messages, and role administration now render live data and
  explicit empty states.
- Role changes continue through the existing `UpdateUserRole` application
  service and contract. Operational actions deep-link to their owning Finance,
  Classes, Personal Coaching, Workouts, Analytics, and Chat surfaces.
- Regenerated OpenAPI JSON and TypeScript schemas after defining the focused
  contracts. Domain, application, controller, authorization, not-found, and
  OpenAPI tests cover the dossier boundary.

Phase 3 validation: 13 focused backend tests passed; targeted ESLint and the
full TypeScript check passed; the production Next.js build passed; and the
built `/admin/users`, `/admin/users/:id`, `/admin/finance`, and `/admin/metrics`
routes returned HTTP 200. The complete backend precommit suite was also run.
No Phase 3 technical debt was deferred.

The 2026-07-17 dossier refinement keeps the same focused-endpoint architecture
while tightening person relevance and operator context:

- Empty history-only sections are omitted from both the profile navigation and
  body after their focused reads resolve. Finance and admin actions remain
  visible because they are operational surfaces even when their source records
  are empty.
- The Finance dossier now returns and renders membership state, package
  subscriptions, referral claims, referred members, and referral rewards in
  addition to entitlement allowances and the existing Finance drill-down.
- Pantheon PR history is included through the Pantheon public API. Admin PR
  cards use the same compact supporting-metric text as Pantheon and show the
  achieved date for every archived result.
- The landing-page workout CTA is conditional: it resumes an active execution,
  opens an approved booked class within two hours of its scheduled time, or
  opens an athlete assignment due today. It is absent when none applies.
- Admin Home now follows Dashboard directly in the top navigation.

No new persistence, migration, dependency, or technical debt was introduced.
