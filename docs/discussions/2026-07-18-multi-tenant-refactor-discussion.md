# Multi-tenant refactor discussion — verbatim backup

Date: 2026-07-18

## User

don't forget to commit everything in small, semantic groups with insightful and explanatory short and very long commit messages. 
then, we will begin a big refactor in a new feature branch: let's brainstorm and discuss these decisions and expand on them so that the app can be sold to different clients and be used by them independently:
- each company-as-client can purchase the use of the app by buying a logical (virtual) space in the app
- the above means that each such client generates its own unique registration codes/signatures, has its own clientele, admin group and the data are completely isolated from other clients
- clientele is grouped using the client's codes that are generated or signed by a unique, bijectional way for the specific client
- codes can be generated live or be pre-generated once by you and stored in DB or follow a better approach. i want your input here with pros+cons elaboratively
- codes expire and are one-off, ephemeral
- for now, users and clients receive their codes manually by me, but later automatically by an email/OTP service (note it as tech debt in ledger)
- there must be a way to understand to which client/gym/coach a new user is registering without having them choose from a list. it should be automatically inferred, but how? give me suggestions and common practices with pros+cons.
- during admin registration (/set-admin) admins choose their affiliated client or even better it is also inferred in the same way as with users. then this admin account is added to the clients admins group
- data, statistics, configurations and EVERYTHING in the app is segmented, isolated and associated with a specific client/company/gym/organization.

## Assistant

Everything is committed in ten small semantic groups. Each commit has a concise subject and a detailed explanatory body. The working tree is clean, and nothing was pushed.

Recent commits:

```text
6bf4129 docs(debt): track invitation delivery automation
60689e3 fix(workouts): retain admin navigation
5f4a260 feat(messaging): promote messages to a drawer
a81d62f feat(analytics): explain operational metrics
4a95af4 fix(admin): hide empty attention chrome
3ac4f52 fix(ui): unify native controls and overlays
01fd61e feat(web): add /set-admin bootstrap
c24150f feat(auth): expose admin registration contract
9a7d454 feat(identity): gate admin creation
ae6725c docs(identity): accept code-gated admin bootstrap
```

Email/OTP invitation delivery is now recorded as `TD-034` in the [technical debt ledger](/home/rodochrousbisbiki/MyApps/milos/docs/technical_debt.md).

## Recommended tenancy model

I recommend treating each paying client as an `Organization`, also called a tenant or workspace internally.

The central model would be:

```text
Platform
└── Organization / tenant
    ├── Memberships
    │   ├── Owner
    │   ├── Admin
    │   ├── Coach
    │   ├── Gym member
    │   └── Athlete
    ├── Invitations
    ├── Configuration
    ├── Financial records
    ├── Classes and bookings
    ├── Workouts and assignments
    ├── Messages and notifications
    ├── Analytics and statistics
    └── Uploaded files and search indexes
```

The important distinction is:

- An account is an authenticated human.
- An organization is a paying client.
- An organization membership connects the human to that client and defines their role there.
- Tenant-owned data always carries an `organization_id`.
- Platform administration is separate from organization administration.

This is more flexible than storing a single global `role` on `users`. The same person could eventually coach for two gyms without data from either gym becoming visible to the other.

I would introduce at least:

```text
organizations
organization_memberships
registration_invitations
organization_domains
organization_settings
```

A membership would contain fields such as:

```text
organization_id
user_id
role
status
joined_at
invited_by
```

Roles should belong to the membership, not globally to the user. Someone could be an admin in one organization and an athlete in another.

## Data-isolation options

There are three serious deployment models.

| Model | Advantages | Disadvantages |
|---|---|---|
| Shared database and tables with `organization_id` | Lowest operating cost, straightforward migrations, efficient analytics, easiest to run for many small clients | A missing tenant condition can cause a data leak unless database-level protection exists |
| One PostgreSQL schema per organization | Better namespace separation and easier per-client exports | Migrations become complicated, connection/search-path handling is fragile, operational burden rises quickly |
| One database per organization | Strongest physical isolation, independent backup/restore, easier enterprise guarantees | Expensive, many connection pools, difficult global operations and migrations, much higher maintenance |

My recommendation is shared tables with PostgreSQL Row-Level Security, unless “completely isolated” specifically means that two clients’ records must never coexist in the same database.

Application-level filtering alone is not enough. The recommended defense is:

1. Every tenant-owned table has a non-null `organization_id`.
2. Every request establishes an authenticated tenant context.
3. Queries still explicitly filter by that tenant.
4. PostgreSQL RLS independently rejects cross-tenant rows.
5. The web application connects with a non-owner database role.
6. `FORCE ROW LEVEL SECURITY` prevents accidental table-owner bypass.
7. Composite foreign keys prevent linking rows across tenants.
8. Isolation tests create two tenants and attempt every relevant cross-tenant read and mutation.

