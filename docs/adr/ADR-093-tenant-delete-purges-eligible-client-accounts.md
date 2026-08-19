# ADR-093: Tenant Delete Purges Eligible Client Accounts
Date: 2026-08-19
Status: Accepted

## Context
The platform "Delete permanently" action removed organization-owned records but
left global Identity users intact. That preserved unique emails for clients whose
only account existed for the deleted tenant, so recreating the client organization
and reusing the same invitation email failed with `email has already been taken`.

Global Identity users can also be personal, platform, or multi-tenant principals,
so deleting every user ever associated with an organization would be unsafe.

## Decision
Permanent organization deletion first finds eligible account purge candidates:
users who belong to the target organization, have no membership in another
organization, are not the platform vendor performing the delete, and are not
active vendors themselves. The Application service deletes those Identity accounts
through the Identity public API before deleting the organization through the
Organizations public API.

## Rationale
Deleting tenant-only accounts releases unique nicknames and emails for real
re-provisioning while preserving shared global identities and platform operators.
Keeping the user deletion in Identity and the candidate query in Organizations
preserves bounded-context ownership.

## Alternatives Considered
Leaving global users untouched was rejected because the UI action says permanent
delete and blocks immediate client re-registration. Deleting all users with a
membership in the organization was rejected because one person may belong to
multiple tenants. Deleting users directly from the Organizations infrastructure
adapter was rejected because it would cross bounded-context schema ownership.

## Consequences
Permanent deletion is destructive for tenant-only client accounts. Users with
memberships elsewhere keep their global account and email. If an eligible account
has restricted personal history that cannot be deleted by Identity, the operation
fails before the organization is removed.

## Implementation Notes
Implemented in the platform Application service: Organizations exposes only the
eligible purge-candidate ids, Identity owns account deletion, and Organizations
then deletes the tenant. The platform controller test covers email reuse after a
permanent delete and preservation of users who still belong to another tenant.
