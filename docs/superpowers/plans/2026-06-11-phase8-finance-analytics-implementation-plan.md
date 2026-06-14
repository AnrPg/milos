# Phase 8 Finance and Analytics Implementation Plan
Date: 2026-06-11
Status: Planning

## Purpose

Implement an MVP of the expanded Phase 8 scope: Finance, basic analytics,
admin search, and all planned admin/user pages. The MVP must lay the full
schema and infrastructure foundation for the full-blown implementation now, even
when some workflows remain stubbed or only lightly surfaced until later phases.

This plan intentionally prioritizes additive, minimal, architecture-aligned
changes. Avoid broad rewrites. Preserve existing code style, naming, context
patterns, controller/application-service boundaries, and the current Phoenix +
Next.js structure.

## Schema Foundation Principle

For Phase 8, "MVP" means limited workflow depth and limited UI coverage, not
throwaway or underspecified data modeling.

Create the durable schema foundation for the full intended product up front:

- Model the full Finance, Wellbeing, Feedback, analytics, and search foundations
  as first-class entities.
- Prefer nullable fields, inactive statuses, lifecycle statuses, and unused but
  documented columns over later destructive migrations.
- Add indexes, foreign keys, unique constraints, status checks, and snapshot
  columns needed to preserve historical meaning.
- Use JSON/map fields only for explicitly extensible parameters, not as a
  shortcut around relational entities that are already known.
- Create pages and API surfaces for future areas as stubs where needed, but back
  them with stable schemas and context boundaries now.
- Defer complex business workflows only after the data model can support them
  without later breaking changes.

## Required Reading Before Implementation

Before writing code, read these files in full:

- `AGENTS.md`
- `docs/superpowers/specs/2026-06-05-gym-app-design.md`
- `docs/superpowers/plans/2026-06-05-gym-app-implementation.md`
- `docs/adr/README.md`
- Relevant ADRs in `docs/adr/`
- `docs/technical_debt.md`
- `docs/superpowers/plans/2026-06-11-phase8-analytics-audit.md`
- `docs/superpowers/plans/2026-06-11-phase8-analytics-dimensions.md`
- `docs/superpowers/plans/2026-06-11-phase8-finance-referrals.md`
- `docs/superpowers/plans/2026-06-11-phase8-wellbeing-feedback.md`
- `docs/superpowers/plans/2026-06-11-phase8-admin-search-index.md`
- `docs/superpowers/plans/2026-06-11-notification-read-push-hardening.md`

Follow the existing architecture rules:

- Controllers call Application Services, not Repo.
- Application Services orchestrate and do not query the DB directly.
- Domain logic stays pure.
- Infrastructure owns Ecto and external adapters.
- Commands write; Queries read.
- Public endpoints must have OpenAPI specs before controller behavior.
- Generated TypeScript API files are regenerated, not manually edited.
- Cross-context side effects use public APIs or PubSub events.

## Phase 8 MVP Scope

The MVP must include the full foundational schemas and infrastructure for:

- A new Finance bounded context.
- Membership packages.
- Memberships.
- Package subscriptions.
- Payments.
- Promotions and referrals entities, even if workflow UI is minimal.
- `finance_aggregates` materialized view.
- Basic `coaching_aggregates` materialized view or summary query surface.
- Admin search endpoint with Meilisearch or a safe DB fallback if Meilisearch integration is incomplete.
- `/admin` dashboard with Finance and Coaching tabs.
- Dedicated pages, even if some are stubs:
  - `/admin/finance`
  - `/admin/reviews`
  - `/admin/wellbeing`
  - `/reviews`
  - user-visible injury/recovery history page or section
- Feedback context for reviews.
- Wellbeing context for injury reporting/healing.
- Basic analytics cards/tables from real persisted data.

MVP analytics should be honest. If a slice is not backed by real persisted data
or a clear derived read model, show it as unavailable or stubbed, not as fake
data.

