# ADR-059: Tenant propagation beyond PostgreSQL
Date: 2026-07-18
Status: Accepted

## Context
Database row scoping alone does not isolate realtime topics, background jobs, caches, search documents, object storage, exports, notifications, or observability. A global key or topic can leak or corrupt data even when PostgreSQL is correct.

## Decision
Treat tenant ownership as mandatory metadata at every system boundary. Oban arguments and uniqueness keys, PubSub and Channel topics, Redis keys, Meilisearch filters or indexes, MinIO object prefixes, signed exports, notification delivery, analytics projections, logs, and traces include `organization_id`. Consumers establish `TenantContext` before calling a bounded context.

Platform-global resources must be explicitly classified and documented; absence of `organization_id` is never interpreted as shared tenant data. Architecture and contract tests will reject known unscoped patterns as each adapter is migrated.

## Rationale
Isolation failures frequently occur outside the primary database. A uniform tenant key and explicit global-resource classification make reviews and automated checks tractable across asynchronous and cached infrastructure.

## Alternatives Considered
Scoping only PostgreSQL was rejected as incomplete. One cache, index, bucket, or queue per tenant was rejected as the default because infrastructure count would grow with clients, though dedicated resources may remain an enterprise option. Prefixing without membership validation was rejected because namespacing alone is not authorization.

## Consequences
Existing jobs and events require versioned payload migrations. Cache invalidation, search rebuilds, and object migration need tenant-aware tooling. Observability may retain organization identifiers only under privacy-aware access and retention policies.

## Implementation Notes
To be completed after implementation.
