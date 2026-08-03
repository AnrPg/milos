# ADR-085: Tenant-scoped coaching projections
Date: 2026-08-04
Status: Accepted

## Context
Coaching aggregates and athlete drill-downs previously combined global athlete
accounts, personal workout executions, and coaching messages without a tenant
boundary. This would let an organization infer personal activity that was never
performed through its programming.

## Decision
Coaching is a tenant-owned projection. Its athlete population is active
`organization_memberships` with role `athlete`. Aggregate completion metrics and
athlete drill-down execution history include only `workout_executions` whose
`organization_id` equals the active tenant. Coaching notes include only messages
whose `organization_id` equals that tenant.

## Rationale
This preserves personal training history as user-owned while allowing a gym to
coach work it prescribed or otherwise recorded under its own organization. A
database query cannot cross organization boundaries merely because the same user
belongs to more than one gym.

## Alternatives Considered
Counting every execution by a currently active member was rejected because it
would expose self-selected or another gym's history. Assigning historical
executions to the athlete's current organization was rejected because membership
can change and would rewrite the meaning of past activity.

## Consequences
Tenant programming must set execution provenance before it contributes to
coaching. A coach may read a provenance-scoped execution only through a tenant
authorized Coaching path; direct personal execution endpoints remain owner
scoped. The aggregate materialized view is partitioned by `organization_id` and
the refresh job requires an explicit organization scope.

## Implementation Notes
Implemented on 2026-08-04. `coaching_aggregates` is recreated with one row per
active organization athlete population and a unique `(organization_id,
period_start)` index. The Coaching adapter requires transaction-local tenant
context and applies an explicit `organization_id` predicate. The canonical
drill-down route validates the target's active athlete membership before loading
tenant assignments, provenance-scoped executions, and tenant coaching messages.

The execution RLS policy retains owner-only writes and grants tenant reads only
for executions that carry matching organization provenance. The HTTP route is
admin-only, so this policy supports the explicitly authorized coaching read model
without broadening personal execution write access.
