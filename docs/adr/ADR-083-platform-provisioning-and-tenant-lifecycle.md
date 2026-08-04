# ADR-083: Platform provisioning and tenant lifecycle
Date: 2026-08-03
Status: Accepted

## Context
Independent organizations require controlled creation, an initial owner, operational
settings, and reversible lifecycle controls. Tenant membership roles cannot safely
authorize installation-wide provisioning, and hard deletion would make recovery and
audit reconciliation unsafe.

## Decision
Use a separate `platform_owners` authority for installation-wide provisioning. A
platform owner provisions an organization, its settings, one hashed initial-owner
invitation, and an audit event in one database transaction. The clear invitation
token is returned exactly once.

Organizations move between `active`, `suspended`, and `archived`. Suspended and
archived organizations cannot resolve a runtime `TenantContext`. The initial product
does not hard-delete tenants; deletion requires an approved export, retention review,
and a dedicated destructive operation outside the web surface.

## Rationale
Separating platform authority from tenant membership prevents a gym owner from
provisioning or operating unrelated clients. Reversible lifecycle states support
incident response, billing holds, and offboarding without destroying records. An
atomic provisioning transaction prevents partially created organizations or leaked
untracked invitations.

## Alternatives Considered
Treating a tenant `owner` as a platform operator was rejected because it crosses the
tenant boundary. Self-service organization creation was rejected for the initial
commercial rollout because isolation gates and commercial review must complete first.
Immediate hard deletion was rejected because backups, shared personal resources, and
audit retention require an explicit reviewed workflow.

## Consequences
An existing account must be granted platform authority through an operational Mix
task before the provisioning surface can be used. Initial owner tokens must be copied
at creation time and cannot be recovered. Archived data remains in storage and
backups until a future approved deletion workflow is implemented.

## Implementation Notes
T7 adds platform-owner resolution, transactional provisioning events, lifecycle and
settings commands, OpenAPI-described HTTP endpoints, and the authenticated
`/platform/organizations` operations page. `mix milos.platform.grant_owner NICKNAME`
is idempotent. The operational runbook documents runtime-role bootstrap, backup,
tenant export, restore drills, archiving, and deletion review. Automated invitation
delivery remains deferred under TD-034.
