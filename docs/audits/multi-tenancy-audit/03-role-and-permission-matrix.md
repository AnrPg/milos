# Role and Permission Matrix

> **Terminology note (2026-08-06):** "platform owner" / "SaaS owner" /
> `platform_owners` below were renamed to **Vendor** / `vendors` by
> [ADR-089](../../adr/ADR-089-rename-platform-owner-to-vendor.md). This page
> is left as originally written; read those terms as "vendor". The
> tenant-scoped `owner`/`admin` roles in §3 below are a separate, unrenamed
> concept.

Date: 2026-08-05. Built from direct code inspection of `apps/api/lib/milos_training/organizations/`,
`apps/api/lib/milos_training/identity/`, `apps/api/lib/milos_training_web/router.ex`,
`apps/api/lib/milos_training_web/plugs/`.

## 1. SaaS-owner authority (`platform_owners`)

| Field | Value |
|---|---|
| Storage | `platform_owners` table, keyed by `user_id`, `status ∈ {active, revoked}` |
| Who may assign | `mix milos.platform.grant_owner NICKNAME` — CLI/Mix task only, no HTTP endpoint. Confirmed sole caller of `grant_platform_owner/1` in the entire codebase. |
| Who may revoke | **No code path exists.** No `revoke_platform_owner` function in `ports/organization_store.ex`, `organization_store.ex`, or the Ecto adapter. Once granted, only direct DB manipulation can revoke it (F-09). |
| Scope | Installation-wide; independent of any organization membership |
| How checked | `RequirePlatformOwner` plug → `ResolvePlatformContext` → `OrganizationStore.get_platform_owner(user_id)` → `Repo.get_by(PlatformOwner, user_id:, status: :active)` |
| Self-escalation possible? | No — Mix-task-only, no HTTP surface (verified) |
| Automatically = global admin? | N/A — there is no separate "global admin" role distinct from platform owner in this codebase; see §2 |

## 2. Other global roles

The codebase does **not** implement a distinct "global admin" role separate from
platform owner. However, the legacy `users.role` field (`Ecto.Enum,
values: [:member, :athlete, :admin]`) is *functionally* a global role that is
still read as an authorization source on several code paths that never resolve
tenant context (F-02):

| Global `user.role` value | Where it still gates behavior directly (bypassing membership role) |
|---|---|
| `:admin` | `application/get_calendar_feed.ex` (unauthenticated-adjacent ICS feed reveal), `application/get_schedule_calendar.ex:75` (fallback path when no TenantContext), `application/get_leaderboard_snippet.ex:7`, `infrastructure/identity/ecto_user_store.ex` (queries/guards, including a global "don't demote the last admin" invariant), `infrastructure/workouts/ecto_workout_store.ex:1910` |
| `:admin` used to *exclude* accounts from listings | `application/admin_search_users.ex`, `application/admin_member_search_documents.ex`, `application/list_finance_members.ex` |

`MilosTrainingWeb.Plugs.RequireRole` (the plug that would check this global role
at the HTTP layer) is **dead code** — never wired into any router pipeline. The
risk is not from that plug; it is from application-service-layer code reading
`actor.role`/`user.role` directly instead of the membership role from
`TenantContext`.

## 3. Tenant-scoped roles (`organization_memberships.role`)

| Role | Granted by | Scope | Notes |
|---|---|---|---|
| `owner` | Platform owner (initial, at provisioning — ADR-087) or any existing `owner`/`admin` via `IssueInvitation` (**unintentionally, since no role-ceiling check exists — F-07**) | Single organization | Highest tenant role |
| `admin` | `owner`/`admin` via `IssueInvitation`, or platform owner via platform tenant-access invitations (ADR-088) | Single organization | Can also issue `owner` invitations due to F-07 |
| `coach` | `owner`/`admin` | Single organization | |
| `member` | `owner`/`admin`, or self-registration (no invitation) | Single organization | |
| `athlete` | `owner`/`admin` | Single organization | |

