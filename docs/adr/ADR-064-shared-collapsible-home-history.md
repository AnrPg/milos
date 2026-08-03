# ADR-064: Shared collapsible home history
Date: 2026-07-18
Status: Accepted

## Context
Personal Records and WOD History are data-dense home-page sections. Members and athletes could not collapse them, and admins did not receive the same personal history surfaces even though the landing payload contains their own gamification and execution data.

## Decision
Use one client-side `HomeDisclosure` component for Personal Records and WOD History. Both sections default open, retain their existing actions and filters, and can be independently collapsed. Render both personal sections for every authenticated role, including admins.

## Rationale
A shared disclosure keeps accessibility, styling, and show/hide behavior consistent. Default-open preserves the existing information hierarchy while allowing users to reduce page length. Admin is also a training user, so role-specific administrative metrics do not preclude showing that account's own PRs and WOD history.

## Alternatives Considered
- Keep separate disclosure implementations: rejected because it duplicates state and accessibility behavior.
- Collapse by default: rejected because it would hide previously visible content on first load.
- Continue excluding admins: rejected because the requirement applies to all user types and the data is already scoped to the signed-in account.

## Consequences
The home page is longer for admins when both sections are open, but each can now be collapsed. PR actions and WOD grid/list controls remain available in their headers. Disclosure state is intentionally session-local and is not persisted.

## Implementation Notes
The shared component has a focused interaction test covering accessible expanded state and repeated reveal/hide behavior. Existing PR modals, WOD filters, execution detail navigation, and role-specific home content remain unchanged.
