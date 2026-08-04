# ADR-086: TrainingJournal Product Shell and Tenant Branding
Date: 2026-08-04
Status: Accepted

## Context
The application is moving from a single-client Milos Training installation to a
multi-tenant SaaS product operated by the platform owner. Milos is now one client
organization, while the provider product needs its own neutral name. At the same
time, each gym owner needs organization-specific branding in member, athlete, and
admin surfaces.

The current tenant backfill created `legacy-milos-training` as a transitional
organization for pre-tenancy records. That tenant identity can appear in the
organization selector, but it must not be treated as the provider product name.

## Decision
Use `TrainingJournal` as the provider product shell name. Organization settings own
tenant-facing branding such as display name, logo, primary color, default locale,
timezone, and invitation lifetime. Milos Training is represented as a normal tenant
organization, not as the global application brand.

Legacy Milos data may be promoted into a normal tenant by updating the existing
legacy organization, settings, memberships, and tenant-owned row provenance after
the tenancy audit is clean. The migration must preserve tenant isolation and must
not assign global personal records to the tenant.

## Rationale
A neutral product shell prevents one client's name from leaking into other clients'
accounts, browser metadata, notifications, exports, and operational dashboards.
Keeping branding on organization settings matches the existing `Organizations`
bounded context and avoids duplicating tenant identity inside feature contexts.

Promoting the legacy tenant is safer than creating a second Milos organization and
moving every record, because existing foreign keys and RLS ownership predicates
already point at the legacy tenant.

## Alternatives Considered
Keeping Milos Training as the product brand was rejected because Milos is now only
one customer of the platform.

Hiding all organization identity from the top navigation was rejected because users
who belong to multiple gyms need an explicit tenant context.

Creating a brand-new Milos tenant and copying legacy data was rejected as the
default because it increases the chance of orphaned records, duplicate memberships,
broken object keys, and inconsistent audit history.

## Consequences
Product-level strings, PWA metadata, API descriptions, push defaults, exports, and
calendar metadata need a controlled rename from Milos Training to TrainingJournal.
Tenant-facing surfaces should prefer organization `brand_name`, then organization
name, and only use TrainingJournal where no tenant context exists.

The platform provisioning UI currently stores `brand_logo_url`; a first-class logo
upload flow must be added before gym owners can upload files directly from the UI.
Uploaded logo objects must be tenant-scoped and validated through the storage
adapter.

Legacy Milos Training can be renamed or promoted, but the operator must audit
tenant-owned rows, memberships, object keys, invitation settings, cached/search
projections, and user-facing links before removing the legacy label.

## Implementation Notes
This ADR records the product/tenant branding decision and the intended migration
direction. No runtime code was changed in this documentation pass.
