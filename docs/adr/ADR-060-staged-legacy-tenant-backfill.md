# ADR-060: Staged legacy-tenant backfill and enforcement rollout
Date: 2026-07-18
Status: Accepted
Amended: 2026-07-19

## Context
The running application contains unscoped production-shaped data across many bounded contexts. Adding non-null tenant columns and enabling RLS in one migration would either fail, require forbidden raw SQL mutations, or make partially migrated runtime paths inaccessible.

## Decision
Migrate in explicit expand/backfill/enforce/contract stages. First create organization primitives and a stable legacy organization. Add nullable `organization_id` columns context by context. Run idempotent application-owned backfill commands through Ecto changesets and public context APIs. Verify counts and foreign-key consistency before making ownership non-null, adding same-tenant constraints, and enabling forced RLS. Remove global-role and tenantless compatibility paths only after all entry points are tenant-aware.

Each stage is deployable, observable, and reversible without deleting tenant data. Dual-read or dual-write compatibility is narrowly time-boxed and recorded in the implementation plan.

The ownership inventory must classify rows before backfill. Tenant-owned rows receive
an organization. Global personal rows retain user ownership and receive user-scoped
RLS; they must not be assigned to the legacy organization merely because they predate
multi-tenancy. Existing self-authored Wellbeing reports and Pantheon PRs are handled
as personal facts, while organization-authored safety records are tenant-owned.

## Rationale
An expand-and-contract migration lets the existing deployment remain usable while preserving the project's changeset-only mutation rule. Verification gates make missing ownership visible before database enforcement turns it into an outage.

## Alternatives Considered
A flag-day migration was rejected because the blast radius spans every context and infrastructure adapter. Raw SQL bulk updates were rejected by the architecture rules. Leaving nullable tenant ownership indefinitely was rejected because it creates an implicit global tenant and weakens isolation.

## Consequences
The refactor requires multiple migrations and temporary compatibility code. Backfill progress and unmapped-row counts become release gates. Until the enforce stage completes, the product must not provision independent external clients.

Backfill reports must separately reconcile tenant-owned, global-personal, and
platform-global counts. A zero unmapped-row count is required for each class before
its RLS policy is forced.

## Implementation Notes
The baseline ownership inventory is recorded in
`docs/architecture/tenant-ownership-inventory.md`. The stable
`legacy-milos-training` organization can be created idempotently through the public
Organizations API, release function, or `mix milos.organizations.ensure_legacy`.
No legacy domain rows were assigned yet; those changes remain in the ordered T4
expand/backfill/enforce loops.

Scheduling completed its enforce step on 2026-08-03 with same-tenant constraints,
explicit predicates, transaction-local context, a two-tenant isolation suite, and
forced RLS. `mix milos.tenancy.audit` classifies every other tenant table as
transitional and deliberately prevents a false full-enforcement declaration.

Workouts completed the same enforcement slice on 2026-08-04 for workout library
and assignment tables. Tenant-scoped public store calls run inside
`RepoContext`, the adapter adds explicit organization predicates to its primary
workout reads, and a two-organization integration test covers draft isolation.
The migration deliberately does not enable RLS for the remaining T4 contexts:
their HTTP and job entry points must first propagate an explicit tenant or user
context. This preserves the staged rollout rather than silently routing them to
the legacy organization.

Execution completed its global-personal ownership slice on 2026-08-04.
`workout_executions` and `execution_progress_operations` use transaction-local
user context, explicit owner predicates, forced user-scoped RLS, and a forged
`user_id` isolation test. The user supplied by authenticated context always wins
over an identifier in a request payload.

Feedback completed its tenant-owned ownership slice on 2026-08-04. Review reads,
updates, aggregates, and answer loading run under explicit tenant context with
organization predicates and forced RLS across questionnaires, reviews, and
answers. Canonical `/api/org/:organization_slug/me/reviews` and admin paths
require membership before reaching the context; legacy routes remain temporary
compatibility paths until T6 contract cleanup.

Coaching completed its tenant projection slice on 2026-08-04. The aggregate is
partitioned by organization, uses active athlete memberships as its population,
and counts only matching execution provenance and tenant coaching messages. The
canonical admin drill-down rejects athletes without an active membership in the
selected organization and exposes no personal execution history without that
provenance.
