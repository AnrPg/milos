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
Provisioning an organization creates the organization, settings, one-time initial
admin invitation, and audit event in one transaction, but does not grant the
platform owner tenant membership. The tenant admin is the account that redeems the
initial admin invitation.

Expose permanent organization deletion only to platform owners from `/platform`.
The delete operation removes platform provisioning audit rows for that organization,
then deletes the organization through the Organizations context. Existing database
foreign-key constraints remain the safety boundary for tenant data that cannot be
cascaded.

## Rationale
Tenant-scoped membership is the authoritative capability fact for admin UI and API
authorization. Keeping platform ownership separate from tenant membership prevents
the SaaS owner from appearing as a gym admin for every provisioned organization.

Keeping hard delete under platform-owner authorization and database constraints
matches the operational nature of the action while avoiding broad, hand-written
cross-context cleanup logic.

## Alternatives Considered
Granting the provisioning account tenant `owner` membership was rejected after live
testing because it made the SaaS owner appear inside every tenant's admin surface.

Letting platform-owner authority bypass tenant membership was rejected because it
would weaken tenant-scoped authorization and blur global platform authority with
tenant roles.

Building a broad destructive cleanup service across every bounded context was
rejected for this pass because the request only requires the platform operation,
and existing ownership constraints should prevent accidental deletion of protected
data.

## Consequences
Platform owners can provision and lifecycle-manage organizations from `/platform`,
but tenant admin surfaces belong to tenant members only.

Permanent deletion is intentionally narrower than archival: it can fail when
protected dependent data exists. Operators should archive tenants for ordinary
offboarding and reserve permanent deletion for mistaken or test organizations.

## Implementation Notes
The initial implementation granted owner membership during platform provisioning,
but the August 2026 hardening removed that coupling: platform provisioning now
issues an admin invitation only, and permanent deletion uses a tenant-scoped user
delete path for tenant-only invited admins so legacy global `users.role = :admin`
does not trip the SaaS-owner last-admin guard.

Migration `20260821090000_remove_auto_provisioned_vendor_memberships` removes only
the old auto-created vendor tenant memberships that can be identified by the
original provisioning audit event. This prevents the platform console from
prefetching tenant admin routes for organizations the vendor only supervises at
platform level.

Migration `20260821093000_delete_membershipless_non_vendor_accounts` cleans up
legacy orphan login accounts left behind by earlier failed tenant deletion flows.
It only targets accounts with no organization memberships and no active vendor
authority, and skips any row that still has protected foreign-key history.
