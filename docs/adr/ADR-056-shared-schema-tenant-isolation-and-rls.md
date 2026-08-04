# ADR-056: Shared-schema tenant isolation with PostgreSQL RLS
Date: 2026-07-18
Status: Accepted
Amended: 2026-07-19

## Context
Client data must be isolated while preserving the operational simplicity of one self-hosted PostgreSQL service. Application-only `organization_id` filters are vulnerable to omissions and do not protect against an incorrectly composed query.

## Decision
Use shared PostgreSQL tables with mandatory `organization_id` ownership for tenant data. Enforce isolation twice: explicit tenant predicates in context adapters and PostgreSQL Row-Level Security using a transaction-local tenant setting. Production application connections use a non-owner role; tenant tables use `FORCE ROW LEVEL SECURITY`. Same-tenant composite foreign keys prevent references across organizations.

Explicitly classified global personal tables use mandatory `owner_user_id` ownership,
explicit owner/grant predicates, and user-scoped RLS instead of a synthetic
`organization_id`. Optional organization provenance is metadata and never grants
access. Runtime transactions establish the applicable user context, tenant context,
or both; absence of either context is denied unless the resource is explicitly
classified as platform-global.

RLS is enabled only after existing records are backfilled and every runtime entry point establishes tenant context. Migrations and platform maintenance use a separate privileged role with auditable, narrowly scoped operations.

## Rationale
Shared-schema tenancy keeps migrations, backups, and resource usage manageable for many small clients. RLS supplies a database-enforced backstop without the connection-pool and deployment cost of one database per organization.

## Alternatives Considered
Schema-per-tenant was rejected because search paths and fleet-wide migrations become fragile. Database-per-tenant was rejected for the initial product because connection pools, backups, and upgrades scale operationally with every client. Application filtering without RLS was rejected because a single missing predicate could expose another client.

## Consequences
All request, job, and test transactions must set the context required by the owned
resource. Database ownership and runtime credentials must be separated before RLS
enforcement. Platform-wide reports require explicitly privileged paths, and isolation
tests must prove that forged organization, user, source, or grant identifiers cannot
cross a policy boundary.

## Implementation Notes
The 2026-08-03 foundation establishes explicit ownership classification and requires
database-validated `TenantContext` or `UserContext` at new boundaries. RLS is not yet
enabled: ADR-060 requires T4 context-by-context backfill and zero-unmapped-row gates
before the T6 runtime-role enforcement step.

The first enforce loop landed for Scheduling on 2026-08-03. Runtime connections use
a non-owner, non-`BYPASSRLS` role; release migrations temporarily use the migration
owner URL. Scheduling store calls establish transaction-local organization/user
settings, all six Scheduling tables have forced RLS, and the audit reports zero
unmapped rows. Full enforcement remains blocked by the transitional T4 contexts and
the audit fails closed while any such table lacks forced RLS.
