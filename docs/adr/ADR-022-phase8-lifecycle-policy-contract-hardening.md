# ADR-022: Phase 8 Lifecycle Policy Contract Hardening
Date: 2026-06-13
Status: Accepted

## Context
Phase 8 added wellbeing, finance invoices, and feedback review workflows across
multiple bounded contexts. Follow-up review found that several lifecycle rules
were enforced only incidentally by controller input shape, store filters, or
calculation fallbacks. That allowed public self-reported injuries to become
hidden from their reporter, invoice line discounts to exceed the line subtotal,
and reviews to be submitted before a workout execution or class attendance had
actually happened.

## Decision
Lifecycle eligibility and accounting invariants stay in pure domain policy
modules, while application services compose the required context APIs and
controllers expose strict request contracts on risky Phase 8 commands.

## Rationale
The design requires hexagonal layering and bounded contexts. A controller-only
fix would leave alternate application or context entry points unsafe, while
moving cross-context reads into a context store would violate ownership
boundaries. Domain policy modules keep rules explicit and testable; application
services remain the orchestration layer for cross-context checks.

## Alternatives Considered
Keeping the current permissive API contracts was rejected because downstream
changeset validation is not enough for commands with business-critical meaning.
Duplicating checks in Ecto changesets only was rejected because review
eligibility depends on other bounded contexts. Adding new database constraints
for invoice line economics was considered, but a domain invariant plus schema
changeset guard is sufficient for the current non-destructive fix and preserves
existing migration history.

## Consequences
Public wellbeing report commands cannot create admin-only reports; admin
wellbeing commands retain admin-only visibility. User healing checks can find
the user's own injury by owner id even when the report is not visible in the
member list. Manual invoices now reject lines where discount exceeds subtotal.
Review submission now requires completed workout executions and attended class
records. API clients will receive 422 or 409 style errors instead of silently
persisting invalid lifecycle state.

## Implementation Notes
Implemented with focused domain policies and application orchestration:

- `Wellbeing.Domain.InjuryPolicy` forces public self-report params to
  `user_and_admin` visibility and strips protected lifecycle fields before the
  wellbeing context write.
- User injury healing now resolves ownership by `user_id` through a wellbeing
  read port instead of relying on the member-visible injury list.
- `Finance.Domain.InvoiceLifecycle.line_total/3` now returns an explicit
  `{:ok, total}` or domain error, and invoice/invoice-line changesets guard the
  same discount-not-above-subtotal invariant.
- `Feedback.Domain.ReviewEligibility` centralizes completed execution and
  attended class checks. `SubmitReview` composes Execution, Scheduling,
  Analytics, Workouts, and Finance public APIs to enforce eligibility.
- Public wellbeing create/heal and admin manual invoice creation now use strict
  OpenAPI request bodies with generated TypeScript refreshed.

No follow-up work was deferred for these findings.
