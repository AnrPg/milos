# ADR-191: Partner perks — redemption methods, an open policy model and versioned terms
Date: 2026-10-23
Status: Accepted

## Context
Gyms and coaches want to give their clients deals at outside stores: a
supplements shop, a physio, a café, an online sportswear store (TD-188).
`GET /api/me/billing` (Εγώ › Πληρωμές) already had an empty `perks` slot
(`BillingPerk`). Partners work in very different ways. Some hand out one
shared code. Some give a batch of single-use codes. Some only want to see
a membership card. Online stores want a link with the code already in it.
Some have no system at all and want Palee to tell them whether a member's
voucher is good. Their terms differ too: percent or fixed amount, a free
item, buy X get Y, minimum spend, weekday mornings only, once a month per
member, members of a package only. The owner asked us not to restrain
partners' policies. That means an open model, not a fixed form. It must
also keep what a member agreed to when the business later changes the
terms.

The billing work (ADR on member billing, TD-188/189) owns the billing
page. This ADR owns the perks context, the business API, the member API
and the partner's verification link. The web screens come separately,
once the mockups are approved.

## Decision
1. **A perk is a partner plus a version.** `perks` holds the partner
   (name, URL, address, logo upload), the redemption method, the covering
   branches (ADR-186 §8: all branches or `location_ids`), the lifecycle
   (`draft → published ⇄ paused → expired`; past `valid_until` it reads as
   expired without a write) and the counters (`claims_count`, `uses_count`).
   `perk_versions` hold the terms as three validated documents and a text:
   - `benefit`: percent, fixed amount, free item, buy X get Y or free text,
     with optional minimum spend and cap;
   - `rules`: validity window, recurring weekly windows in local time, a
     channel (in store, online or both), stacking notes, limits and
     eligibility;
   - `redemption`: the method's settings;
   - `terms`: free text.

   Limits cover the overall cap, a per-member cap (default 1) and per-period
   caps (day, week or month) for everyone and for each member. Eligibility
   covers packages (memberships are packages), club groups and minimum
   tenure. Each document is an embedded Ecto schema carrying its own
   `schema_version`. The table checks that every document is a JSON object
   with a `schema_version`, so a new kind of rule is a new field, not a
   migration.

2. **Versioning.** Until the first claim, a change amends the current
   version. After it, a change to the benefit, rules, redemption or terms
   makes version N+1. Every claim records its `perk_version`, and the member,
   the export, the billing slot and the partner's link all read the claim's
   own version. Once a perk is claimed, the method is fixed and the overall
   cap can't drop below the claims made. An ended perk is read-only.
   `GET …/perks/:id/versions` lists the history.

3. **Redemption methods are strategies.** `Perks.Domain.RedemptionMethod`
   is a behaviour with five modules:
   - `shared_code` (the default): one code for everyone;
   - `code_pool`: a batch of single-use codes the partner gave, pasted or
     uploaded as CSV and topped up any time. One code goes to each claim
     (`FOR UPDATE SKIP LOCKED`). There is a low-pool alert, with a default
     threshold of 10. Publishing needs a free code;
   - `partner_link`: an https store link, where `{code}` is replaced by the
     URL-encoded shared code;
   - `show_membership`: no code. The claim still records the use and
     carries a reference;
   - `personal_qr`: a single-use QR that Palee issues and the partner
     verifies with a signed link (§5).

   Each strategy says what settings it needs (`validate/1`), how a claim
   gets its code (`issue/0`: shared, pool or reference), whether it can be
   verified, whether it is ready to go live, and what the member sees
   (`reveal/2`). Partner-issued codes are checked by the partner in its own
   system. Palee only reveals and records them.

4. **Claims are atomic.** Claiming takes `FOR UPDATE` on the perk. Under
   that lock it counts the member's claims and the claims in the current
   period, applies `PerkRules.claim_check/2`, then either inserts the claim
   and increments `claims_count`, or returns the member's open claim, which
   makes claiming idempotent. A pool claim takes its code in the same
   transaction. Marking a claim used is a conditional update
   (`status = 'claimed'`) under the same lock. Revoking a claim frees its
   place. The check constraints are the last line of defence, for example
   `uses_count <= claims_count`.

5. **The partner verification link (personal QR).** The member's QR opens
   `/perks/verify/<token>`. The API side is
   `GET /api/public/perk-verifications/:token` and `POST …/:token/redeem`.
   The link is:
   - **signed**: `Phoenix.Token` with the endpoint secret, salt
     `perk-verification-v1`. The payload is `{v, claim, org, nonce, expiry}`;
   - **expiring**: at most 30 minutes, and never past the perk's last day.
     It carries its own expiry, and the signer's `max_age` applies too;
   - **revocable**: only the SHA-256 of the nonce is stored on the claim
     (`token_hash`), and it is compared in constant time. Opening a new QR
     rotates it. The business revoking the claim answers `revoked`, and
     marking the claim used clears it;
   - **single-use**: the redeem rechecks the secret and the status under
     the lock;
   - **rate-limited**: 60 requests a minute per client (`public-perk`
     bucket), with `cache-control: no-store` and `referrer-policy:
     no-referrer`;
   - **minimal**: it shows the perk (partner, benefit line, terms, last
     day), the business's name and logo, the status (valid, used, revoked,
     outside_hours or expired), the short code and the member's **first
     name only**.

   Every failure of the token itself answers the same
   `invalid_verification_link` (404); only a well-signed link past its
   expiry answers 410.

