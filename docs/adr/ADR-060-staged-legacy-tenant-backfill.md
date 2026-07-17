# ADR-060: Staged legacy-tenant backfill and enforcement rollout
Date: 2026-07-18
Status: Accepted

## Context
The running application contains unscoped production-shaped data across many bounded contexts. Adding non-null tenant columns and enabling RLS in one migration would either fail, require forbidden raw SQL mutations, or make partially migrated runtime paths inaccessible.

## Decision
Migrate in explicit expand/backfill/enforce/contract stages. First create organization primitives and a stable legacy organization. Add nullable `organization_id` columns context by context. Run idempotent application-owned backfill commands through Ecto changesets and public context APIs. Verify counts and foreign-key consistency before making ownership non-null, adding same-tenant constraints, and enabling forced RLS. Remove global-role and tenantless compatibility paths only after all entry points are tenant-aware.

Each stage is deployable, observable, and reversible without deleting tenant data. Dual-read or dual-write compatibility is narrowly time-boxed and recorded in the implementation plan.

## Rationale
An expand-and-contract migration lets the existing deployment remain usable while preserving the project's changeset-only mutation rule. Verification gates make missing ownership visible before database enforcement turns it into an outage.

## Alternatives Considered
A flag-day migration was rejected because the blast radius spans every context and infrastructure adapter. Raw SQL bulk updates were rejected by the architecture rules. Leaving nullable tenant ownership indefinitely was rejected because it creates an implicit global tenant and weakens isolation.

## Consequences
The refactor requires multiple migrations and temporary compatibility code. Backfill progress and unmapped-row counts become release gates. Until the enforce stage completes, the product must not provision independent external clients.

## Implementation Notes
To be completed after implementation.
