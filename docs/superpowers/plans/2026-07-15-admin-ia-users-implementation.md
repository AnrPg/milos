# Admin IA and Users Implementation Plan
Date: 2026-07-15
Status: Completed

## Goal

Restructure the admin workspace information architecture with minimal additive changes, add a canonical Users section and user profile surface, move finance analytics to Analytics & Marketing, make Finance operational, and preserve the existing Classes and Personal Coaching pages except for naming and navigation alignment.

Authoritative decision documents:

- `docs/superpowers/specs/2026-07-15-admin-ia-users-decision.md`
- `docs/adr/ADR-035-admin-information-architecture-and-user-profiles.md`

## Non-Negotiable Constraints

- Follow the design doc architecture constraints.
- Write or update OpenAPI specs before controller implementation.
- Controllers call Application Services, not Repo or domain modules directly.
- Cross-context user profile reads are composed in Application Services.
- Contexts expose data through public APIs only.
- Generated TypeScript clients under `apps/web/src/api/generated/` are regenerated, not manually edited.
- Keep changes additive and minimal where possible.
- Preserve existing page design patterns, style, and behavior, especially for Classes and Personal Coaching.

## Phase 1: Navigation Shell and IA Relabelling

### Goal

Update admin navigation and route presentation to match the final IA while making the smallest possible page changes.

### Scope

- Admin top navigation:
  - Dashboard
  - Users
  - Finance
  - Classes
  - Personal Coaching
  - Workouts
  - Analytics & Marketing
  - Messages
- Small-screen navigation:
  - keep Dashboard as the main dropdown navigation hub
  - prefer visible mobile links for Dashboard, Classes, Personal Coaching, and Messages
- Rename or relabel existing Classes page only; do not redesign it.
- Rename or relabel existing Personal Coaching page only; do not redesign it.
- Rename Settings-facing UI to App configurations and move it into a subtle Dashboard utility affordance.
- Ensure Workouts is present as a primary top-level destination.
- Move Challenges out of primary navigation.

### Backend Work

- No backend schema changes expected.
- Add redirects or route aliases only if required for navigation compatibility.
- Preserve existing APIs.

### Frontend Work

- Update admin navigation definitions and responsive visibility rules.
- Update Dashboard dropdown contents.
- Add a subtle App configurations entry in Dashboard.
- Keep existing Classes and Personal Coaching page components intact.
- Ensure Workouts appears in primary desktop navigation.
- Remove Challenges from primary navigation and prepare its destination under Analytics & Marketing.

### Tests

- Frontend route/navigation tests where available.
- Manual responsive checks for desktop and mobile nav.
- Confirm existing Classes and Personal Coaching workflows still behave as before.

### Live Test

- Desktop: navigate to every primary admin section from top nav.
- Mobile: confirm Dashboard dropdown exposes hidden destinations.
- Confirm Classes and Personal Coaching pages are only relabelled and not functionally changed.

### Completion Criteria

- Primary admin navigation matches ADR-035.
- Mobile navigation follows the Dashboard-hub model.
- App configurations is subtle and reachable.
- Challenges is no longer a primary top navigation item.

## Phase 2: Finance and Analytics & Marketing Repositioning

### Goal

Make `/admin/finance` the operational finance surface and move broad finance analytics plus Challenges into Analytics & Marketing.

### Scope

- `/admin/finance` becomes the canonical Finance Operations experience.
- Add a succinct operational attention strip below the Finance hero.
- Keep only crucial attention items in the strip:
  - overdue invoices
  - unallocated or blocked finance items
  - pending refund or reversal actions
  - urgent entitlement or membership blockers
  - referral reward actions only when they require operator attention
- Move finance analytics to Analytics & Marketing:
  - active memberships
  - revenue charts
  - package distribution
  - broad financial trends
  - retention or membership trend views
- Create or update Analytics & Marketing subsections:
  - Overview
  - Finance Analytics
  - Training Analytics
  - Coaching Analytics
  - User Engagement
  - Health / Incidents
  - Challenges
  - Marketing
- Move Challenges under Analytics & Marketing.
- Add Marketing links:
  - Promotions -> `/admin/finance?tab=promotions`
  - Referrals -> `/admin/finance?tab=referrals`
  - Packages -> `/admin/finance?tab=packages`

### Backend Work

- Prefer reusing existing finance summary, operational queues, analytics, challenges, promotions, referrals, and package endpoints.
- Add or adjust endpoint contracts only if the current APIs cannot support the one-line attention strip or analytics relocation cleanly.
- If new endpoint contracts are needed, update OpenAPI first and regenerate the TypeScript client.

### Frontend Work

