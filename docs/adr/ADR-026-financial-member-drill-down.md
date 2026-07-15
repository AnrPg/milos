# ADR-026: Financial Member Drill-Down Contract
Date: 2026-06-13
Status: Accepted

## Context
Phase 8 requires the admin dashboard to drill down from financial summaries into
a single member profile that supports membership lifecycle decisions. The
existing Finance profile endpoint exposes source facts such as membership,
package subscriptions, invoices, payments, credits, and reversals, but those
facts still require the frontend to infer current state, urgency, and action
eligibility.

The drill-down backend plan defines Phase 1 as the Financial Member Drill-Down:
an admin-readable profile that distinguishes identity, current status, package
relationship, financial timeline, upcoming/outstanding items, operational
context, and available or blocked actions.

## Decision
Keep Finance as the source of truth for financial facts and extend the existing
admin member finance profile with a `drill_down` section that composes those
facts into operator-facing sections.

The existing profile fields remain available for compatibility. The
`drill_down` section adds interpreted status, urgency, timeline, and action
readiness without creating new persistence or moving accounting meaning outside
Finance.

## Rationale
Preserving the existing profile shape avoids breaking current admin finance
screens while giving the unified `/admin` dashboard a complete backend contract.
Composing from Finance public reads keeps the source-of-truth accounting facts
inside Finance and prevents controller or frontend business-rule drift.

This approach also keeps Phase 1 additive. It can be consumed by the frontend
when the admin workspace is ready, while existing member profile routes and
actions continue to operate.

## Alternatives Considered
Creating a separate parallel drill-down endpoint was rejected for Phase 1
because it would duplicate the profile read boundary and make frontend adoption
more complex.

Replacing the existing profile payload was rejected because existing finance
screens already consume raw fact lists.

Persisting a new drill-down read model was rejected because the surface can be
derived from current Finance facts and does not yet need independent caching or
projection lifecycle.

## Consequences
The admin member profile response now has two layers: source facts for detailed
finance workflows and a `drill_down` section for operator summary and action
readiness.

Frontend code should prefer `drill_down` for dashboard member drill-down UI and
fall back to source facts only for detailed tables or legacy finance screens.

Future Phase 2 coaching drill-down work should follow the same contract shape
where practical so `/admin` surfaces stay consistent.

## Implementation Notes
Implemented Phase 1 by adding a pure Finance domain composer,
`MilosTraining.Finance.Domain.MemberDrillDown`, and wiring the existing admin
member finance profile application service to include a `drill_down` section.

The response keeps the existing source-fact fields intact and adds:

- identity summary
- current status and urgency
- active package relationship
- chronological financial timeline
- outstanding/open items
- operational context
- action readiness with blocked-action reasons

Unmanaged users now receive a coherent drill-down empty state when the Identity
account exists but no Finance membership profile exists. Unknown user ids return
`not_found`.

The existing admin finance profile OpenAPI operation now declares the
`drill_down` section in the response schema while preserving additional
properties for compatibility with existing finance screens.

Validation performed:

- `DB_PORT=5434 MIX_BUILD_PATH=/tmp/milos_phase1_drilldown_build mix test test/milos_training/finance/domain/member_drill_down_test.exs test/milos_training_web/controllers/phase8_finance_controller_test.exs`
- `MIX_BUILD_PATH=/tmp/milos_phase1_drilldown_build mix milos.export_openapi ../web/src/api/generated/openapi.json`
- `npx openapi-typescript src/api/generated/openapi.json -o src/api/generated/schema.ts`

No new technical debt was deferred by this slice. Existing warnings from
calendar feed and search fallback code remain unrelated to the drill-down
implementation.

On 2026-06-14, the finance operations package-assignment controls were
corrected to consume the Finance package contract's `active` boolean rather
than filtering on a nonexistent `status` field. The member-table inline
assignment dropdown and referral-event membership setup now list every
package returned by Finance, with inactive packages explicitly labelled
instead of silently removing all options.

The same hardening pass made package assignment the supported onboarding
boundary for Identity users that do not yet have a Finance membership.
`AssignFinanceMemberPackage` now validates the Identity user and package,
creates a default `trial` membership when needed, and then assigns the
package. Referral-wizard onboarding records `signup_source: referral`;
member-table assignment defaults to `admin_created`. Inactive packages remain
visible for operator context but are disabled and rejected by a pure Finance
assignment policy.
