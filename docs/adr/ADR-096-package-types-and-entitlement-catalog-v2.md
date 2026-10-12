# ADR-096: Package Types and Entitlement Catalog v2
Date: 2026-10-12
Status: Accepted

## Context
ADR-040 made package benefits an explicit, enforced contract, but the package
form exposed the enforcement internals directly: delivery channels and
capabilities had to be ticked in matching pairs, allowances were raw limit and
period inputs, and a descriptive `family` field (`unlimited`, `limited-visits`,
`personal-programming`, `hybrid`) mixed quantity with service type without any
behavioural meaning. Non-technical gym administrators could not tell what a
package would actually sell. The editor also blocked
`receive_coaching_touchpoints`, which programming delivery and coach check-ins
require, so no package authored in the UI could receive coach-assigned work
under enforcement.

The product also lacked the commercial models gyms sell besides recurring
memberships: class packs, drop-ins, trials, personal-training packs, add-ons,
shared memberships, and corporate memberships. The full product redesign is
described in
`docs/superpowers/specs/2026-10-12-package-types-and-entitlements-redesign.md`
and is delivered in three phases (A: foundations and core commercial types,
B: booking rules, perks and facility, C: new services and payer models).
This ADR records the Phase A decisions.

## Decision
Finance owns two independent package axes:

1. **Package type** — how a package is sold: `membership`, `class_pack`,
   `drop_in`, `trial`, `pt_pack`, `add_on`, `shared`, `corporate`. It is a
   required column on `membership_packages`. All eight types are modelled in
   the domain; a type is sellable only once its phase is implemented
   (Phase A: `membership`, `class_pack`, `drop_in`, `trial`).
2. **Entitlement catalog v2** — what a package includes, stored as
   `params.entitlement_version = 2` with a flat, closed map of catalog field
   keys to values (`params.fields`). Every package stores a value for every
   catalog field.

Each type has a complete **preset** and a set of **type-enforced (locked)
fields** whose values define the type (for example a drop-in is one-off and
holds exactly one visit). Presets, locks, field specifications and phase
availability are pure Finance domain data, exposed read-only through an admin
presets endpoint so the web client never duplicates them.

Writes go through a pure `PackageContract` normaliser that merges the type
preset with the submitted fields, rejects changes to locked fields
(`package_type_invariant_violated`), rejects non-default values on fields
whose phase is not implemented (`entitlement_not_available`), validates each
field against its specification and the type's cross-field rules, and returns
the complete field map.

The v2 field map compiles into the existing ADR-040 plan (channels,
capabilities, allowances), so the enforcement policy, ledger and reservation
sagas remain the single enforcement path. Channels and capabilities become an
internal compilation detail and are no longer authored.

Phase A additionally decides:
- Group-class scope by class type and per-class-type visit limits are
  enforced. A booking whose class type has its own limit consumes that limit
  instead of the general visit limit; a class type outside the scope is denied
  with `finance_class_type_not_included`.
- One-off types derive `ends_on` from the package validity on assignment and
  are never renewable; recurring memberships may disable automatic renewal.
- Class packs and drop-ins stack: several active one-off subscriptions may
  coexist with a recurring membership. A reservation tries recurring
  subscriptions first and then one-off subscriptions by earliest expiry,
  choosing the first that authorizes the request.
- Trials enforce once-per-person eligibility (locked) and optional
  new-members-only eligibility at assignment.
- `family` is no longer authored. It is written as the package type so the
  existing reporting columns and materialized views group by package type.
  Legacy family values on packages, subscription snapshots and invoice-line
  snapshots are relabelled to `membership`, because every legacy package is a
  recurring membership and ADR-040 already guaranteed the value carried no
  authorization meaning.
- Package codes are generated from the package name when omitted, with Greek
  transliteration (ELOT 743) and a numeric suffix on collision, and are
  immutable once created.
- Finance settings gain `package_modules`, the services the gym offers. The
  package wizard shows only types and services whose module is enabled.

## Rationale
Separating "how it is sold" from "what it includes" removes the
contradictions of `family` and gives presets a natural key. A flat field
catalog lets the backend validate, snapshot, compare with presets and report
"changed from preset" uniformly, and lets the web client render advanced
settings generically from field specifications. Compiling into the ADR-040
plan avoids a second enforcement engine and keeps immutable subscription
snapshots meaningful.

Locking type-defining values preserves the meaning of the type for reporting,
renewal and eligibility rules while every other value remains editable.
Rejecting non-default values for unimplemented fields keeps the stored
contract truthful: nothing is sold that the product cannot deliver.

## Alternatives Considered
Keeping channel and capability authoring with a friendlier skin was rejected
because the pair requirement is an engineering detail that cannot be made
self-explanatory.

Storing only the differences from a preset was rejected because later preset
changes would silently alter sold contracts.

Inferring type from billing period or limits was rejected for the same reason
ADR-040 rejected inferring benefits from names.

Creating a separate column per catalog field was rejected: the catalog grows
by phase and the contract is already snapshotted as a document.

Renaming the `family` columns was rejected for Phase A because several
materialized views and search documents depend on them; relabelling values
achieves the reporting change without view rewrites.

## Consequences
The package create/update contract changes (closed OpenAPI schema with
`package_type` and `fields`); the generated web client is regenerated.
Existing v1 packages remain readable and enforceable; they are presented to
the editor as an equivalent v2 field map and become v2 on the next save.

Booking reservations carry the class type. Effective entitlement read models
list every active subscription because stacked one-off packages can coexist.

Phase B and C fields exist in the catalog with defaults but cannot be changed
until their phase implements enforcement and product surfaces.

## Implementation Notes
To be completed when Phase A is finished.
