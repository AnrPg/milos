# ADR-117: Reviewed Tenant Export and Purge
Date: 2026-10-12
Status: Accepted

## Context
ADR-083 deferred tenant destruction until an approved export, a retention review
and a dedicated destructive operation existed. ADR-087 then added a platform
"Delete permanently" action for mistaken or test organizations that relies on
database constraints as its safety boundary, and ADR-093 extended it to purge
tenant-only accounts. That action fails for real tenants: RESTRICT foreign keys
across bounded contexts (for example `scheduled_classes.master_workout_id`,
self-referencing finance and folder rows) stop the cascade, personal tables
whose RLS keys on `user_id` cannot be cleaned from a tenant session, finance
records carry statutory retention, and object storage (invoice documents,
avatars) is not cleaned at all. ADR-094's clean-slate job explicitly skipped
MinIO because there was no tenant-safe object inventory (TD-047). TD-041 asked
for a reviewed, staged workflow with export, retention review, object cleanup
and context-owned purge policies.

## Decision
Add a staged, vendor-operated purge workflow with a platform-level audit record:

1. **Request** (`POST /api/platform/organizations/:id/purge`). Organizations
   records an `organization_purges` row (`requested`) and suspends an active
   organization in the same transaction, so no tenant session or tenant job can
   write while the export is taken. An `ExportOrganizationTenantDataJob` is
   enqueued.
2. **Export** (Oban). Every bounded context exports its own rows through its
   public API (`export_tenant_data/2`) under a `TenantData.PurgeContext`. The
   result is `organizations/<id>/purge/<purge_id>/tenant-export.zip` (one JSON
   file per context, secret-free account records, a stored-objects manifest and
   the retention review) plus `organizations/<id>/retained/<purge_id>/retention-archive.zip`
   holding only rows a policy retains. The purge record stores the object keys,
   size, SHA-256 and the retention review; status becomes `exported`.
3. **Retention review** (`GET .../purge`). Per context: record counts per
   resource, the disposition (`purge`, `retain`, `retain_anonymized`), retention
   years, deadline and basis, plus `identity` (tenant-only vs shared accounts)
   and `storage` (purgeable vs retained documents, avatars) entries, and a
   15-minute signed download link while the purge is `exported`/`approved`.
4. **Approval** (`POST .../purge/approve`). Only an `exported` purge can be
   approved, and only by retyping the organization slug. The record stores the
   approver and whether a second vendor approved (`second_vendor`) or the
   requester self-approved with the typed confirmation (`typed_confirmation`).
   Approved and running purges cannot be cancelled and pin the lifecycle;
   reactivating an organization with any open purge requires an explicit cancel,
   which also deletes that purge's export objects.
5. **Purge** (Oban, `ExecuteOrganizationPurgeJob`). In dependency order -
   Analytics, Notifications, Execution, Pantheon, Feedback, Wellbeing, Messaging,
   Gamification, Finance, Scheduling, Workouts - each context deletes its own
   rows via `purge_tenant_data/1`; then tenant-only accounts and their avatar
   objects (ADR-093 eligibility); then tenant documents except retained
   prefixes; finally the organization row is deleted (cascading Organizations'
   memberships, invitations, settings, domains and provisioning events) in the
   same transaction that marks the purge `completed`. Each finished step is
   written to `organization_purges.steps` before the next starts, so a retry or
   `POST .../purge/resume` skips finished steps; a completed purge is a no-op.
6. **Status** survives the tenant: `GET .../purge` and
   `GET /api/platform/organization-purges` read the platform record, which
   holds identifiers, the slug, counts, policies, object keys and timestamps
   only - no tenant PII.

Each bounded context owns its policy in a pure
`<Context>.Domain.TenantDataPolicy` (tables in delete order, disposition,
retention, columns to drop, retained object prefixes). Finance retains all its
tables for 10 years in the retention archive and keeps `invoices/` documents;
Analytics retains `analytics_events` for 2 years with `user_id`, `context_id`
and `metadata` dropped; every other context purges. A shared executor
(`TenantData.TableStore` + `Infrastructure.TenantData.EctoTableStore`) only
runs what a context's own policy declares, always inside `RepoContext.run/2`:
tenant tables under `%{organization_id, user_id: vendor}` and personal tables
whose RLS admits only the owner under one `%{organization_id, user_id: member}`
session per member.

Object storage gets a storage-owned inventory
(`Application.TenantObjectStorage` over a `TenantObjectStore` port implemented
by `MinioStorage`) that can only list or delete under
`organizations/<organization_id>/` and `users/<user_id>/`.

