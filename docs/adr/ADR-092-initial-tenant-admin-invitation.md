# ADR-092: Initial Tenant Admin Invitation
Date: 2026-08-19
Status: Accepted

## Context
Platform provisioning originally described the copy-once bootstrap invitation as an
initial owner invitation. In practice, client onboarding should create the first
tenant operator as an admin, while the platform vendor keeps installation-level
control outside tenant membership semantics.

The registration page also made local validation failures look like a broken
invitation link because the submit button could remain disabled with no actionable
feedback.

## Decision
Provisioning issues the first organization invitation with the tenant `admin` role.
The existing response field remains `initial_owner_invitation` for compatibility,
but its `role` value is `admin`. Pending-registration detection treats unredeemed
initial admin invitations as awaiting setup.

The admin registration page keeps the button unavailable only while the invitation
is missing or fields are empty. Backend-compatible password rules are shown inline
and enforced on click with visible feedback.

## Rationale
Tenant `admin` is the role the client needs to manage the gym without implying
platform ownership or a separate tenant owner authority. Preserving the response
field avoids a breaking frontend/API rename during the urgent onboarding fix.

## Alternatives Considered
Keeping the first invitation as `owner` was rejected because it contradicts the
desired client role. Renaming every `initial_owner_*` field immediately was rejected
because it would broaden a registration bugfix into a larger contract migration.

## Consequences
Some internal names and copy still carry the historical "owner" wording until a
follow-up contract cleanup. Authorization remains tenant-membership based; the
global Identity role for invited admins remains `member`.

## Implementation Notes
Provisioning now creates an admin-role invitation, lists organizations as pending
when an unredeemed owner or admin bootstrap invitation exists, and updates platform
copy/types/tests around initial admin setup. The registration form no longer leaves
fully filled forms inert when only password validation is failing.