- Repoint `/admin/finance` to the operational finance component.
- Preserve current finance operations tabs and behavior.
- Add support for `?tab=promotions`, `?tab=referrals`, and `?tab=packages` if not already present.
- Move analytics-heavy Finance dashboard content into Analytics & Marketing > Finance Analytics.
- Add Marketing subsection cards/links that deep-link to finance operation tabs.
- Move Challenges UI under Analytics & Marketing.

### Tests

- Finance operations renders at `/admin/finance`.
- Deep links open the expected Finance operation tabs.
- Analytics & Marketing renders Finance Analytics and Challenges.
- Existing finance operation actions still work.

### Live Test

- Open `/admin/finance` and confirm it is operational, not analytics-heavy.
- Confirm the attention strip fits in one line at desktop widths and degrades cleanly on mobile.
- Open Analytics & Marketing and confirm finance analytics and Challenges are reachable.
- Use Marketing links to reach Promotions, Referrals, and Packages tabs.

### Completion Criteria

- Finance is operational.
- Finance analytics lives in Analytics & Marketing.
- Challenges lives in Analytics & Marketing.
- Marketing links navigate to the correct Finance operation tabs without duplicating management UIs.

## Phase 3: Users Directory and Profile Dossier

### Goal

Create the canonical admin Users section for all users and add a role-aware user profile dossier with finance, training, PRs, scores, health incidents, coaching context, and messages.

### Scope

- Add `/admin/users` directory.
- Directory includes members, athletes, and admins.
- Suggested tabs:
  - All
  - Members
  - Athletes
  - Admins
- Add `/admin/users/:id` profile shell.
- Profile sections:
  - Overview
  - Finance
  - Training history
  - PRs
  - Scores
  - Health / incidents
  - Coaching context
  - Class participation
  - Messages
  - Admin actions
- Finance information is shown for both members and athletes.
- Profile shell is consistent across roles; role determines which sections have data and which actions are available.

### Backend Work

OpenAPI first. Add contracts for focused reads, preferring a profile shell plus sub-endpoints over one heavy all-data endpoint.

Recommended endpoints:

- `GET /api/admin/users`
  - paginated directory
  - filters: `q`, `role`, and optional attention/status filters
- `GET /api/admin/users/:id`
  - common profile shell
  - identity, role, account status, available sections, high-level attention
- `GET /api/admin/users/:id/finance`
  - finance profile summary and operational links/actions for members and athletes
- `GET /api/admin/users/:id/training-history`
  - class participation, assigned workouts, executions, and scores
- `GET /api/admin/users/:id/prs`
  - detailed PR records
- `GET /api/admin/users/:id/incidents`
  - health and injury reports
- `GET /api/admin/users/:id/messages`
  - communication summary or thread references

Implementation boundaries:

- Compose cross-context reads in `MilosTraining.Application.*`.
- Use public APIs from Identity, Finance, Scheduling, Workouts, Execution, Gamification, Wellbeing, Coaching, and Messaging.
- Do not import foreign Ecto schemas across contexts.
- Do not put business logic or cross-context stitching in controllers.

### Frontend Work

- Add Users nav destination and route.
- Build directory using existing table/list/search design patterns.
- Build profile shell with section navigation.
- Reuse existing finance, coaching, wellbeing, gamification, execution, and messaging UI patterns where possible.
- Link profile actions back to owning operational surfaces when appropriate, instead of duplicating complex workflows.

### Tests

- Backend controller tests for admin-only access, filtering, not found, and forbidden shapes.
- Application service integration tests for user profile composition.
- Domain tests only if new pure interpretation logic is introduced.
- Frontend tests for directory rendering, profile navigation, and empty states where available.
- OpenAPI export and TypeScript regeneration.

### Live Test

- Admin can view all users.
- Admin can filter members, athletes, and admins.
- Admin can open a member profile and see finance, training, PRs, scores, incidents, and messages where data exists.
- Admin can open an athlete profile and see finance, coaching, training, PRs, scores, incidents, and messages where data exists.
- Admin can open an admin profile without broken role assumptions.
- Non-admin users cannot access the admin Users endpoints or screens.

### Completion Criteria

- Users is the canonical admin person directory.
- User profile sections expose the agreed role-aware dossier.
- Finance appears for both members and athletes.
- Cross-context composition follows the architecture rules.
- Existing Finance, Classes, Personal Coaching, Workouts, Analytics & Marketing, and Messages surfaces remain stable.

## Commit Order Guidance

For each phase, keep commits atomic and dependency ordered:

1. Documentation or ADR updates if phase scope changes.
2. OpenAPI contract changes.
3. Backend application/query/domain changes.
4. Controller/router changes.
5. OpenAPI export and TypeScript client regeneration.
6. Frontend route/navigation/component changes.
7. Tests.

## Deferred Work Policy

Any deferred implementation discovered during these phases must be appended to `docs/technical_debt.md` with a new `TD-NNN` row, including phase, reason deferred, priority, and date.