MVP workflows may remain narrow. MVP schemas should not. If a later planned
feature is already understood, include the stable table/column/lifecycle shape
now and leave the advanced workflow as a stub or deferred command.

## ADR Work

Before implementation code, create a new ADR:

`docs/adr/ADR-NNN-phase8-finance-analytics-wellbeing-feedback.md`

The ADR must decide:

- Finance becomes a bounded context.
- Wellbeing and Feedback are added as bounded contexts, or explicitly justify
  if they are implemented inside existing contexts.
- Financial analytics use `finance_aggregates`.
- Basic coaching analytics use `coaching_aggregates`.
- Admin search uses Meilisearch for fuzzy lookup, with Postgres as source of
  truth for financial totals.
- Referral rewards are admin-reviewed/manual in v1.
- Review editing policy for v1: append-only or editable with history.

Update `docs/adr/README.md` after adding the ADR.

## MVP Implementation Steps

### 1. Finance Context Skeleton

Create:

- `apps/api/lib/milos_training/finance.ex`
- `apps/api/lib/milos_training/finance/`
- `apps/api/lib/milos_training/infrastructure/finance/`
- ports, commands, queries, and schemas following existing context style.

Start with the full known schema but keep abstractions thin. Add only behaviour
ports, commands, and queries needed by the MVP endpoints/tests, while keeping
the underlying schema ready for later commands.

### 2. Finance Migrations

Add full foundational migrations for:

- `membership_packages`
- `memberships`
- `membership_package_subscriptions`
- `membership_payments`
- `promotion_campaigns`
- `promotion_codes`
- `promotion_redemptions`
- `referral_programs`
- `referral_events`
- `referral_rewards`
- `finance_aggregates` materialized view

Prefer additive migrations. Do not alter existing tables destructively. The goal
is to avoid future breaking migrations by including known relationships and
lifecycle fields now, even if some are nullable or unused in MVP UI.

Foundational fields are described in:

- `docs/superpowers/plans/2026-06-11-phase8-finance-referrals.md`

Do not reduce those entities to minimal string fields. For example,
`membership_packages` must be an object with code, family, billing period, tags,
parameters, status, and price fields, and memberships must support multiple
package subscriptions through a join table from the start.

### 3. Finance Domain and Commands

Implement basic commands:

- Create/update membership package.
- Create/update membership.
- Assign package to membership.
- Record payment.
- Create promotion campaign/code.
- Record promotion redemption.
- Create referral program.
- Record referral event.
- Approve/apply/reject referral reward.

Domain logic:

- Membership status derivation.
- Expiring soon calculation.
- Renewal count calculation.
- Price band calculation.
- Referral reward status transition validation.

Keep domain modules pure and unit-tested.

### 4. Finance Queries and Aggregates

Implement queries:

- List packages.
- Get member finance profile.
- List expiring memberships.
- Financial summary.
- Payment history.
- Package performance.
- Promo/referral summary.

Create `finance_aggregates` materialized view for:

- Monthly revenue.
- Active membership count.
- Expiring count.
- Revenue by package.
- Revenue by user type.
- Promo-attributed discounts.
- Referral-attributed signups/revenue.
- Pending referral rewards.

Add an Oban refresh job:

- `MilosTraining.Workers.RefreshFinanceAggregatesJob`

Use `CONCURRENTLY` only if the view has the required unique index.

### 5. Coaching Aggregates MVP

Add a minimal `coaching_aggregates` materialized view or query-backed summary.

MVP fields:

- Active athletes.
- Inactive athletes.
- Completed workouts by week.
- Notes written by week.
- Average completion rate.
- Recent workout note count.

Prefer a materialized view if the implementation is straightforward. If joins
become too large for the first slice, ship a query-backed summary and document
the deferred materialized-view conversion in technical debt.

### 6. Feedback Context MVP

Create the foundational Feedback context:

- `reviews`
- `review_answers`

MVP endpoints:

