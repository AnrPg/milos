# ADR-088: Platform Tenant Access Management
Date: 2026-08-04
Status: Accepted

## Context
The SaaS owner needs a platform surface to invite people into a tenant with a
specific role and to adjust tenant account types after accounts exist. The tenant
model stores authorization on organization memberships, while global Identity users
remain authentication principals.

## Decision
Add platform-owner operations for tenant access management under
`/api/platform/organizations/:id/access`: list tenant memberships, issue a
role-scoped invitation, and update a membership role. The Organizations context owns
membership and invitation writes. An application service decorates memberships with
Identity public API data for display.

## Rationale
Putting the surface under `/platform` matches the SaaS owner's workflow and avoids
requiring tenant switching just to invite or classify users. Keeping role changes
tenant-scoped preserves the multi-tenancy model and avoids reviving global
`users.role` as the primary authorization source.

## Alternatives Considered
Using the existing tenant invitation endpoint directly from the UI was rejected
because it requires selecting a tenant context before the platform owner can perform
basic provisioning tasks.

Changing global Identity roles from the platform page was rejected because one
person can belong to multiple tenants with different roles.

## Consequences
Platform owners can change organization membership roles without changing the
global account role. Legacy admin profile role controls remain separate until the
remaining global-role UI is retired.

## Implementation Notes
Initial implementation adds the API endpoints, membership-role command, OpenAPI
contract regeneration, and an access panel in `/platform/organizations`.
