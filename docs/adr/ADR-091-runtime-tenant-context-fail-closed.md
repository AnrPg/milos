# ADR-091: Runtime Tenant Context Must Fail Closed
Date: 2026-08-08
Status: Accepted

## Context
The staged multi-tenant rollout introduced a stable legacy organization for
backfill and migration tooling. Several runtime paths still treated that
organization as a fallback when HTTP, WebSocket, application-service, cache, or
store calls omitted tenant context. That behavior hides integration defects and
can write tenant-owned data into the legacy organization instead of failing.

## Decision
Runtime tenant-owned operations must require an explicit validated tenant context
and return `{:error, :organization_context_required}` when it is missing. The
legacy organization remains available only through explicit operator migration
tooling. Tenant role checks and admin fanout use organization memberships, not the
global `users.role` field.

## Rationale
Failing closed makes missing tenant propagation visible at the layer that dropped
context, preserves PostgreSQL RLS as a backstop, and prevents legacy ownership from
masking unsafe writes or reads. Keeping legacy creation in operator tooling still
supports staged migration without making it a product behavior.

## Alternatives Considered
Keeping compatibility fallbacks was rejected because it keeps one-tenant behavior
alive inside the multi-tenant runtime. Automatically resolving a tenant from a
user's first membership was rejected because multi-membership accounts would become
ambiguous and stale tabs could act in the wrong organization.

## Consequences
Callers of tenant-owned contexts must thread `TenantContext` or an equivalent
system tenant context explicitly. Legacy routes and jobs that cannot supply one
must be migrated or fail visibly. Tests should assert the missing-context error so
future shortcuts do not silently reintroduce the fallback.

## Implementation Notes
Message delivery jobs resolve a system tenant context from tenant ownership keys
before dispatch. Runtime scheduling, assignment, execution, landing cache, realtime
broadcast, and admin/member search paths now require explicit tenant context or
fail with an ownership error. Workout assignment persistence stamps ownership from
the active repo context, and a forward migration removes the legacy organization
default from new assignment rows. Frontend tenant surfaces derive admin/member/
athlete behavior from the selected organization membership instead of global
account role.

The T4 foundation migration now uses expand/backfill/enforce without leaving a
legacy default, and the follow-up default-drop migration removes existing tenant
table defaults in already-migrated databases. The central Notifications fanout no
longer falls back to global admins; remaining direct application-level
`Identity.list_by_role(:admin)` call sites need event-specific tenant payload
threading before `users.role` can be fully demoted.
