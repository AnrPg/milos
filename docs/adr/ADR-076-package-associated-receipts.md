# ADR-076: Package-associated receipts
Date: 2026-08-01
Status: Accepted

## Context
Receipt mode creates and settles an invoice in one Finance transaction, but the
receipt workflow currently always creates a generic manual-charge line. Admins
cannot identify which of a member's package subscriptions the received money is
for, even though Finance invoices, invoice lines, and payments already support
an optional `membership_package_subscription_id`.

## Decision
Receipt creation accepts an optional member package-subscription identifier.
When present, Finance validates that the subscription belongs to the receipt's
membership and records the association on the backing invoice, invoice line,
and payment. The line snapshots the package identity through the existing
package snapshot fields, and the receipt projection and exported document show
the human package name when it remains available.

The admin receipt form selects from the member's existing package subscriptions.
Creating a receipt does not assign a new package, change subscription lifecycle,
or rewrite a historical package snapshot.

## Rationale
Reusing the existing subscription foreign keys preserves the invoice/payment
accounting model established by ADR-017 and the one-step receipt policy from
ADR-073. It also applies the existing Finance ownership validation and keeps
historical receipts tied to the package contract that was actually assigned to
the member.

## Alternatives Considered
Adding `membership_package_id` directly to receipts was rejected because
receipts are projections rather than a separate table, and a catalog package
does not identify the member-specific contract that was sold.

Storing only a package name in receipt metadata was rejected because it would
be displayable but not relationally auditable.

Automatically assigning the selected package while issuing a receipt was
rejected because package assignment changes entitlement and subscription
lifecycle and must remain an explicit Finance command.

## Consequences
The receipt API contract gains one optional UUID. Existing clients and receipts
remain valid. A selected subscription from another membership is rejected by
the existing Finance membership-link policy. No database migration or new
dependency is required.

## Implementation Notes
Receipt creation now passes the optional subscription identifier through the
existing invoice builder. That builder performs the Finance-owned membership
link check, creates a `membership_package` invoice line with the existing code
and family snapshots, and persists the same subscription identifier on the paid
payment. The receipt projection returns the live package name when available
plus snapshot fallbacks, and the analytics event includes the subscription id.

The admin receipt form lists the member's package subscriptions, pre-fills the
selected subscription price and package purpose, keeps manual receipts
available when no package is selected, and includes the package label in the
private client-generated PDF. The OpenAPI request contract and generated
TypeScript artifacts were regenerated.

Verification completed with focused Finance/controller coverage, including
foreign-membership rejection; 104 frontend unit tests; lint; type-check; the
production build; localization; and the full backend precommit suite (498 tests,
formatter, Credo, and the architecture boundary gate). Live testing was skipped
at the user's direction. No technical debt was introduced or deferred by this
change.
