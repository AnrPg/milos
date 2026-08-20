# ADR-095: Align Account Role With Membership
Date: 2026-08-20
Status: Accepted

## Context
Tenant invitations create an `organization_memberships` row with the invited
tenant role, but invited admin accounts were still persisted as global
`users.role = member`. The membership was correct, yet the issued session and
role-based shell could still present member-only surfaces until the membership
query resolved, which made a first tenant admin look like a plain member.

## Decision
Invited accounts must align their global `users.role` to the highest active
tenant membership surface role: owner, admin, and coach map to `admin`, athlete
maps to `athlete`, and member maps to `member`.

## Rationale
Tenant membership remains the authorization source for tenant actions, but the
global account role is still used by session payloads and role-specific web
surfaces. Keeping the two aligned prevents freshly invited admins from receiving
member navigation, messages, or landing behavior.

## Alternatives Considered
Keeping invited admins as global members was rejected because it produces an
incorrect first-run experience and stale JWT/user state.

Using only frontend membership detection was rejected because it leaves backend
session semantics inconsistent and depends on a second request after signup.

## Consequences
Registration now performs a role alignment step after the self-register-safe
account creation. Existing non-vendor users are reconciled by migration from
their active memberships. Vendor accounts are not promoted by tenant
memberships so the provider console keeps its platform identity.

## Implementation Notes
Registration still creates the account through the self-registration path first,
so public signup cannot directly request an admin role. After the invitation is
redeemed successfully, the application service aligns the account role before
issuing tokens.

A data migration backfills missing tenant settings rows and reconciles existing
non-vendor accounts from active memberships so live invited admins no longer
keep stale `member` session semantics.

The web root guard now resolves the legacy `/admin` redirect through the
selected tenant membership, preserving `/org/:slug/admin` as the admin landing
surface.
