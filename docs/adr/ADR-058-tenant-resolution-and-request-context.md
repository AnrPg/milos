# ADR-058: Tenant resolution and request context
Date: 2026-07-18
Status: Accepted
Amended: 2026-07-19

## Context
Organization joining must infer the organization without a public directory, and
every tenant-scoped HTTP or WebSocket operation must resolve one unambiguous tenant
before reaching business logic. Personal operations must remain usable without a
tenant.

## Decision
Invitation links are authoritative when joining an organization. After token validation, the server resolves the organization and intended role. Independent personal registration remains available without an invitation or organization membership.

The product uses one browser origin and one deployment. Personal routes such as
`/today` and `/journal` are user-scoped. Organization routes use
`/org/:organization_slug/...`; in-app navigation and a membership selector generate
these paths, so users do not type endpoints. The path identifies the requested
context but never grants access.

Phoenix plugs and socket connection code resolve the path slug and authenticated
active membership into a transport-neutral `TenantContext` containing organization,
account, membership, and request metadata. Controllers and channels pass this context
to application services and public context APIs. Organization identifiers supplied
in bodies, headers, cookies, or token claims are never authorization sources.

## Rationale
Invitation inference provides secure, low-friction organization entry. Explicit
path context plus membership validation keeps bookmarks, refreshes, and multiple tabs
deterministic without changing browser origin or relying on hidden selected-tenant
session state.

## Alternatives Considered
A public organization directory or registration-time picker was rejected because it
leaks clients and enables ambiguous registration. The authenticated membership
selector lists only the current user's memberships. Email-domain inference was
rejected because public and shared domains are not proof of affiliation. Session-only
tenant state was rejected because stale tabs become ambiguous. Subdomain authority
was rejected because the product requires one browser origin and seamless personal
and organization navigation.

## Consequences
Every tenant interface adapter must reject missing or mismatched path/membership
context. Personal adapters must reject attempts to smuggle tenant authority into a
user-scoped request. Invitation endpoints must avoid logging raw tokens. Custom
domains and wildcard tenant DNS are outside the initial design; adding them requires
a new ADR that preserves canonical path identity and authorization semantics.

## Implementation Notes
HTTP organization paths and optional socket organization parameters are resolved
through the Organizations public API and validated against current database
membership state. Access-token membership claims support client navigation but are
never accepted as authorization. The web membership selector generates explicit
`/org/:slug` paths; full tenant operations remain gated on T4 ownership migration.
