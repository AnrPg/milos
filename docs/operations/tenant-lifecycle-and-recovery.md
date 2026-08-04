# Tenant Lifecycle and Recovery Runbook

## Scope

This runbook covers platform-owner bootstrap, organization provisioning, lifecycle
changes, database and object-store backups, tenant export, restore drills, and the
current no-hard-delete policy.

## Runtime database role

New PostgreSQL volumes run `ops/postgres/init/010-milos-runtime-role.sh` automatically.
The API connects as the non-owner `milos_runtime` role; releases and migrations use
the migration-owner URL.

For an existing volume, set `DB_RUNTIME_PASSWORD` and run:

```bash
./scripts/provision_postgres_runtime_role.sh
```

Restart the API after the role exists. Verify that the runtime role is not a
superuser and does not have `BYPASSRLS`:

```sql
SELECT rolname, rolsuper, rolbypassrls
FROM pg_roles
WHERE rolname = 'milos_runtime';
```

## Platform-owner bootstrap

Create or identify a normal authenticated account, then grant installation-wide
platform authority:

```bash
cd apps/api
mix milos.platform.grant_owner NICKNAME
```

Platform authority is separate from organization membership. Grant it only to the
installation operator.

## Provision an organization

1. Sign in with the platform-owner account.
2. Open `/platform/organizations`.
3. Enter name, optional slug, timezone, locale, invitation lifetime, and branding.
4. Provision the organization.
5. Copy the initial owner invitation immediately. The clear token is returned once
   and is never stored.
6. Deliver the token through an approved private channel. Automated email or OTP
   delivery is not implemented.
7. Confirm the owner can register and open the canonical `/org/:slug` path.

Do not provision an independent production tenant until the T4-T6 enforcement audit
passes for every shipped context.

## Lifecycle operations

- `active`: tenant context can be resolved and members can use organization routes.
- `suspended`: tenant access is denied, but data is retained and the state is
  reversible.
- `archived`: tenant access is denied and the organization is treated as offboarded;
  data remains retained for audit and recovery.

Every lifecycle and settings change creates an `organization_provisioning_events`
record identifying the platform owner.

## Backup

Back up PostgreSQL and both MinIO buckets in the same maintenance window. Record the
database snapshot time and object version/copy time together.

```bash
docker compose exec -T postgres \
  pg_dump --format=custom --no-owner --file=/tmp/milos.dump "$DB_NAME"
docker cp "$(docker compose ps -q postgres):/tmp/milos.dump" ./backups/milos.dump
```

Mirror the invoice/document and avatar buckets with an S3-compatible client. Encrypt
backup media, restrict access to platform operators, and apply the installation's
retention policy.

## Tenant export

Tenant export is an operator-reviewed process until a dedicated export service lands.

1. Suspend the organization to prevent writes.
2. Record its UUID, slug, export timestamp, requester, and legal/retention basis.
3. Export rows from each tenant-owned table using `organization_id` predicates.
4. Export objects under `organizations/<organization_id>/`.
5. Export organization settings, domains, memberships, invitation metadata without
   token digests, and provisioning audit events.
6. Do not include global-personal rows unless the owner has explicitly authorized
   export or an accepted grant makes them part of the tenant record.
7. Validate row counts and object checksums before delivering the encrypted archive.

## Restore drill

Run restore drills in an isolated environment, never over production.

1. Restore PostgreSQL with the migration-owner account.
2. Restore MinIO buckets and preserve object keys.
3. Run all migrations.
4. Re-provision the runtime database role for an existing restored volume.
5. Run `mix milos.tenancy.audit` and the architecture gate.
6. Verify two organizations cannot read each other's HTTP, socket, job, cache,
   search, storage, analytics, or export data.
7. Verify archived and suspended organizations cannot resolve tenant context.
8. Record duration, failures, and remediation work in the operations log.

## Legacy object migration

TD-039 is closed by an operator-controlled migration task for pre-tenancy object
keys. New uploads already use canonical prefixes, but older rows can still point at
`invoices/...` document keys or public avatar URLs containing
`/milos-avatars/avatars/<user_id>/...`.

Run the dry-run first:

```bash
mix milos.storage.migrate_legacy_objects
```

Apply during a maintenance window after PostgreSQL and both MinIO buckets have been
backed up:

```bash
mix milos.storage.migrate_legacy_objects --apply
```

The task copies each legacy object to `organizations/<organization_id>/...` or
`users/<user_id>/avatars/...`, reads the destination back, verifies a SHA-256 byte
checksum, and only then updates the persisted invoice `file_key` or user
`avatar_url`. Add `--delete-legacy` only after a successful dry-run/apply cycle if
the old object keys should be removed after verification.

## Deletion policy

The application does not expose hard tenant deletion. Archive is the normal
offboarding state. A future hard-delete request requires all of the following:

- approved tenant export and checksum verification;
- retention and legal review;
- inventory of tenant-owned rows, shared/global-personal references, Oban jobs,
  cache keys, search documents, and object prefixes;
- a dry-run count reviewed by a second operator;
- a dedicated changeset-backed deletion command and recovery plan;
- explicit human approval immediately before execution.

Never delete an organization directly with SQL or cascade through shared personal
resources.
