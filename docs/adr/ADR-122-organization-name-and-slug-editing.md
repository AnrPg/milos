# ADR-122: Organization Name and Slug Editing
Date: 2026-10-12
Status: Accepted

## Context
TD-045: the vendor sets an organization's canonical `name` and path `slug` at
provisioning time (ADR-083) and had no supported way to change either afterwards,
even though the `Organization` changeset casts both. "Edit settings" on
`/platform/organizations` only covered the separate `organization_settings` row.

The name is display-only. The slug is not: it is the organization's address under
ADR-058's single-origin routing (`/org/:slug/...` on the web, `/api/org/:slug/...`
on the API), it is returned as `canonical_path`, it is embedded in access-token
membership claims, in the web's remembered organization selection
(`localStorage`), in socket connection params, in stored push/notification deep
links (`organization_slug` in payloads, `AdminPath.admin_url/2`), and in whatever
bookmarks and shared links users already hold. A slug that simply changed in place
would break all of these at once, and - worse - a released slug could later be
provisioned for a *different* organization, so old bookmarks would silently open
another tenant's sign-in context.

## Decision
1. **Name.** The existing vendor endpoint `PATCH /api/platform/organizations/:id/name`
   (`Application.RenameOrganization`, audit event `organization_renamed`) and the
   name field in the "Edit settings" dialog are the supported name-editing path.
   A name change never moves the slug.

2. **Slug rename** is a separate, vendor-only, confirmed operation:
   `GET /api/platform/organizations/:id/slug-impact` returns the impact summary
   (active member count, pending invitation count, previous slugs, whether an
   open purge blocks the rename); `PATCH /api/platform/organizations/:id/slug`
   with `{slug, confirmation}` renames. The vendor must retype the **current**
   slug. The new slug must satisfy `OrganizationPolicy.valid_slug?/1` as typed
   (trimmed and lower-cased, never re-slugified) and be free across both
   canonical slugs and retired aliases. The organization row update, the alias
   bookkeeping and an `organization_slug_renamed` provisioning event commit in
   one transaction inside `RepoContext.run(%{user_id: vendor})`.

3. **Retired slugs become aliases** in a new root table `organization_slug_aliases`
   (`organization_id` FK `ON DELETE CASCADE`, unique `slug`, `retired_at`,
   `retired_by_user_id`). They are **reserved indefinitely** - for as long as the
   organization exists - so no other organization can provision or rename into
   them. Renaming back to one of the organization's own aliases is allowed: that
   alias row is removed and the then-current slug becomes an alias. Aliases are
   deleted with the organization (cascade, permanent delete, and the ADR-117
   purge), which is the only point at which a retired slug becomes claimable.

4. **API resolution by a retired slug is transparent.** `ResolveTenantContext`
   falls back to the alias table, so the request (HTTP, socket connect, channel
   revalidation, `x-organization-slug` header lookups, stale token claims) is
   served normally and the `TenantContext` carries the canonical organization.
   HTTP responses resolved through an alias carry
   `x-organization-canonical-slug: <current>`; the web client uses it to replace
   a remembered retired selection. Authorization is unchanged: the alias only
   identifies the organization, membership is still checked against the database.

5. **Web `/org/<retired>/...` is a 308.** The Next.js proxy asks the API's
   unauthenticated `GET /api/organization-slug-aliases/:slug` (rate-limited, 404
   for canonical *and* unknown slugs alike) and redirects to
   `/org/<canonical>/<rest of path>?<same query>` with status 308. Lookups are
   best-effort with a short per-instance cache; on any failure the request
   proceeds unchanged, and decision 4 still keeps tenant API calls working.

6. **Open purges block slug renames** (`slug_rename_blocked_by_purge`), because
   the ADR-117 approval compares the typed confirmation with the slug snapshotted
   on the purge record.

## Rationale
Resolving aliases transparently in the API (rather than returning a structured
"moved" error) keeps every non-browser consumer working without client changes:
socket reconnects, channel join revalidation (`TenantChannelContext.refresh/2`
resolves the slug captured at connect time), background calendar feeds and the
`localStorage` selection all continue to work the moment the rename commits, and
nothing has to be released in lock-step. The response header gives clients a
cheap signal to converge on the new slug. The browser-facing redirect is still a
real 308 so bookmarks, shared links and old notification deep links land on the
canonical URL and the address bar is corrected.

Indefinite reservation is the only rule that guarantees an old link can never
resolve to a different tenant. Slugs are cheap (3-63 characters), renames are
rare vendor operations, and the reservation ends exactly when the organization -
and therefore the meaning of the old link - ends.

Requiring the current slug retyped mirrors ADR-117's purge approval and makes the
vendor read the address that is about to change; the impact summary makes the
blast radius explicit before commit.

## Alternatives Considered
- **Structured redirect error from the API** (e.g. `409 organization_slug_moved`
  with the new slug): rejected; every API client (web fetch layer, sockets,
  channel revalidation) would need retry logic and a rename would cause a wave of
  failed requests.