For example, a booking belonging to organization A must not be able to reference a class from organization B, even if both UUIDs exist.

## Registration-code design

I strongly recommend opaque, random, database-backed invitation tokens.

A code should not mathematically encode the client ID. It should instead map to exactly one invitation record, which itself belongs to exactly one organization:

```text
random token
    ↓ hash lookup
registration invitation
    ├── organization_id
    ├── intended role
    ├── expiry
    ├── redeemed_at
    └── issued_by
```

The relationship is effectively one-to-one without using a reversible or “bijective” transformation.

A deterministic client-derived code is undesirable because it can:

- Reveal internal organization identifiers.
- Make codes predictable.
- Allow attackers to infer relationships between codes.
- Make secret rotation difficult.
- Accidentally turn one compromised client secret into unlimited invitations.

### Recommended token format

Generate at least 128 bits of cryptographically secure randomness and encode it with URL-safe Base64 or a human-friendly alphabet.

For example:

```text
MLOS-X7KM-4QVN-9HPT-J2CR
```

The prefix is only branding/versioning. It must not identify the organization.

Store only a digest of the code, similar to password-reset tokens. The clear code is shown once to the issuer and then distributed manually.

A record might contain:

```text
id
organization_id
token_digest
membership_role
expires_at
redeemed_at
revoked_at
issued_by_user_id
intended_email_digest   # optional later
created_at
```

Redemption must be transactional:

1. Find the invitation by token digest.
2. Lock it.
3. Confirm it is unused, unrevoked, and unexpired.
4. Create the account or membership.
5. Mark it redeemed.
6. Commit everything together.

Two simultaneous submissions must never redeem the same code twice.

### Live generation versus pre-generation

| Approach | Pros | Cons |
|---|---|---|
| Generate live when an admin invites someone | Shorter exposure window, correct role and expiration, immediate auditing, no unused inventory | Requires the application to be available when issuing |
| Pre-generate batches and store them | Useful for printed cards, reception desks, offline onboarding, bulk events | Codes may sit unused or be lost; harder revocation and attribution; larger theft surface |
| Stateless signed token | No lookup needed for basic validity, portable | One-time use and revocation still require database state, so the main advantage disappears |
| Deterministic tenant-derived code | Easy to reproduce | Predictable, difficult to revoke, dangerous for authorization; not recommended |
| Hybrid database-backed token | Supports live and controlled batch creation using the same secure model | Slightly more database state, but operationally straightforward |

I recommend the hybrid model:

- Use the same opaque database-backed invitation entity.
- Generate invitations live by default.
- Permit explicitly audited batch generation later for reception or printed cards.
- Never store reusable organization registration codes.

Suggested defaults:

- Initial organization-owner invitation: 24 hours.
- Additional admin invitation: 24–48 hours.
- Member or athlete invitation: 7 days.
- All invitations: exactly one redemption.
- Expiration may be shortened by an organization but should have a platform maximum.

## Automatically identifying the client

The invitation itself is the most reliable tenant-discovery mechanism.

The preferred registration flow is:

```text
Platform owner creates organization
        ↓
Initial organization-owner invitation generated
        ↓
Recipient receives /set-admin?invite=<opaque-token>
        ↓
Server validates invitation and resolves organization
        ↓
Page shows “You are joining Acme Gym”
        ↓
Registration creates account and organization membership
        ↓
Invitation is permanently consumed
```

The registrant never selects an organization from a list and cannot alter the organization in the request body.

### Discovery approaches

| Approach | Advantages | Disadvantages |
|---|---|---|
| Invitation link containing an opaque token | Strongest inference, easy user experience, role and tenant resolved together | Links must be protected because they are temporary bearer credentials |
| Manually typed invitation code | Works through phone, paper, or in-person delivery | More typing errors and phishing risk |
| Organization subdomain | Excellent ongoing tenant context and branding | Requires wildcard DNS/TLS, slug management, and domain-routing infrastructure |
| Custom organization domain | Professional client branding | Domain verification, certificate management, support burden |
| Email-domain inference | Convenient for corporations | Unsafe for public domains, consultants, franchises, and shared domains |
| SSO/identity-provider inference | Strong enterprise onboarding | Considerably more integration and configuration work |
| QR code | Excellent for reception or physical marketing | It is merely another representation of the invitation link and must remain short-lived |

My recommendation combines invitation links and tenant subdomains:

```text
https://milos.example.com/join/<token>
```

The server validates the invitation and redirects to:

```text
https://acme-gym.milos.example.com/register
```

For administrators:

```text
https://milos.example.com/set-admin?invite=<token>
```

The token determines both the organization and intended admin role. The page may display the organization for confirmation, but the organization should not be an editable form value.

Typed codes and QR codes can resolve to exactly the same invitation record.

Email-domain inference should only be an optional enterprise convenience after ownership of that domain has been verified. It should never be the primary authorization mechanism.