## Rationale
Context-declared policies keep table knowledge inside the owning context while
one audited executor provides consistent RLS scoping, idempotent deletes and
JSON export without a schema per table. Purging dependents first removes the
RESTRICT chains that made the ADR-087 delete fail, without changing any
foreign key. The platform purge record, deliberately without foreign keys,
gives a tamper-evident trail (export checksum, approver, per-step counts) that
outlives the tenant. Retaining finance in an archive object rather than in the
live database lets the organization row and its cascades disappear while still
meeting the retention obligation; archiving anonymized analytics keeps service
metrics without personal data. The typed slug plus approver recording satisfies
"second person or explicit typed confirmation" without blocking single-operator
installations.

## Alternatives Considered
- **Keep relying on ADR-087 cascades.** Rejected: RESTRICT chains and
  owner-only RLS make it fail or leave rows behind; no export or retention.
- **Each context implements its own Ecto purge/export adapter.** Rejected for
  now: ~11 near-identical adapters with the same RLS subtleties; the shared
  executor enforces the scoping once while each context still owns its table
  list and policy.
- **Retain finance rows in the live database under an archived organization.**
  Rejected: every tenant table cascades from `organizations`, so it would keep
  the tenant alive indefinitely and keep PII queryable by the runtime.
- **Mandatory second vendor.** Rejected: small installations have a single
  vendor; the approval mode is recorded instead.
- **Copy every stored object into the export.** Rejected: unbounded export
  size; the export carries a manifest, and objects stay downloadable until the
  purge runs.
- **Polling the status in the UI.** Rejected per the no-polling rule; the
  dialog refreshes on demand and after each action.

## Consequences
- New tenant tables must be added to their context's `TenantDataPolicy`;
  `TenantTableCoverageTest` fails when a table with `organization_id` is not
  declared by exactly one context.
- Finance's 10-year retention and Analytics' 2-year anonymized retention are
  product defaults that legal review must confirm per deployment jurisdiction.
- The full export contains tenant PII and lives in object storage until the
  purge (or a cancel) deletes it; only vendors can obtain the signed link.
- Retention archives and retained invoice documents are not yet expired
  automatically after their deadline.
- Exports are built in memory; very large tenants may need streaming.

## Implementation Notes
- Migration `20261012090000_create_organization_purges` is additive: one
  vendor-only RLS table (forced RLS, `milos_acting_user_is_vendor()` policy
  mirroring `organization_provisioning_events`), a partial unique index allowing
  one open purge per organization, and a status check constraint. The table is
  classified as platform-administered in `mix milos.tenancy.audit`.
- No new lifecycle status was added: `suspended` already blocks tenant
  contexts and jobs, and the purge record carries the pending-purge state.
  Archived organizations stay archived when a purge is requested.
- `Organizations.get_by_id/1` is not RepoContext-wrapped and returns `nil`
  under the runtime role; the workflow reads organizations through vendor-
  scoped queries only. `OrganizationPurgeRLSTest` runs the whole workflow under
  the non-superuser runtime role with `SET LOCAL ROLE` inside the sandbox
  transaction, which is the first test to exercise real application services
  (not raw SQL) under RLS; `RLSCase.ensure_runtime_role!/0` was extracted for it.
- The ExAws list parser needs SweetXml, which is not a dependency; MinIO list
  responses are parsed by a small regex parser and bulk deletes use
  `delete_multiple_objects` with the parser disabled. Tests use an in-memory
  `TenantObjectStore`.
- Jobs carry only `purge_id` and the acting vendor id, re-resolve the platform
  context (a revoked vendor cancels the job), are unique per purge while
  incomplete, and cancel instead of retrying when the purge has moved on.
- `DELETE /api/platform/organizations/:id` (ADR-087) is unchanged and remains
  the quick path for mistaken/test organizations.
- TD-047 is partially resolved: the storage-owned tenant/user object inventory
  now exists and is used by tenant purge, but ADR-094's clean-slate job is not
  wired to it.
- Deferred: automatic expiry of retention archives and retained invoice
  documents after `retained_until`; streaming exports for large tenants;
  removing Meilisearch documents and Redis keys for a purged tenant (they are
  derived caches rebuilt from the database, but stale entries may persist
  until the next rebuild); purging a shared account's personal rows that belong
  to the purged tenant but are keyed only by `user_id` without
  `organization_id` (e.g. `user_stats`).
