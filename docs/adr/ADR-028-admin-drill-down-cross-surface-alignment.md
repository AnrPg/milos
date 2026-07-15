# ADR-028: Admin Drill-Down Cross-Surface Alignment
Date: 2026-06-13
Status: Accepted

## Context
Phase 8 now has two backend-supported admin drill-down reads: Financial Member
Drill-Down and Coaching Athlete Drill-Down. Each surface was delivered in its
own slice, so Phase 3 must confirm that they behave like one admin workspace
rather than unrelated profile payloads.

The frontend should not need to invent shared meanings for current state,
attention signals, action availability, or error handling.

## Decision
Align both drill-down surfaces around the same product-contract conventions:

- identity sections identify the subject by `user_id`, `nickname`, and `role`
- current-state sections expose `state`, `reason`, and `urgency`
- attention lists use `type`, `severity`, `reason`, and `title`
- actions use `key`, `available`, and `reason`
- admin read endpoints declare explicit OpenAPI drill-down response sections and
  shared not-found/forbidden failure shapes

The two surfaces may keep domain-specific section names where the product
meaning differs, such as `current_status` for finance and `recent_activity` for
coaching.

## Rationale
Keeping a small shared vocabulary gives the admin frontend a stable integration
contract while preserving domain ownership. Finance owns membership lifecycle
meaning; Coaching owns athlete participation meaning. The alignment layer is the
contract shape, not a new persistence model or a new admin context.

## Alternatives Considered
Forcing both surfaces into identical section names was rejected because finance
and coaching answer different operational questions.

Leaving the OpenAPI schemas as loose objects was rejected because that would
make frontend integration rely on backend implementation details instead of the
published API contract.

Adding a separate aggregate `/admin/drill-down` endpoint was rejected because
the existing entry points already match the product workflows.

## Consequences
Future drill-down surfaces should reuse the same state, attention, and action
shape unless a new product meaning requires an ADR.

The generated TypeScript schema becomes the frontend contract source for these
sections; generated files must continue to be regenerated rather than edited by
hand.

## Implementation Notes
Implemented Phase 3 by adding a shared interface-layer schema module for the
admin drill-down OpenAPI contracts and tightening both finance and coaching
response schemas around identity, current state, attention items, and action
readiness.

Coaching `recent_activity` now includes the same `state`, `reason`, and
`urgency` vocabulary that finance exposes through `current_status`.

Added `docs/superpowers/specs/2026-06-13-phase8-drill-down-backend-contract.md`
as the cross-surface readiness contract for frontend integration.

Added focused alignment tests that lock shared domain payload semantics and
OpenAPI response detail for both drill-down surfaces.

Regenerated OpenAPI JSON and generated TypeScript schema after tightening the
contracts.

Validation performed:

- `DB_PORT=5434 MIX_BUILD_PATH=/tmp/milos_phase3_drilldown_build mix test test/milos_training/finance/domain/member_drill_down_test.exs test/milos_training/coaching/domain/athlete_drill_down_test.exs test/milos_training/admin_drill_down_alignment_test.exs test/milos_training_web/controllers/phase8_finance_controller_test.exs test/milos_training_web/controllers/admin_coaching_controller_test.exs test/milos_training_web/controllers/api_spec_controller_test.exs`

No new backend follow-up work was deferred by this alignment slice.