Authorization choke point: `Organizations.Domain.TenantAuthorization.build/4`
validates org `status == :active`, membership org/user match, membership
`status == :active`, and `authorize/2` checks `role in allowed_roles`. This is
correctly membership-based, not user-based — the invariant "authorization in
tenant A depends on membership(U,A), not membership(U,B)" **holds** for every
code path that actually goes through `TenantAuthorization`/`TenantContext`.
It does **not** hold for the ~140 legacy `/api/admin/*` routes and the
`POST /api/executions` path, which resolve identity/role independent of a
correctly-scoped `TenantContext` (see F-01, F-03, F-02).

## 4. Membership state

| Status | Meaning | Transition command available? |
|---|---|---|
| `invited` | Pending, not yet active | Set by invitation issuance |
| `active` | Default; only status accepted by `MembershipPolicy.authorized_status?/1` | Set by redemption |
| `suspended` | Implied de-authorization | **No command exists to set this** (F-08) |
| `revoked` | Implied permanent removal | **No command exists to set this** (F-08) |

**Gap:** the enum implies a de-authorization workflow that is not implemented.
An organization currently has no way to cut off a member's/admin's access short
of deleting the underlying global `users` account (which is a blunt,
cross-organization-impacting instrument since accounts are global).

## 5. Invitation-granted roles

| Invitation type | Issuer | Role source | organization_id source | Verified constraint |
|---|---|---|---|---|
| Initial owner (provisioning) | Platform owner | Hardcoded `:owner` | Newly-created org, same transaction | Correct — matches ADR-087 |
| Tenant self-service | `owner`/`admin` | **Client-supplied `role` param, validated only against the full tenant role set — no ceiling check against issuer's own role** | `context.organization_id` (server-resolved, correct) | **F-07: broken** |
| Platform tenant-access (ADR-088) | Platform owner | Client-supplied, any tenant role (intended — caller already platform-authorized) | URL path `:id`, looked up server-side (correct) | Correct — matches ADR-088 |

Redemption: token looked up by SHA-256 digest, `SELECT ... FOR UPDATE`,
`InvitationPolicy.redeemable?/2` (unexpired/unredeemed/unrevoked), atomic
membership creation + invitation-redeemed marking in one transaction. Sound.
`intended_email_digest` is computed and stored on every issuance path but
**never read back or compared during redemption** (F-13) — any authenticated
account (or freshly created one) holding the token can redeem it, regardless of
whether it matches the intended recipient's email.

## 6. Support / impersonation capabilities

No impersonation or "support login as tenant" feature was found in either
backend or frontend code during this audit. Platform owners access tenant data
through the tenant `owner` membership granted to them at provisioning time
(ADR-087), not through an impersonation mechanism — this is the correct,
auditable design per the ADR, though it does mean platform owners who
provisioned an org remain a permanent tenant-owner member of it (an accepted,
documented consequence in ADR-087, not a defect).

## 7. Service-account / machine privileges

No dedicated service-account/machine-credential model was found. Oban job
workers run in-process with the application's own database role; job-level
tenant scoping relies on job args carrying `organization_id`/`owner_user_id`
(ADR-059) rather than a distinct machine identity/credential.

## 8. Invariant test: `authorization(U, A)` must depend only on `membership(U, A)`

| Code path | Holds? | Evidence |
|---|---|---|
| `/api/org/:organization_slug/...` routes (new, slug-scoped) | **Yes** | `ResolveTenantContext` derives org strictly from path slug + DB membership |
| `/api/admin/*` routes (~140 endpoints, legacy) | **No** | Tenant resolves from `x-organization-slug` header (client-controlled) or the legacy org, not from any path-encoded tenant (F-01) |
| `POST /api/executions` (`self_selected`/`class_booking` sources) | **No** | `organization_id` accepted directly from client body with no membership check (F-03) |
| WebSocket connections without an explicit `organization_slug` param | **Partially** | Falls back to legacy org, but still membership-gated before context is built (F-01/§3 of `05-legacy-gym-inventory.md`) |
| Global `user.role == :admin` code paths (§2 above) | **No** | Authorization derived from account-wide role, not any specific organization's membership (F-02) |