- **Alias expiry** (e.g. 90 days): rejected for the initial version because an
  expired alias could be claimed by another organization, turning old bookmarks
  and stored deep links into links to a different tenant. An explicit vendor
  "release alias" action can be added later if real demand appears.
- **Re-pointing stored notification payloads to the new slug**: rejected;
  notifications live in another bounded context and the redirect already makes
  them work, so a cross-context rewrite would add risk without benefit.
- **A SECURITY DEFINER SQL function for the unauthenticated lookup**: rejected
  because its RLS behaviour depends on the function owner's role attributes,
  which differ between environments. Separate SELECT-only permissive policies keyed
  on an explicit `app.slug_alias_lookup` session flag (the same pattern as
  `app.invitation_redemption`) are additive and testable under `RLSCase`.
- **Next.js `redirects()` in `next.config.ts`**: rejected; they are static at build
  time and cannot know about runtime renames.

## Consequences
- `organization_slug_aliases` is a platform-administered root table: classified in
  `Tenancy.Audit`'s `@platform_administered_tables`, forced RLS mirroring
  `organization_domains`, and declared in Organizations' `TenantDataPolicy` so the
  ADR-117 export carries it and `TenantTableCoverageTest` stays green.
- Provisioning (`provision_organization`, `create_organization`) now also rejects a
  slug that is a retired alias (`slug: has already been taken`). Organization
  slugs and aliases share one namespace across two tables, so both provisioning and
  renames serialize on a transaction-scoped advisory lock per slug.
- One new unauthenticated endpoint exists. It reveals only "retired slug X is now
  Y" to someone who already knows X; slugs are identifiers, not secrets (ADR-058),
  and canonical/unknown slugs return the same 404 so it cannot be used to probe for
  organizations.
- The web proxy performs a network call for `/org/<slug>` GET/HEAD requests whose
  answer is not cached; it fails open and times out after 1.5 s.
- Access-token membership claims keep the old slug until the next refresh; this is
  harmless because claims are never authorization (ADR-058) and old slugs resolve.

## Implementation Notes
- Migration `20261012110000_create_organization_slug_aliases` creates the table,
  `organization_slug_aliases_tenant_policy` (vendor / member / invitation carve-out,
  same `WITH CHECK` shape as the F-16 root tables), and two SELECT-only lookup
  policies (`organization_slug_aliases_lookup_policy`,
  `organizations_slug_alias_lookup_policy`). Existing policies are not redefined.
- Domain: `Organizations.Domain.SlugRenamePolicy` (pure: `requested_slug/1`,
  `verify_confirmation/2`, `plan/4` over a claim of `nil | {:organization, id} |
  {:alias, id}`). Command `RenameOrganizationSlug`, queries `GetSlugRenameImpact`
  and `ResolveSlugAlias`; application services `RenameOrganizationSlug`,
  `GetOrganizationSlugRenameImpact`, `ResolveOrganizationSlugAlias`. All root-table
  access runs inside `RepoContext.run/2` (vendor user scope, or the new
  `%{slug_alias_lookup: true}` scope).
- `EctoOrganizationStore.rename_organization_slug/5` locks the organization row,
  verifies the typed confirmation against the locked current slug, refuses while a
  purge is open, takes advisory locks on both slugs (sorted, to avoid deadlocks),
  derives the claim, and then deletes a reclaimed own alias, updates the slug,
  inserts the retired alias and the audit event.
- Error codes: `invalid_slug` (422), `slug_unchanged` (422),
  `slug_confirmation_mismatch` (422), `slug_taken` (409),
  `slug_rename_blocked_by_purge` (409).
- `ResolveTenantContext` plug sets `x-organization-canonical-slug`; the CORS plug
  exposes it. `apiRequest` replaces a remembered selection that equals the retired
  slug. Realtime topics are keyed by organization id (`TenantTopics`), so no topic
  changes were needed; a socket connected before the rename keeps joining channels
  (covered by `UserSocketTenantContextTest`).
- Web: `src/lib/organization-slug-alias.ts` (lookup, cache, URL rewrite) used by
  `src/proxy.ts`; `OrganizationSlugRenameDialog` on `/platform/organizations`
  ("Change slug") with en/el copy in `src/i18n/platform-organization-slug.ts`.
- Not changed: invitation links (`/set-admin?token=`, `/register?token=`) and the
  calendar feed (`/api/calendar/feed.ics?token=`) are token-based and never carried
  the slug. Stored notification deep links keep the old slug and rely on the 308.
- Deferred: a vendor action to release (delete) an alias; listing previous slugs on
  the organization list itself (they are shown in the rename dialog); a realtime
  broadcast telling already-open tabs to rewrite their URL (they keep working via
  transparent resolution and pick up the new slug on the next navigation).
