# ADR-041: Package Retirement Reconciliation
Date: 2026-07-15
Status: Accepted

## Context
Membership package subscriptions snapshot the entitlement contract that was sold. Marking a
catalog package inactive prevents new assignments, but does not by itself reconcile users whose
current effective subscription still points at that package. The Finance UI also exposed the
one-time legacy entitlement backfill as a permanent operational surface, mixing rollout tooling
with routine package management.

## Decision
Package retirement is an explicit, atomic Finance command. When the package has effective
subscribers, the command requires an active replacement package for every affected membership
role, creates replacement subscription snapshots, cancels the retired effective subscriptions,
refreshes entitlement snapshots, and only then marks the catalog package inactive.

The regular Packages tab does not expose legacy rollout controls. The edit flow checks the current
member read model and opens a mandatory reconciliation dialog only when an active package is being
retired while it has effective subscribers. Inactive packages and promotion campaigns are grouped
in subtle, collapsed archive sections below their active lists.

## Rationale
An atomic Finance-owned command prevents partial browser-side reassignment and guarantees that a
package cannot become unavailable midway through reconciliation. Role-specific mappings preserve
the existing distinction between member and athlete products without importing Identity schemas
into Finance. Keeping inactive records visible in collapsed archives preserves auditability while
reducing routine visual noise.

## Alternatives Considered
Reassigning each user from the browser before patching the package was rejected because a failed
request could leave a partially migrated cohort. Reusing the legacy backfill was rejected because
that operation creates missing profiles and subscriptions; it does not retire an already effective
package. Silently leaving existing snapshots active was rejected because it does not satisfy the
administrator's explicit reconciliation intent.

## Consequences
Package deactivation uses a dedicated contract instead of the general package update endpoint.
Reactivation and ordinary metadata edits continue through the existing update endpoint. Historic
subscription rows remain intact, with the retired effective row moved to `cancelled` and a new
active snapshot created for the selected replacement.

## Implementation Notes
The Finance adapter now locks the source package and its effective subscription rows in one
transaction. It validates role-specific replacement packages, cancels each effective source
subscription through its changeset, creates a new immutable replacement snapshot, refreshes the
membership entitlement projection, and deactivates the source package last. The ordinary package
update command rejects occupied-package deactivation so callers cannot bypass reconciliation.

The Packages UI derives the affected cohort from the existing admin Finance member read model and
shows the mandatory replacement dialog only for occupied packages. The backend remains the source
of truth and repeats all safety validation atomically. The legacy rollout block was removed from
routine Finance navigation; inactive packages and promotions now live in collapsed archive groups.

No database migration or new dependency was required. Focused controller coverage verifies both
the update guard and member/athlete reassignment path. The generated OpenAPI JSON and TypeScript
schema include the retirement endpoint and its role-mapping request contract.