## How `/set-admin` should evolve

The current fixed `DEY48keGE` gate is suitable only as a temporary bootstrap mechanism.

In the tenant design:

- Platform-level organization creation is available only to the platform owner.
- Creating an organization generates its initial `organization_owner` invitation.
- `/set-admin` requires that invitation.
- The invitation determines the organization and admin role.
- Additional organization admins are invited by authorized organization owners/admins.
- No registrant chooses their own organization or role.
- The fixed global code is removed from normal tenant onboarding.
- A separate emergency platform-bootstrap mechanism may remain, but it must not create tenant admins.

This prevents someone who learns one global code from creating an administrator in an arbitrary organization.

## Identity isolation decision

There are two credible choices.

### Global account with tenant memberships

A person has one authentication account and one or more organization memberships.

Advantages:

- One login across multiple gyms.
- Natural support for consultants and coaches.
- Less duplicate personal data.
- Common SaaS model.

Disadvantages:

- The platform knows that memberships belong to the same human.
- Account recovery is platform-wide.
- Tenant-specific nicknames and profiles must move onto memberships or tenant profiles.

### Completely tenant-contained accounts

Every organization has its own independent account records, even when the same email belongs to the same person.

Advantages:

- Strong privacy boundary.
- Same nickname/email can independently exist in every organization.
- Account deletion and export are naturally tenant-contained.

Disadvantages:

- Users need separate accounts for multiple gyms.
- Coaches working across organizations have duplicated credentials.
- Future account linking becomes difficult.

My default recommendation is global authentication accounts with tenant memberships, but with these restrictions:

- Tenant profiles, nicknames, health information, preferences, roles, and activity belong to the membership/organization.
- Do not automatically link accounts across organizations merely because email addresses match.
- Platform operators cannot casually browse tenant records.
- Cross-organization membership discovery is never exposed to tenant admins.

If absolute contractual privacy requires even authentication identities to be independent, choose tenant-contained accounts before migrations begin.

## “Everything” that must become tenant-aware

Adding `organization_id` to business tables is only part of the work. Tenant context must also cover:

- PostgreSQL rows and materialized views.
- Unique indexes and foreign keys.
- Oban jobs and job uniqueness.
- Phoenix Channel and PubSub topic names.
- Redis cache keys.
- Meilisearch documents, filters, or per-tenant indexes.
- Object-storage paths and presigned URLs.
- Notifications and push subscriptions.
- Message threads and participants.
- Uploaded files and avatars.
- Analytics events and aggregates.
- Finance ledgers, packages, promotions, and invoices.
- Class types, configuration, themes, and feature settings.
- Audit logs.
- CSV/calendar exports.
- Rate-limit keys where tenant identity matters.
- Logs, traces, and metrics labels.
- Background reconciliation and cleanup jobs.

There will still be a small amount of intentionally platform-global data:

- Organization registry.
- Platform subscription plans.
- Platform operator accounts.
- Database migrations.
- Global system reference data.
- Platform-wide infrastructure configuration.

Every exception should be explicitly classified rather than left tenantless by accident.

## Recommended refactor sequence

Before implementation, I would create several ADRs rather than one oversized decision:

1. Tenant identity and membership model.
2. PostgreSQL isolation strategy and RLS.
3. Invitation generation and redemption.
4. Tenant resolution through links, hosts, sessions, and Channels.
5. Tenant propagation through jobs, caches, search, storage, and analytics.
6. Existing-data migration and rollout strategy.

Then implement incrementally:

1. Create the feature branch.
2. Add organizations, memberships, invitations, and domains.
3. Create one “legacy organization” and backfill all existing records into it.
4. Introduce a mandatory `TenantContext`.
5. Make authentication and `/set-admin` invitation-aware.
6. Add tenant columns context by context.
7. Add composite constraints and RLS after backfill.
8. Scope Channels, jobs, cache, search, and storage.
9. Add two-tenant isolation tests for every bounded context.
10. Make tenant columns non-null and remove transitional fallbacks.
11. Perform a live cross-tenant penetration test.
12. Only then expose organization provisioning commercially.

My recommended decisions to carry into the new branch are:

- Shared PostgreSQL tables with mandatory `organization_id` plus RLS.
- Global authentication principals with organization memberships.
- Opaque, random, hashed, one-time invitation tokens.
- Invitations infer both organization and role.
- Invitation links as the primary onboarding method.
- Tenant subdomains for ongoing organization context.
- No organization picker during registration.
- Replace the global `/set-admin` code with tenant-owner invitations.
- Backfill the current deployment into a default legacy organization.
- Treat every cache, job, file, message, search document, and statistic as tenant-owned by default.

The feature branch has deliberately not been created yet so these foundational choices can be confirmed first.

## User

i agree with everything. first export our discussion verbatim as backup and then create the feature branch and start planning the implementation and then begin the implementation in the branch
