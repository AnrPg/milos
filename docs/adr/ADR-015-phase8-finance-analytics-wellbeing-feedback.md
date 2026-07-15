# ADR-015: Phase 8 Finance, Analytics, Wellbeing, and Feedback Foundations
Date: 2026-06-11
Status: Accepted

## Context

The original Phase 8 plan called for an admin dashboard with financial
analytics, coaching analytics, fuzzy search, and drill-down views. Subsequent
product planning expanded the scope: financial analytics must be backed by real
membership/package/payment data, users must be able to report injuries and
healing, users must be able to submit reviews for several target types, and
admin search must support finance, progress, injury, and satisfaction facets.

The existing design doc enumerates the initial bounded contexts, but the new
scope introduces product domains that do not fit cleanly inside the existing
contexts:

- Finance: memberships, packages, payments, promotions, referrals, and financial
  aggregates.
- Wellbeing: injury reports, healing, active limitations, and history.
- Feedback: reviews, ratings, questionnaires, and review triage.

The implementation plan also requires full schema foundations in the MVP, even
when some workflows remain stubs, to avoid future breaking migrations.

## Decision

Add three bounded contexts: `MilosTraining.Finance`, `MilosTraining.Wellbeing`,
and `MilosTraining.Feedback`.

Finance owns membership packages, memberships, package subscriptions, payments,
promotion campaigns/codes/redemptions, referral programs/events/rewards, and
`finance_aggregates`.

Wellbeing owns injury reports and injury status events.

Feedback owns reviews, review answers, and future questionnaire versions.

The admin dashboard reads financial totals from PostgreSQL materialized views
and context query APIs. Meilisearch is used for fuzzy admin user lookup and
filterable facets only; PostgreSQL remains the source of truth for accounting,
analytics totals, reviews, injuries, and referrals.

Referral rewards are admin-reviewed/manual in v1 using an explicit lifecycle:
`pending`, `approved`, `applied`, and `rejected`.

Reviews are append-only in v1. Admin triage may update review status and tags,
but user-authored answers are not rewritten without a future revision model.

## Rationale

Finance is a standalone domain because packages, payments, promotions, and
referrals have accounting and audit concerns that should not live in Identity,
Scheduling, or Coaching.

Wellbeing applies to both athletes and gym members, so placing injuries inside
Coaching would incorrectly narrow ownership to remote athletes and coach notes.

Feedback targets workouts, classes, exercises, packages, coaching, and general
gym parameters. Keeping it separate avoids scattering review persistence across
many contexts and makes satisfaction analytics coherent.

Materialized views keep dashboard reads stable as the number of executions,
payments, reviews, injuries, and referrals grows. Keeping Meilisearch as a
lookup index prevents fuzzy-search convenience from becoming the accounting
source of truth.

## Alternatives Considered

Putting Finance inside Coaching:
rejected because financial membership/payment data applies to gym members and
athletes and has different consistency and audit requirements than coaching
notes.

Putting injury reports inside Coaching:
rejected because members can also report injuries, and injury analytics must
cross classes, workouts, exercises, memberships, and satisfaction data.

Putting reviews inside Workouts or Scheduling:
rejected because reviews can target many entity types, including gym parameters,
coaching parameters, packages, and general feedback.

Using Meilisearch for analytics totals:
rejected because indexed documents are denormalized lookup projections and are
not suitable as an auditable source for finance or aggregate reporting.

Shipping minimal MVP tables and expanding later:
rejected because the product owner explicitly wants full schema foundations now
to avoid breaking migrations when deeper workflows are implemented later.

## Consequences

The original bounded-context list is expanded. Future agents must treat Finance,
Wellbeing, and Feedback as first-class contexts with their own commands, queries,
ports, schemas, and infrastructure adapters.

Controllers must still call application services. Cross-context composition for
dashboard and search reads belongs in application services or context public
APIs.

The MVP may expose some pages as stubs, but the underlying schemas should
anticipate the full planned workflows: package entitlements, referrals,
promotions, injury history, review questionnaires, triage, and aggregate slices.

Finance, Wellbeing, and Feedback facts can later feed `finance_aggregates`,
`coaching_aggregates`, and `engagement_aggregates` without ownership confusion.

## Implementation Notes

Initial MVP implementation created the foundational migration with finance,
wellbeing, feedback, attendance, communication, analytics-event,
notification-click, push-dispatch-attempt, exercise-catalog, `finance_aggregates`,
and refreshed `coaching_aggregates` structures.

