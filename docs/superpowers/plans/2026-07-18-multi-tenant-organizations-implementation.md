# Multi-tenant Organizations Implementation Plan

**Date:** 2026-07-18

**Status:** In progress
**Goal:** Convert Milos Training into a single-origin, shared-schema multi-tenant
product with membership-scoped roles, one-time invitations, path-resolved tenant
context, global personal resources, and defense-in-depth isolation.

## Governing decisions

- ADR-055: Organizations bounded context and membership-scoped identity.
- ADR-056: Shared schema with explicit predicates and PostgreSQL RLS.
- ADR-057: Opaque, hashed, expiring, one-time invitations.
- ADR-058: Invitation joining and single-origin path-resolved tenant context.
- ADR-059: Tenant propagation through all infrastructure.
- ADR-060: Expand/backfill/enforce/contract rollout.
- Journal-first cross-feature constraints:
  `docs/superpowers/specs/2026-07-19-journal-first-app-redesign.md`.

## Non-negotiable delivery rules

- Follow the four-layer architecture and bounded-context public APIs.
- Write migrations before schemas and OpenAPI contracts before controllers.
- Use failing tests before every non-trivial domain, application, query, and controller behavior.
- Never accept an organization or role from browser input as authorization.
- Never store or log raw invitation tokens.
- Every isolation test uses at least two organizations and forged foreign identifiers.
- Commit dependency-ordered, atomic slices; perform live tests before declaring a phase complete.

## Phase T0 — Decisions and inventory

- [x] Preserve the approved discussion verbatim.
- [x] Create the feature branch.
- [x] Write ADR-055 through ADR-060.
- [ ] Build a tenant-ownership inventory for every table, materialized view, job, cache key, topic, search document, and object path.
- [ ] Classify every resource as tenant-owned, global-personal, or platform-global.
- [ ] Record self-authored Wellbeing facts and Pantheon PRs as global-personal; record
      organization-authored safety facts as tenant-owned.
- [ ] Record the movement catalog as platform-global with tenant-scoped proposal and
      alias moderation.
- [ ] Add tenant migration status and deferred delivery automation to the debt ledger as needed.

## Phase T1 — Organization primitives

- [x] Migration: create `organizations`, `organization_memberships`, `registration_invitations`, `organization_domains`, and `organization_settings`.
- [x] Domain tests: slug normalization, membership roles, invitation expiry limits, and state transitions.
- [x] Schemas and changesets for each aggregate.
- [ ] Organization store port and Ecto adapter.
- [ ] Commands: create organization, add membership, issue/revoke invitation.
- [ ] Queries: organization by ID/slug/domain, memberships, invitation by digest.
- [ ] Public `Organizations` context API.
- [ ] Create the stable legacy organization through an idempotent release/backfill command.
- [ ] Verify migration, constraints, architecture gate, and focused tests.

## Phase T2 — Invitation redemption and tenant-aware registration

- [ ] Preserve open personal registration without creating a synthetic organization
      membership.
- [ ] Pure token generation/digest and invitation policy tests.
- [ ] Transactional invitation redemption port owned by Organizations.
- [ ] Cross-context application services for new-account and existing-account redemption.
- [ ] OpenAPI contracts for invitation inspection, member registration, and admin registration.
- [ ] Replace the shared `/set-admin` code with an organization-owner/admin invitation.
- [ ] Update `/register` and `/set-admin` to accept link or typed token and show non-editable organization confirmation.
- [ ] Rate-limit inspection and redemption without exposing whether arbitrary organizations exist.
- [ ] Prove one-time behavior under concurrent redemption.

## Phase T3 — Path, authorization, and realtime tenant context

- [ ] Add transport-neutral `TenantContext` and membership authorization policy.
- [ ] Resolve `/org/:organization_slug/...` in HTTP plugs and Phoenix socket
      connection, then validate active membership.
- [ ] Keep personal routes user-scoped and independent of tenant selection.
- [ ] Add an authenticated membership selector that generates organization paths;
      never rely on hidden selected-organization session state.
