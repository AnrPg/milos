# ADR-111: Tenant Logo Upload
Date: 2026-10-12
Status: Accepted

## Context
ADR-086 made organization settings the owner of tenant branding but left the logo
as `organization_settings.brand_logo_url`, a free-text URL that only a vendor could
set from the platform console. Gym owners could not upload a logo themselves, the
URL pointed at arbitrary third-party hosts the CSP did not allow, and nothing
validated what the URL served. TD-040 asked for a first-class upload with
tenant-scoped storage, validation, preview, audit events and consumption across
branded surfaces.

The avatar flow (presigned PUT straight to MinIO, then a finalize call that probes
the stored bytes) and the ADR-107 tenant object inventory
(`organizations/<organization_id>/...`, prefix-pinned list/delete) already provide
the building blocks.

## Decision
Add a logo upload flow that mirrors avatars and is pinned to the tenant prefix:

1. **Request** (`POST .../branding/logo/upload-url`): a tenant owner/admin (own
   organization) or a vendor (any organization, platform console) asks for a
   presigned PUT. The server allocates
   `organizations/<organization_id>/branding/logo/<uuid>.<ext>` after checking the
   declared type (PNG, JPEG, WebP) and size (1 byte to 2 MiB).
2. **Upload**: the browser PUTs the file directly to object storage with the
   required `content-type` header.
3. **Finalize** (`PUT .../branding/logo` with `logo_key`): the server checks that
   the key is one the policy would issue for *this* organization (exact prefix,
   UUID file name, allowed extension, no traversal), probes the first 16 bytes and
   the total size, and requires the magic bytes to identify PNG/JPEG/WebP *and*
   match the key's extension. A rejected object is deleted. On success the
   settings row stores `brand_logo_object_key` and the derived public URL in
   `brand_logo_url`, an audit event is written in the same transaction, and the
   superseded logo object is deleted (only if it is an owned key of the same
   organization).
4. **Remove** (`DELETE .../branding/logo`): clears both columns (also a legacy
   external URL), writes the audit event and deletes the uploaded object.

Logos live in the public media (avatar) bucket under the logical storage bucket
`:branding`; the bucket policy now allows anonymous `GetObject` on
`users/*/avatars/*` and `organizations/*/branding/logo/*` only.

SVG is rejected at request time and by the magic-byte probe. It can carry script,
and there is no safe sanitizer in the dependency set; adding one would need a new
dependency.

## Rationale
- **Same shape as avatars**: no file bytes go through Phoenix, the
  `MINIO_PUBLIC_ENDPOINT` media origin is already in `img-src`/`connect-src` (TD-032),
  and presigned PUTs from the browser are already proven against MinIO CORS.
- **The bytes decide, not the client**: the declared content type is only used to
  sign the PUT. Finalize trusts the probed bytes plus the server-chosen extension,
  so a renamed SVG or HTML payload can never become the logo.
- **Prefix ownership is checked before storage is touched**: an org A admin who
  submits a key under org B's prefix gets `brand_logo_key_forbidden` before any
  probe or delete, so they can neither adopt nor destroy org B's object.
- **`brand_logo_url` stays the read model**: memberships, the platform console and
  the shell already read it, so storing the derived URL keeps every consumer and
  the existing API contract working. `brand_logo_object_key` is the source of
  truth for cleanup and for "uploaded vs external".
- **Public bucket**: logos render in the shell header for every member and must be
  cacheable; presigned GET URLs would expire inside cached membership payloads.

## Alternatives Considered
- **Private documents bucket + presigned GET**: rejected. URLs expire after 15
  minutes but are cached in memberships and query caches, and a redirect endpoint
  would add an authenticated round trip for every header render.
- **Proxying uploads through the API**: rejected. It duplicates request-size limits
  and puts image bytes through Phoenix for no gain over the avatar pattern.
- **Accepting SVG with sanitization**: rejected for now. A regex "sanitizer" is not
  safe and there is no vetted library in the dependency set. Raster formats cover
  the need.
- **A new tenant audit table**: rejected. `organization_provisioning_events` is the
  existing organization audit log. A narrow additive INSERT policy lets tenant
  admins write their own logo events, which is cheaper than a second log with its
  own retention and export rules.

## Consequences
- New tenant-admin routes: `GET /api/org/:slug/admin/branding`,
  `POST /api/org/:slug/admin/branding/logo/upload-url`,
  `PUT|DELETE /api/org/:slug/admin/branding/logo`. New vendor routes:
  `POST /api/platform/organizations/:id/branding/logo/upload-url`,
  `PUT|DELETE /api/platform/organizations/:id/branding/logo`. Platform settings
  responses gain `brand_logo_uploaded`.
