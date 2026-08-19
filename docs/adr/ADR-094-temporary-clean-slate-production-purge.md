# ADR-094: Temporary Clean Slate Production Purge
Date: 2026-08-19
Status: Accepted

## Context
The production SaaS-owner control panel previously left tenant-only Identity
accounts behind after a permanent organization deletion. Those stale accounts
kept global unique emails reserved and blocked client invitation registration.

The live environment may already contain stale tenant data from the old deletion
behavior. A one-time operator cleanup is needed after the fixed API is deployed.

## Decision
Add a temporary, release-callable clean slate purge that truncates Postgres
runtime tenant data, flushes the app Redis database, deletes known Meilisearch
indexes, deletes every non-owner Postgres user, and preserves only the SaaS
owner's user row, active vendor grant, migration history, and static reference
seed tables.

The purge refuses to run unless `MILOS_SAAS_OWNER_NICKNAME` identifies an active
vendor and `MILOS_CONFIRM_PROD_PURGE` equals the exact confirmation phrase.

## Rationale
A Kubernetes Job can run the existing production API image through the Phoenix
release entrypoint, so the cleanup uses the same runtime configuration and
database connectivity as migrations. Preserving schema migrations avoids
re-running historical migrations, while preserving reference seeds keeps the app
bootable immediately after the purge.

## Alternatives Considered
Using a database migration was rejected because this is operational data cleanup,
not schema history. Running ad hoc SQL from CI was rejected because it would
duplicate database configuration outside the app release and make safeguards
easier to bypass. Keeping old data and relying on future fixed deletes was
rejected because existing stale emails would remain blocked.

## Consequences
This cleanup is intentionally destructive and temporary. It must be removed from
GitOps after the operator confirms it has run successfully. Any future broad
production cleanup should add a new ADR and a new explicitly guarded release
entrypoint.

## Implementation Notes
The release entrypoint lives in `MilosTraining.Release` and delegates to
`MilosTraining.Infrastructure.Maintenance.CleanSlatePurge`. The GitOps manifest
is a one-shot Kubernetes Job using the same API image policy and secrets as the
API Deployment. MinIO object cleanup is intentionally not included because the
current object key layout does not expose a complete tenant-safe inventory for a
blanket delete from this recovery job.
