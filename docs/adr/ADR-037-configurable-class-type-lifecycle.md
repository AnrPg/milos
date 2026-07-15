# ADR-037: Configurable Class Type Lifecycle
Date: 2026-07-15
Status: Accepted

## Context
Scheduled classes currently copy a fixed `training_type` enum from their linked
workout. The product instead needs an admin-managed class taxonomy that is
independent from the workout training taxonomy. Class type removal must not
erase historical meaning, and future scheduled classes cannot retain a type
that is no longer selectable.

The application is still unreleased and its databases contain no production
data, so preserving legacy schedule request parameters or a transitional
`scheduled_classes.training_type` column would add complexity without protecting
real consumers.

## Decision
Scheduling owns a normalized `class_types` catalog. Every scheduled class has a
required `class_type_id`; workout `training_type` remains owned by Workouts and
is never used to infer a class type.

Removing a class type archives it rather than deleting it. Past and current
scheduled classes keep their original class type. If future classes reference
the type, the archive command requires an active replacement and atomically
reassigns those future classes before archiving the original type.

Schedule reads and filters use class type identifiers. The legacy schedule
`training_type` field and query parameter are removed outright.

## Rationale
A normalized catalog makes configured values the source of truth and lets
labels change without rewriting scheduled classes. Soft archival preserves
historicity and analytics. Requiring a replacement for future classes prevents
an archived option from remaining in active operations.

Keeping workout training type separate reflects the two concepts: a workout's
training discipline and a scheduled class's administrator-selected offering.

## Alternatives Considered
Keeping a denormalized compatibility string was rejected because there are no
released clients or populated databases to protect and it would create two
sources of truth.

Hard deletion was rejected because historical classes and analytics must retain
their original classification.

Inferring class type from workout training type was rejected because admins
must explicitly classify every scheduled class and the taxonomies evolve
independently.

## Consequences
The schedule API has an intentional breaking contract change. Class type CRUD,
archive mapping, and active-type listing are Scheduling operations exposed
through Application Services and contract-first controllers.

Archival must lock the source type and affected future scheduled classes inside
one transaction. A replacement must be active, distinct from the source, and
present whenever future references exist.

## Implementation Notes
To be completed after implementation.