- User submits workout review.
- User submits general review.
- User lists own reviews.
- Admin lists reviews.
- Admin marks review as reviewed or needs follow-up.

MVP pages:

- `/reviews`: current user's submitted reviews.
- `/admin/reviews`: admin review inbox, filters can be basic.

Do not overbuild configurable questionnaire management in MVP. Still create the
schema in a way that can support questionnaire versions later, and store
structured answers so the questionnaire can become configurable without
rewriting reviews.

### 7. Wellbeing Context MVP

Create the foundational Wellbeing context:

- `injury_reports`
- `injury_status_events`

MVP endpoints:

- User reports injury.
- Admin reports injury for user.
- User/admin marks injury healed.
- User lists own injury history.
- Admin lists injuries and filters by active/healed/user.

MVP pages:

- User injury/recovery history page or section.
- `/admin/wellbeing`: active injuries and recently healed list.

The schema should already support reopen events, admin notes, visibility,
severity, body area, tags, and training limitations, even if only report/heal
flows are active in MVP.

### 8. Admin Search MVP

Implement:

- `MilosTraining.Infrastructure.Search.MemberIndexer`
- `MilosTraining.Workers.IndexUserJob`
- `GET /api/admin/search`

Minimum filters:

- `q`
- `role`
- `user_type`
- `membership_status`
- `package_code`
- `expires_within_days`

Index user documents with denormalized finance and engagement fields. Postgres
remains source of truth for dashboard totals.

If Meilisearch client setup is blocked, implement a DB-backed fallback search
for MVP and document Meilisearch completion as high-priority technical debt. The
index document design should still include the full planned facet shape so the
Meilisearch implementation does not require a contract redesign later.

### 9. Admin Finance API

Add OpenAPI specs and controllers for:

- `GET /api/admin/finance/summary`
- `GET /api/admin/finance/packages`
- `POST /api/admin/finance/packages`
- `PATCH /api/admin/finance/packages/:id`
- `GET /api/admin/finance/members/:id`
- `PATCH /api/admin/finance/members/:id`
- `POST /api/admin/finance/members/:id/packages`
- `POST /api/admin/finance/members/:id/payments`
- `GET /api/admin/finance/promotions`
- `POST /api/admin/finance/promotions`
- `GET /api/admin/finance/referrals`
- `POST /api/admin/finance/referrals/:id/approve`
- `POST /api/admin/finance/referrals/:id/reject`
- `POST /api/admin/finance/referrals/:id/apply`

Keep controller logic thin. Validate through OpenAPI and changesets.

### 10. Admin Dashboard Pages

Build `/admin` with:

- Finance tab.
- Coaching tab.
- Search box.
- Basic drill-down panels.

Create or update pages:

- `/admin/finance`: packages, expiring memberships, recent payments, promo/referral basics.
- `/admin/reviews`: review inbox.
- `/admin/wellbeing`: injury reports.
- Existing `/admin/coaching`: keep working, optionally link from dashboard.

Stubs are acceptable for deep workflows in MVP if they:

- Are reachable.
- Clearly show "not implemented yet" only for deferred actions.
- Do not display fake analytics.
- Link to the relevant implemented MVP pages/actions.
- Sit on top of real context/API/schema foundations where the future workflow is
  already known.

### 11. Frontend API and State

Add typed API helpers outside generated files.

Regenerate OpenAPI client after backend spec updates:

- `apps/web/src/api/generated/openapi.json`
- `apps/web/src/api/generated/schema.ts`

Use existing frontend patterns:

- TanStack Query for server state.
- Existing admin page visual language.
- No manual edits to generated clients.

### 12. Telemetry and Fact Capture MVP

MVP telemetry/fact capture:

- Membership created/updated.
- Payment recorded.
- Referral status changed.
- Review submitted.
- Injury reported/healed.
- Notification clicked.
- Push dispatch result, if feasible.

