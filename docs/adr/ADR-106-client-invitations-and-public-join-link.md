# ADR-106: Client Invitations and Public Join Link
Date: 2026-10-12
Status: Accepted

## Context
Tenant admins had an API for one-time invitations (ADR-092) but no UI to
invite clients, list pending invitations or revoke them. Gyms also want a
reusable address to put on their website, social media or a QR code at
reception, which one-time invitations cannot serve.

## Decision
- Add `GET /api/org/:slug/invitations` (pending only, no tokens) and an invite
  surface on the dashboard, the users page and App configuration: personal
  one-time member/athlete links with optional email binding and 1–7 day
  validity, plus copy, native share, email and WhatsApp actions, and revoke.
- Add an opt-in public join link at `/join/<slug>`, stored as
  `organization_settings.settings["join_link"] = %{enabled, role}` and
  governed by the pure `JoinLinkPolicy`: disabled by default, client roles
  only (member or athlete), active organizations only, and never reactivates
  a suspended membership. Endpoints: `GET|PUT /api/org/:slug/join-link`
  (owner/admin), public `GET /api/auth/join/:slug`, authenticated
  `POST /api/memberships/join/:slug`.
- Joining aligns the global role of a client account that had no other
  organization (ADR-095); staff and multi-organization accounts keep theirs.

## Rationale
Invitations remain the default and the only path for staff. The join link is
a deliberate, revocable trade-off for client acquisition: it cannot grant
privileges beyond the client role the admin picked, and public lookups answer
the same `join_link_unavailable` for unknown, inactive and disabled slugs so
they cannot be used to enumerate tenants.

## Alternatives Considered
- Multi-use invitation tokens: would change the one-redemption invariant of
  ADR-092 and leak through every share of the token.
- Join requests with admin approval: safer but slower; can be added later as a
  join-link mode.

## Consequences
- Tenant-owned preferences now live in `organization_settings.settings` via
  `put_organization_settings_entry/3`, which does not write vendor
  provisioning events.
- Joining changes the account role, which invalidates the old access token; the
  web client rotates its session after joining.

## Implementation Notes
Implemented with controller tests for listing, revocation, disabled links,
staff-role rejection, idempotent joining and staff membership protection.