Finance now has Ecto schemas, a store port, an Ecto adapter, public context API,
admin application services, admin controller routes, an aggregate refresh worker,
and an admin finance page. Membership packages, membership profiles, package
subscriptions, payments, promotion campaigns, and referral events are usable as
manual MVP workflows. Hardening added promotion-code entities, manual promotion
redemption, referral reward entities, admin routes, route-level tests, and
search slicing by membership/package dimensions. Automated renewal/invoicing,
entitlement enforcement, and automatic referral reward application remain
explicit technical debt.

Wellbeing now has injury reports, status events, user/admin application services,
controllers, and user/admin pages. User healing is scoped to the current user's
own reports; admin healing remains intentionally unrestricted within the admin
pipeline. Deeper workout/class safety surfacing is deferred.

Feedback now has reviews, answers, questionnaire schema, store port/adapter,
user/admin services, controllers, and user/admin pages. Users can submit
reviews; admins can list and mark reviews reviewed. Questionnaire authoring and
target-specific default selection are deferred.

Admin search now returns Identity role plus finance membership/package metadata
from PostgreSQL-backed context APIs. Meilisearch-backed fuzzy indexing is still
planned as an additive optimization, not a source-of-truth replacement.

Phase 8B added a first-class Analytics context over the foundational fact
tables: `analytics_events`, `notification_click_events`, `push_dispatch_attempts`,
`attendance_records`, `communication_threads`, `communication_messages`, and
`exercise_catalog_entries`. The current implementation exposes recording APIs
for analytics events, notification clicks, push attempts, attendance, and
exercise catalog entries, plus a persisted-facts summary used by
`GET /api/admin/analytics/summary`.

Phase 8B instrumentation records non-critical analytics events after successful
primary writes for payments, promotion redemptions, referral event/reward
changes, review submissions, injury report/heal flows, notification reads, and
notification clicks. These analytics writes are intentionally non-blocking for
the primary workflow. The admin analytics page reads persisted facts and owning
context summaries; it does not show synthetic values for missing slices.

Phase 8 hardening on 2026-06-11 fixed several cross-layer correctness and
architecture issues. `finance_aggregates` now uses a fact-union materialized
view grain so payments, promotion redemptions, referral events, and rewards are
aggregated independently before package/user-type rollup, avoiding one-to-many
join multiplication. Finance aggregate refresh is scheduled through Oban cron
alongside leaderboard refresh.

Promotion code creation now accepts the legacy `fixed` alias only inside the
Finance domain normalization path, while API/UI contracts use the canonical
`fixed_amount` value. Promotion redemption validates code active state,
campaign active state, campaign date window, and max-redemption limits before
writing a redemption.

Wellbeing user-facing reads now expose only `user_and_admin` injury reports;
`admin_only` injuries remain visible and healable only through admin
application services. The admin wellbeing page now supports staff-created
injury reports and admin healing actions.

Feedback review targets are constrained to the documented taxonomy, with
legacy `private_coaching` normalized to `coaching_parameter`. The user review
page now captures the four planned structured questionnaire answers rather
than a single summary answer.

Finance, Wellbeing, Feedback, and Analytics public context APIs now route
through thin `Commands.*` and `Queries.*` modules before reaching their store
ports, restoring the Phase 8 CQRS layer shape without changing persistence
ownership. Touched API request contracts were tightened with concrete
OpenAPI schemas and request validation plugs, and generated OpenAPI/TypeScript
artifacts were regenerated.

Validation performed: API compiled successfully, Phase 8 migration applied
successfully against the compose Postgres instance on port 5434, OpenAPI JSON and
TypeScript schema were regenerated, focused Phase 8/8B backend tests passed, and
targeted frontend lint/typecheck passed for the new Phase 8 files. The existing
full backend suite still has unrelated pre-existing failures noted in the
implementation summaries.

Hardening pass on 2026-06-11 moved finance consistency checks into pure domain
policies and enforced them before persistence: payment/redemption links must
belong to the target membership, referral events cannot be self-referrals or
point at another user's membership, referral rewards require approved/applied
events and are unique per referral event, and membership lifecycle status is
derived from dates for active/expired/expiring semantics. The finance aggregate
read model was rebuilt to use the same active-membership date semantics. Admin
finance UI now exposes referral event/reward creation, promotion redemption
requires a selected code in the normal UI path, review/wellbeing mutation errors
are visible, analytics store adapter lookup is runtime-configurable, and bulk
notification read emits the same analytics event family as single read.
