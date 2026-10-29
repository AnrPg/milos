# ADR-255: Setup recipes and the settings catalog («Προχωρημένα»)
Date: 2026-10-29
Status: Accepted

## Context
V3-M11 (CP-H1, CP-H2 of `docs/plans/competitive-parity-and-beyond.md`). The competitor review found
that Palee feels cluttered: about 104 switches across 142 staff pages, while Kilo, Arbox and
PushPress win on "easy to set up". The product owner wants a calm settings screen without option
overload, and a new box should be ready in one step: «CrossFit box», «Στούντιο προσωπικής
προπόνησης», … set packages, class types, booking rules and settings at once, all changeable later.

Settings are spread over many contexts (Scheduling, Finance, Gamification, Facility, Community,
Trials, Organizations, AI usage, referrals), each with its own table and screen, and nothing said
which ones an owner actually needs.

## Decision
1. **A new bounded context `Palee.Setup`** (ontology: «Συνταγή στησίματος» / setup recipe,
   «Προχωρημένα» / advanced settings).
2. **Settings catalog** (`Setup.Domain.SettingsCatalog`): every business setting with one verdict
   from the audit (`docs/plans/v3-settings-audit.md`): `basic`, `advanced`, `derive` (the app or a
   recipe sets it) or `remove` (not shown to owners; the code keeps it). A setting is advanced
   (hidden by default) unless basic. Nothing is deleted from the code. The web reads it from
   `GET /admin/setup/settings` and from `advanced_settings` on `GET /admin/settings`. A test keeps
   the audit's counts and the catalog in step.
3. **Recipes are data** (`Setup.Domain.Recipes`, seven: CrossFit box, Functional/HYROX, personal
   training studio, yoga/pilates studio, martial arts school, open gym, independent coach). Each
   declares a provider kind, settings by catalog key, class types, subscription packages (type
   preset plus a few catalog fields, suggested prices in cents), role grants and documents.
4. **The plan is the preview** (`Setup.Domain.RecipePlan`, pure): it compares a recipe with a
   snapshot of the business and lists changes (`set`, `create`, `add`, `manual`) and what is
   already in place. The same plan, rebuilt inside the transaction, is what apply executes, so
   applying twice changes nothing the second time. Rules: settings change when they differ (lists
   as sets); a package is created when no package has its code, a class type when no class type has
   its name in the business's language; role grants are only added; the trial's conversion package
   is set only while the box has none.
5. **Applied through a port** (`Setup.Ports.BusinessConfigurator`). The adapter
   `Application.Setup.ServicesConfigurator` reads each context through its public API and writes
   through the same use cases the settings screens call (`Scheduling.update_settings`,
   `Finance.update_finance_settings`, `UpdateCheckInRules`, `Application.Trials.update_policy`,
   `CreateClassType`, `CreateFinancePackage`, `Organizations.set_role_grants`, …), with the
   caller's tenant context and permissions. Setup never writes another context's tables.
6. **One transaction, recorded.** `RecipeApplicationStore.transaction/2` runs snapshot, plan, every
   change and the record in one database transaction holding a per-business advisory lock. A step
   that fails rolls everything back (`recipe_step_failed` with the step's key). The record
   `setup_recipe_applications` (tenant table, forced RLS, insert-only by use) keeps recipe key,
   version, who, when, the changes and the manual steps.
7. **Permissions.** Every endpoint needs `manage_settings`; applying is owner only
   (`recipe_owner_only`), because a recipe may change the provider kind and role grants, which are
   the owner's.
8. **Documents** are `manual` steps for now: the business has no document templates in this
   release. When `Palee.Documents` (V3-M8) lands, the adapter's snapshot lists the templates it
   has and the same plan creates the missing ones.

Endpoints (`/api/org/:slug/admin`): `GET /setup/settings`, `GET /setup/recipes`,
`POST /setup/recipes/:key/preview`, `POST /setup/recipes/:key/apply`.

## Rationale
- Declarative recipes are reviewable by the product owner and testable without a database; a
  recipe cannot do anything a staff screen could not.
- Going through the existing use cases keeps validation and side rules (e.g. revoking static
  member codes when the code mode changes) in one place and means a recipe can never produce a
  state the screens would refuse.
- A plan that is both the preview and the work list makes idempotence a property of the domain,
  not of careful adapter code.

## Alternatives Considered
- **Seed SQL per box type**: fast, but bypasses validation and RLS-scoped stores, and is not
  previewable. Rejected.
- **Recipe as a sequence of API calls from the web**: no transaction, no record, and every client
  would need the logic. Rejected.
- **Deleting or hiding settings in the API now**: breaks the existing web and clients. The verdict
  only labels; screens hide advanced settings once the mockups are approved.
- **Matching class types by slug**: the slug comes from the localized name, so an English recipe
  slug would not match a Greek business. Names in the business's language are compared instead.

## Consequences
- New tenant table `setup_recipe_applications` (migration `20270211000000`), registered in the
  tenancy audit, the architecture task's store list and the tenant-data contexts (purged, order 6).
- New error codes: `recipe_not_found` (404), `recipe_owner_only` (403), `recipe_step_failed` (422).
- The settings screen and the first-run «Τι box είσαι;» step wait for approved mockups; the API and
  the generated web client are ready.
- A recipe's content change needs a version bump; applications record the version.

## Implementation Notes
- Prices are suggestions in the business's currency (the fiscal country profile's, EUR otherwise).
- Package and class type names use the business's `default_locale` (Greek or English).
- Trial conversion in a recipe names a package by code; the adapter resolves it to the id after
  the packages are created in the same transaction.
- Open for the product owner: whether «remove» settings also leave the API responses in v3.1, the
  suggested prices per box type, and whether `subscription_grace_days` should be basic.