6. **Who sees what.** Members get the perks of every provider where they
   hold a client role (member or athlete). Staff-only memberships don't
   count, and demo businesses never count (ADR-184). Each provider is read
   in its own tenant context, and a failing provider is left out.

   A perk shows when it is live, at the member's branch (members without a
   home branch roam) and within its eligibility. No code is shown before a
   claim. The staff API (`/api/org/:slug/admin/perks…`) needs the
   `manage_perks` capability (admins). Branch-scoped staff see and change
   only perks of their branches, and «all branches» needs all-branch staff.

   A business in demo mode drafts perks but can't publish them
   (`GoLivePolicy :publish_perk` → `business_not_activated`).

7. **Billing.** `MemberPerks.for_member_provider/1` returns `BillingPerk`
   rows, `{id, store, discount, code, terms, valid_until, url}`, for the
   claims the member can still use, read from their version. `MyBilling`
   fills `providers[].perks` from it in its own `safe/3` section, so a
   failure there marks the provider `partial`.

8. **Storage and observability.** There are four tables: `perks`,
   `perk_versions`, `perk_codes` and `perk_claims`. Each has
   `organization_id`, composite foreign keys `(perk_id, organization_id)`,
   RLS with FORCE and the tenant-context trigger. They are classified in
   the tenancy audit and the tenant data policy, which excludes
   `token_hash` from exports. Every staff action, claim, use, revocation,
   export, new version and low-pool alert is an analytics event (the audit
   trail), with `[:palee, :perk, …]` telemetry. These are `perk_created`,
   `perk_versioned`, `perk_published`, `perk_paused`, `perk_expired`,
   `perk_codes_added`, `perk_claims_exported`, `perk_pool_low`,
   `perk_claimed`, `perk_redeemed` and `perk_claim_revoked`.

9. **CSV export.** `GET …/perks/:id/claims` pages as JSON, using an
   `after` cursor and up to 1,000 rows per page. `…/claims.csv` follows RFC
   4180 with CRLF line ends. Cells a spreadsheet would read as a formula
   are prefixed with `'`.

## Rationale
One strategy module per method keeps every method's quirks in one place,
and adding a sixth method doesn't touch the claim path. Validated
documents with a schema version give partners an open set of rules
without a column per rule. They still refuse nonsense at the edge: a
period without a cap, a link that isn't https, `{code}` without a code.

Versions are the only honest way to change terms after people have
accepted them. Amending until the first claim keeps drafting cheap.

The QR link has no account behind it, so its safety is the token: signed,
short-lived, bound to a rotating secret, rechecked under a lock, and
showing nothing a stranger could use.

## Alternatives Considered
- **A fixed form** (a percent and a code). The owner rejected it: it
  can't express pools, links, recurring windows or eligibility.
- **Rules as columns.** Every new rule would need a migration, and
  versioning them would mean copying rows. JSON without validation was
  also rejected: it would accept anything.
- **A partner account and portal** to verify codes. It is heavier for
  small partners and is deferred (TD-191). The signed link works for a
  counter with only a phone.
- **Long-lived or reusable QR links.** A screenshot would become a
  voucher. They are short-lived and single-use instead.
- **Rewriting claimed terms in place.** That breaks what members agreed
  to. Rejected.

## Consequences
- The web needs:
  - the console screens (perk editor with method-aware fields, code
    upload, claims and export);
  - the member screens (list, claim, the QR with its first-name
    verification);
  - the public page `/perks/verify/:token` that calls the public API.

  The generated client already has the types.
- Low-pool alerts are events and telemetry, not staff notifications yet
  (TD-194).
- Eligibility by package reads the member's own subscriptions; a
  beneficiary's share of a family package doesn't count yet (TD-194).
- True parallel claims can't be shown inside the SQL sandbox. The race
  test checks the cap holds with concurrent tasks on one connection; the
  lock and constraints carry it in production.

## Implementation Notes
- Migration `20261212000000_partner_perks`.
- Domain: `Palee.Perks.Domain.{PerkRules, RedemptionMethod, Methods.*,
  CodeImport, VerificationToken, TenantDataPolicy}` and the documents
  `Palee.Perks.{Benefit, Rules, Rules.*, Redemption, PerkVersion}`.
- Port `Palee.Perks.Ports.PerkStore`, facade `Palee.Perks.PerkStore`
  (every call through `RepoContext.run`), adapter
  `Palee.Infrastructure.Perks.EctoPerkStore`.
- Application: `Palee.Application.{Perks, MemberPerks, PerkVerification,
  PerkPresenter}`.
- Web: `AdminPerkController`, `MyPerkController`,
  `PerkVerificationController`. Schemas live in `PaleeWeb.Schemas.Perks`,
  where the shared shapes are named components, and
  `PaleeWeb.Schemas.PerkParts`.
- `PromotionCode.normalize_code/1` (finance) is now public and normalizes
  shared and pool codes the same way promotion codes are normalized.

## Future
- Partner self-service portal: TD-191.
- Affiliate revenue share: TD-192.
- Inbound partner codes, or reverse perks (a partner's customers redeem
  the box's codes or QRs at check-in or sale), are to be decided with ANR:
  TD-193. They could reuse these redemption strategies and run the signed
  verification engine in reverse.
- Perk follow-ups (staff low-pool notification, the web verification
  page, beneficiaries in eligibility): TD-194.