- While an uploaded logo is set, the generic settings update rejects a change to
  `brand_logo_url` ("is managed by the uploaded logo; remove the upload first").
  The provisioning form keeps the optional external URL field for backward
  compatibility.
- Logo audit events (`organization_logo_uploaded`, `organization_logo_replaced`,
  `organization_logo_removed`) record the acting account in the historical
  `vendor_user_id` column, with `metadata.actor_scope` set to `tenant` or `vendor`.
  The metadata holds only ids, object keys, a boolean for "previous logo was an
  external URL", and the change timestamp.
- Uploaded logos are tenant objects for ADR-107. `TenantObjectStorage.inventory/2`
  lists them with the tenant's documents, and `purge_tenant_objects/2` deletes them.
- The stored URL is derived at finalize time from `MINIO_PUBLIC_ENDPOINT`. If the
  public endpoint changes, existing logo URLs must be re-derived (re-upload, or a
  one-off backfill from `brand_logo_object_key`), the same as avatars.

## Implementation Notes
- **Layers**: `Organizations.Domain.BrandLogoPolicy` is pure and holds actor
  authorization, request validation, key allocation/ownership, magic-byte
  detection, the event classification and metadata, and superseded-key selection.
  `Organizations.Commands.ReplaceOrganizationLogo` and
  `Queries.GetOrganizationBranding` run under `RepoContext` (the tenant context for
  owners/admins, a user-scoped session for vendors).
  `EctoOrganizationStore.replace_organization_logo/4` locks the settings row
  (`FOR UPDATE`), applies `OrganizationSetting.logo_changeset/2` and inserts the
  event in one transaction. The application services are
  `RequestOrganizationLogoUpload`, `FinalizeOrganizationLogo`,
  `RemoveOrganizationLogo` and `GetOrganizationBranding`, with the shared steps in
  `Application.OrganizationLogo`.
- **Storage port**: `TenantObjectStore` gained `presigned_upload/3`,
  `probe_object/3` (ranged GET; 416 on an empty object maps to size 0) and
  `public_object_url/2`. `MinioStorage` implements them, and
  `TestSupport.MemoryObjectStore` implements them for tests.
  `TenantObjectStorage.branding_upload/probe_branding_object/delete_branding_objects`
  refuse any key outside `organizations/<organization_id>/`. Unlike avatars, the
  logo probe has no public-URL fallback: a failed private probe returns
  `brand_logo_storage_unavailable` (503).
- **Migration** `20261012110000_add_organization_brand_logo_object_key` adds the
  nullable column and the permissive INSERT policy
  `organization_provisioning_events_tenant_logo_insert`. The policy allows only the
  three logo events, only with `vendor_user_id = app.user_id`, and only for an
  organization the acting user administers. Reads stay vendor-only. The RLS tests
  (`OrganizationLogoTest`, "under real row level security") run finalize/remove
  as the non-superuser runtime role and show a cross-organization insert is
  refused.
- **Idempotency**: finalizing the current key again is a no-op (no event, no
  delete). Removing when there is no logo is a no-op.
- **Realtime**: after a change, tenant staff receive a `user:sync` with scope
  `organization_branding`. The web bridge then invalidates `organization-memberships`
  and `["admin","branding"]`. Members pick up the new logo on their next
  memberships refetch (60 s stale time).
- **Web**: `src/lib/tenant-logo-upload.ts` mirrors the client-side policy and drives
  request, PUT and finalize. `components/branding/TenantLogoUploader` provides
  preview (blob: URL, already allowed by `img-src`), upload, replace and remove. It
  is used in a new "Branding" section of tenant admin settings and replaces the
  logo URL text field in the platform settings dialog. That dialog no longer sends
  `brand_logo_url`/`brand_logo_uploaded` back through the generic settings PATCH.
  The shell header (`TopNav`) now shows the selected tenant's logo next to its
  brand name, in addition to the organization selector. All copy goes through the
  `Ui` catalog in all 12 locales, including API error codes in `presentation.ts`.
- **Branded surfaces not changed**: the login page has no tenant context
  (ADR-086: TrainingJournal shell before tenant resolution), and no email template
  reads `brand_logo_url`, so neither renders a logo. Both are follow-ups if
  per-tenant login pages or branded emails are introduced.
- **Deferred**: orphaned objects from uploads that are never finalized stay inside
  the tenant prefix until the ADR-107 purge. A periodic sweep of
  `organizations/*/branding/logo/` keys that no settings row references would
  reclaim them sooner. Server-side image re-encoding (to strip metadata or
  normalize dimensions) is not done.
