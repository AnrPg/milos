# ADR-087: Platform Owner Tenant Entry and Permanent Organization Deletion
Date: 2026-08-04
Status: Accepted

## Context
Platform owners provision client organizations from `/platform`, then need a direct
way to open the newly provisioned tenant and verify or manage the tenant admin
surface. The previous provisioning flow created a copy-once owner invitation but
did not grant the provisioning account tenant-scoped owner membership, so opening
the organization could land on a shell without usable admin capabilities.

The platform operations page also needs a permanent-delete option for organizations
created by mistake. ADR-083 originally rejected hard deletion from the web surface,
but the current product requirement explicitly asks for it.

## Decision
Provisioning an organization grants the provisioning account an active tenant
`owner` membership in the same database transaction as organization, settings,
invitation, and audit-event creation. The `/platform` Open organization action sets
that tenant as the selected organization and enters the tenant admin dashboard.

Expose permanent organization deletion only to platform owners from `/platform`.
The delete operation removes platform provisioning audit rows for that organization,
then deletes the organization through the Organizations context. Existing database
foreign-key constraints remain the safety boundary for tenant data that cannot be
cascaded.

## Rationale
Tenant-scoped owner membership is the authoritative capability fact for admin UI and
API authorization. Granting it during provisioning avoids a second setup step and
keeps the account that created the tenant able to manage it immediately.

Keeping hard delete under platform-owner authorization and database constraints
matches the operational nature of the action while avoiding broad, hand-written
cross-context cleanup logic.

## Alternatives Considered
Keeping invitation-only tenant activation was rejected because it leaves the
provisioning account without the requested tenant admin capabilities.

Letting platform-owner authority bypass tenant membership was rejected because it
would weaken tenant-scoped authorization and blur global platform authority with
tenant roles.

Building a broad destructive cleanup service across every bounded context was
rejected for this pass because the request only requires the platform operation,
and existing ownership constraints should prevent accidental deletion of protected
data.

## Consequences
Platform owners who create organizations also appear as tenant owners in those
organizations. Future self-service organization registration can reuse the same
membership invariant.

Permanent deletion is intentionally narrower than archival: it can fail when
protected dependent data exists. Operators should archive tenants for ordinary
offboarding and reserve permanent deletion for mistaken or test organizations.

## Implementation Notes
The initial implementation grants owner membership during platform provisioning,
changes the platform Open action to enter `/admin` with the selected tenant slug,
hides self-service account surfaces for platform-owner accounts, and adds a
platform-owner delete endpoint plus confirmation flow.
