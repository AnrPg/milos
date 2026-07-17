# ADR-058: Tenant resolution and request context
Date: 2026-07-18
Status: Accepted

## Context
Registration must infer the organization without a user-facing directory, and every authenticated HTTP or WebSocket operation must resolve one unambiguous tenant before reaching business logic.

## Decision
Invitation links are authoritative during registration. After token validation, the server resolves the organization and intended role and may redirect to its verified subdomain. Ongoing tenant context is resolved from a verified organization hostname plus authenticated membership; tenant identifiers supplied in request bodies never grant access.

Phoenix plugs and socket connection code construct a transport-neutral `TenantContext` containing organization, account, membership, and request metadata. Controllers and channels pass this context to application services and public context APIs. Users with multiple memberships enter through the relevant organization host; the registration form never offers an organization picker.

## Rationale
Invitation inference provides a secure and low-friction first entry. Hostname plus membership validation makes bookmarked URLs and login behavior deterministic while preventing a forged body parameter from changing tenant authority.

## Alternatives Considered
An organization selector was rejected because it leaks the client directory and enables ambiguous registration. Email-domain inference was rejected as a primary mechanism because public and shared domains are not proof of affiliation. Session-only tenant state was rejected because stale tabs and cross-subdomain navigation can become ambiguous. Path-based slugs remain a local-development fallback but are not the production authority.

## Consequences
Wildcard DNS and TLS are required for production subdomains. Every interface adapter must reject missing or mismatched tenant context. Invitation endpoints must avoid logging raw tokens, and a future custom-domain flow must verify domain ownership before activation.

## Implementation Notes
To be completed after implementation.