- [ ] Carry organization and membership claims in access tokens without treating claims as the source of truth.
- [ ] Replace global role plugs with membership-aware authorization.
- [ ] Scope Channels and PubSub topics by organization and user.
- [ ] Add cross-path, multi-tab, stale-membership, forged-claim, personal-route, and
      socket-isolation tests.

## Phase T4 — Context-by-context database ownership

For each bounded context, repeat the complete expand/backfill/enforce loop before moving to the next:

1. Identity tenant profile data.
2. Scheduling.
3. Workouts.
4. Execution.
5. Finance.
6. Messaging and Notifications.
7. Gamification and tenant-owned Pantheon projections; keep personal PR records
   user-owned.
8. Coaching, Analytics, Feedback, and Wellbeing, splitting self-authored personal
   facts from organization-authored safety facts.

Each loop includes:

- [ ] Nullable ownership migration and indexes.
- [ ] Idempotent changeset-backed legacy backfill.
- [ ] Tenant-owned public API and store port signatures require `TenantContext`;
      global-personal signatures require authenticated `UserContext`.
- [ ] Same-tenant foreign-key constraints.
- [ ] Non-null ownership migration.
- [ ] Explicit query predicates plus RLS policy.
- [ ] Two-tenant read/write isolation suite.
- [ ] For global-personal tables, use owner/grant predicates and user-scoped RLS
      instead of forcing `organization_id`.
- [ ] Preserve former-member read access only to the user's own actual result, never
      prescription, class, peer, or coach-private data.

## Phase T5 — Infrastructure isolation

- [ ] Oban payloads, uniqueness, and workers establish tenant context.
- [ ] Tenant-owned Redis keys and invalidation include organization ID;
      global-personal keys include owner user ID.
- [ ] Tenant-owned Meilisearch documents and filters include organization ID;
      rebuild indexes.
- [ ] Global-personal indexes use owner scope; the global movement catalog indexes
      only approved canonical terms and correctly scoped aliases.
- [ ] MinIO paths and signed URLs include organization prefixes; migrate objects.
- [ ] Calendar/CSV/document exports bind organization and membership.
- [ ] Notification delivery and push subscriptions cannot cross organizations.
- [ ] Logs/traces redact invitation tokens and classify organization labels safely.

## Phase T6 — RLS enforcement and contract cleanup

- [ ] Provision distinct migration-owner and runtime database roles.
- [ ] Set transaction-local organization context in runtime adapters.
- [ ] Set transaction-local user context for global-personal adapters.
- [ ] Enable and force RLS only after unmapped-row checks reach zero.
- [ ] Remove global-role authorization and tenantless fallbacks.
- [ ] Remove the fixed admin registration code.
- [ ] Add an architecture check for unscoped tenant-owned adapters.
- [ ] Perform a live two-organization penetration test across HTTP, sockets, jobs, cache, search, storage, analytics, and exports.

## Phase T7 — Commercial provisioning

- [ ] Platform-owner organization provisioning surface.
- [ ] Organization lifecycle: active, suspended, archived.
- [ ] Initial owner invitation and copy-once delivery.
- [ ] Organization branding, locale, timezone, and configurable invitation lifetimes.
- [ ] Single-origin organization path routing and canonical deep links.
- [ ] Backup/export/restore runbook and tenant deletion policy.
- [ ] Keep automated email/OTP delivery deferred under TD-034 until provider work begins.

## Completion gates

- All tests, architecture checks, contract generation, lint, localization, and production builds pass.
- No tenant-owned row is nullable or reachable without tenant context.
- No global-personal row is reachable without owner or explicit grant authorization.
- No raw invitation token persists in PostgreSQL, logs, analytics, or job arguments.
- Two organizations can use every shipped surface independently with identical nicknames and no observable cross-tenant data.
- An independent account can register and use personal surfaces without a synthetic
  organization, while organization paths remain deterministic across tabs and
  bookmarks.
- ADR implementation notes and the technical debt ledger reflect all emergent decisions and deferrals.
