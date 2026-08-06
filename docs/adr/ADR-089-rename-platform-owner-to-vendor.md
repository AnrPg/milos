# ADR-089: Rename Platform Owner to Vendor

Date: 2026-08-06
Status: Accepted

## Context

The multi-tenancy audit (`docs/audits/multi-tenancy-audit/`) surfaced a naming
collision between two distinct authorization concepts that both used the word
"owner":

1. **`platform_owners`** — an installation-wide authority, independent of any
   organization, granted only via `mix milos.platform.grant_owner` (see
   ADR-087, ADR-088). This is the SaaS operator's own account.
2. **`organization_memberships.role == :owner`** — the highest tenant-scoped
   role within a single organization (a gym owner or freelance coach —
   the SaaS product's customer).

Product design decisions for this project have consistently used "owner" to
mean the SaaS-level party (#1) and "admin" to mean the SaaS's client (#2's
`:owner`/`:admin` tenant roles). The codebase's naming inverted this: the
literal word "owner" was attached to the *tenant*-level role, while the
platform-level concept was also called "owner" — the same token used for two
different authority levels, one of which conflicted with the design
vocabulary.

Renaming the tenant-level `:owner`/`:admin` roles was considered but rejected
for this change: that enum is threaded through ~48 files (RLS policies,
`TenantAuthorization`, invitation flows, migrations, tests). The platform-level
concept touches a much smaller, self-contained surface: one table, one Ecto
schema, one plug, one Mix task, one context resolver, and their direct
call sites (~24 backend files, ~6 frontend files, plus the generated OpenAPI
contract).

## Decision

Rename the SaaS-level "platform owner" concept to **Vendor** everywhere it is
represented as a distinct identifier:

- Table `platform_owners` → `vendors`; column
  `organization_provisioning_events.platform_owner_user_id` → `vendor_user_id`
  (migration `20260806160000_rename_platform_owner_to_vendor.exs`, fully
  reversible).
- Schema `MilosTraining.Organizations.PlatformOwner` →
  `MilosTraining.Organizations.Vendor`.
- Store functions `grant_platform_owner/1`, `get_platform_owner/1` →
  `grant_vendor/1`, `get_vendor/1` (context, port, and Ecto adapter).
- Plug `MilosTrainingWeb.Plugs.RequirePlatformOwner` →
  `MilosTrainingWeb.Plugs.RequireVendor`; router pipeline `:platform_owner` →
  `:vendor`.
- Error code `"platform_owner_required"` → `"vendor_required"`.
- Mix task `mix milos.platform.grant_owner` → `mix milos.platform.grant_vendor`.
- `PlatformContext` struct field `:platform_owner` → `:vendor`.
- Public API field `platform_owner` on `GET /api/auth/me` → `vendor` (OpenAPI
  contract regenerated, frontend consumers updated).

Not renamed: the `PlatformContext` struct/module name, `ResolvePlatformContext`,
and the `/api/platform/*` route namespace — "platform" alone does not collide
with either tenant role and denotes the request-scoping concept, not the
authority holder.

Tenant-scoped `:owner`/`:admin` roles (`organization_memberships.role`) are
**unchanged** by this ADR. See the multi-tenancy audit for a related, separate
question raised about whether that tenant-level distinction is itself
warranted (no enforcement gap was closed or introduced by this rename).

## Rationale

The platform-level concept was the cheaper, non-controversial side of the
collision to rename (~30 files total vs. ~48 for the tenant role), and
"Vendor" is a term that cannot be confused with either tenant role
(`owner`/`admin`), unlike alternatives considered.

## Alternatives Considered

- **Rename tenant `:owner`/`:admin` instead** — correct in the abstract (it's
  the newer/more pervasive name that's actually ambiguous with itself), but
  ~8x the surface area and touches RLS policies and live authorization checks,
  raising the risk of the change for no functional benefit.
- **"Operator" / "Steward" / "Root"** — considered; "Vendor" was chosen
  because it best conveys "the company operating the SaaS" rather than an
  infra/ops framing, matching how the term is used in product conversations.
- **Leave as-is, document only** — rejected; a documentation-only fix does not
  stop new code (or new agents) from continuing to write `platform_owner` and
  perpetuating the ambiguity.

## Consequences

- Any external tooling, scripts, or dashboards querying the `platform_owners`
  table or the `platform_owner` field on `/api/auth/me` must be updated to the
  new names before this migrates to production.
- `mix milos.platform.grant_owner` no longer exists; use
  `mix milos.platform.grant_vendor`.
- Future audits, ADRs, and code should use "vendor" for the SaaS-level party
  and reserve "owner"/"admin" exclusively for tenant-scoped roles.

## Implementation Notes

Migration `20260806160000_rename_platform_owner_to_vendor.exs` renames the
table, column, and their indexes/constraints (primary key, unique index, check
constraint, both foreign keys), guarded with existence checks so it is a
no-op-safe rename regardless of the exact auto-generated constraint names in
a given environment. `up`/`down` verified against a live Postgres instance.