For self-hosted analytics, persist domain facts in DB first. Use telemetry as
secondary instrumentation unless a telemetry event is explicitly persisted.

### 13. Tests

Backend:

- Finance domain unit tests.
- Finance command/query integration tests.
- Feedback controller tests.
- Wellbeing controller tests.
- Admin search tests.
- Finance aggregate refresh test where practical.

Frontend:

- Lint/type-check touched pages.
- Manual smoke tests for all new pages.

### 14. Live Test Checklist

Run the app and verify:

- Admin creates a membership package.
- Admin creates/updates a user membership.
- Admin assigns a package to a membership.
- Admin records a payment.
- Finance summary updates after aggregate refresh.
- Admin sees expiring memberships.
- Admin search finds users and filters by package/status/type.
- User submits a review.
- Admin sees the review in `/admin/reviews`.
- User reports an injury.
- Admin sees injury in `/admin/wellbeing`.
- User marks injury healed.
- Injury remains in history.
- `/admin`, `/admin/finance`, `/admin/reviews`, `/admin/wellbeing`, and `/reviews` all load.

## MVP Technical Debt Updates

At MVP completion, update `docs/technical_debt.md` for any deferred pieces.

Expected entries should describe deferred workflow depth, not missing core
schemas. Examples:

- Complex membership package entitlement evaluation and enforcement.
- Configurable review questionnaire admin UI if the schema exists but management UI is deferred.
- Full communication thread workflow if thread schemas exist but deep triage is deferred.
- Attendance/no-show UI and policies if attendance schemas exist but full workflows are deferred.
- Exercise catalog curation UI if metadata schemas exist but import/management is deferred.
- Push delivery receipt workflow if dispatch-attempt schema exists but external receipts are limited.
- Full Meilisearch indexing if DB fallback shipped.

## Post-MVP Extension Plan

### Extension 1: Package Entitlements

Implement and enforce richer package rules already anticipated by the foundational schema:

- Visit limits.
- Class-type restrictions.
- Remote programming entitlements.
- Pause policies.
- Location/channel restrictions.
- Promo/referral interaction rules.

### Extension 2: Attendance and Class Analytics

Implement workflows and analytics over the foundational attendance/class schemas:

- `attendance_records`.
- No-show and late-cancel logic.
- Waitlist if needed.
- Coach/room/class-series fields.
- Class attendance aggregates.

### Extension 3: Exercise Catalog

Implement catalog management and analytics over the foundational exercise metadata schemas:

- Exercise catalog.
- Movement pattern.
- Equipment.
- Muscle groups.
- Skill domain.
- Progression levels.
- Mapping from workout exercise names to catalog entries.

### Extension 4: Communication Threads

Implement full workflows over the foundational communication schemas:

- `communication_threads`.
- `communication_messages`.
- Thread status.
- Response latency.
- Unanswered-message analytics.
- Sentiment/manual triage tags.

### Extension 5: Advanced Feedback

Implement management UI and deeper analytics over the foundational Feedback schemas:

- Admin-configurable questionnaires.
- Review edit history or append-only revision model.
- Review tagging workflows.
- Satisfaction aggregates by package, coach, class type, workout type, and injury status.

### Extension 6: Advanced Wellbeing

Implement richer recovery workflows over the foundational Wellbeing schemas:

- Recurrence detection.
- Training limitation suggestions.
- Injury-aware warning surfaces in workout/class views.
- Injury x exercise exposure analytics.

### Extension 7: Engagement Aggregates

Add `engagement_aggregates` materialized view for:

- Last active bucket.
- Completion rate bucket.
- Communication status.
- Satisfaction bucket.
- Churn risk.
- Training type affinity.

### Extension 8: Analytics Event Pipeline

Add persisted analytics facts for non-state events:

- Page/entity opened.
- Workout started/abandoned.
- Notification clicked.
- Push dispatch result.
- Message sent/thread resolved.

Use telemetry events at write boundaries and persist the facts needed for
self-hosted reporting.
