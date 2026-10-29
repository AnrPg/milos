# ADR-271: «Πωλείται online» opens on connect, the owner's choice wins, and the API says why a package is not visible
Date: 2026-10-29
Status: Accepted

## Context
ADR-248 added `membership_packages.sold_online` (default `false`): only packages a box marks
«Πωλείται online» appear on the Σελίδα πακέτων and can be bought in the app. No screen set it, so
a box that connected Viva or Stripe still sold nothing online. The pilot-gap mockup (screen p1,
alternative A) puts one switch in the package panel, an «Online» badge in the list, and a count
with a link in Ρυθμίσεις › Πληρωμές and the Συνταγή στησίματος. The product owner then decided
(2026-10-29): when a box connects an online payment provider, its paid packages go on sale online
automatically and the owner is told; the owner can switch each package off in the package's
advanced settings; Palee never switches back on a package the owner switched off; and the API
explains why a package marked «Πωλείται online» is not visible.

## Decision
1. **One rule module.** `Palee.Payments.Domain.PackageSale` holds every rule: the «Τι πληρώνεται
   online» purpose of a package (ADR-260), `visibility/2`, `listed?/2` (public page), `opens?/2`
   (automatic opening) and `default_on?/2` (new packages). The public page
   (`OnlineSales.public_packages/1`) now filters with `listed?/2`, so the staff field and the
   page cannot disagree.
2. **`online_visibility`** is computed on every staff package row (`GET/POST/PATCH
   /admin/finance/packages…`): `visible`, or why not, in this order: `inactive`, `free` (price 0),
   `off` (front desk only), `purpose_off` (the provider is connected but the purpose is off in
   «Τι πληρώνεται online»), `no_provider` (listed, bought once online payments connect). The web
   shows the hint and the fix link from this value only.
3. **Owner's choice.** A `sold_online` sent by staff (create or update) stamps
   `membership_packages.sold_online_chosen_at`. Automatic changes skip any package with a stamp.
4. **Opening on connect, once.** After the provider accepts the account (pasted keys, ADR-246, or
   one button, ADR-261) and payments are available, `OnlineSales.open_on_connect/2` claims
   `payment_accounts.packages_opened_at` (only when empty), switches on every active paid package
   whose purpose is allowed and whose owner never chose, and keeps the number in
   `packages_opened_count`. Reconnecting later never runs it again.
5. **Telling the owner.** `GET /admin/payments/account` returns `account.packages_notice`
   (`{count, opened_at}`) until the owner closes it with `DELETE
   /admin/payments/account/packages-notice` (`packages_notice_dismissed_at`), and
   `online_sales` (`{sold_online, packages}` over the active paid packages) for «N από M πακέτα
   συνδρομής πωλούνται online» in Πληρωμές and the Συνταγή στησίματος (read only, with a link).
6. **New packages.** A paid package created while online payments are available (and its purpose
   is on) starts sold online unless the request carries `sold_online`. Recipes and imports go
   through the same service and follow the same rule.

Migration `20270310000000_v31_sold_online` adds the four nullable columns; no new table, no RLS
change (both tables are already tenant tables).

## Rationale
The owner connected payments to sell; asking them to open five panels afterwards (the con of
mockup option A) left the Σελίδα πακέτων empty. Opening once, with a visible notice and a per-package
«off» that is remembered, gives the shop on day one without ever overriding a decision. Keeping
the rules in one domain module (instead of duplicating them in the web, as the mockup's
`saleState` does) means a hint can never say «visible» while the public page hides the package.

## Alternatives Considered
- **Open every time the box connects.** Rejected: reconnecting after a provider change would
  surprise owners who curated the list; the owner's stamp protects switched-off packages, but a
  package created while disconnected would appear without being asked for.
- **A boolean «owner chose» flag.** A timestamp costs the same and tells support when it happened.
- **Compute visibility in the web.** Rejected: two copies of the ADR-260 purpose mapping.
- **Mockup option B (a checklist in Πληρωμές).** Rejected by the owner earlier: a second home for a
  package field.

## Consequences
- A package created while the box is disconnected starts front-desk only, and a later reconnect
  does not open it (the opening already happened); the owner switches it on in the package panel.
- A package switched on while its purpose is off reports `purpose_off` with a link to
  Ρυθμίσεις › Πληρωμές.
- `open_on_connect` reads packages of every branch; branch managers cannot connect payments
  (`manage_billing`), so this is the owner's scope anyway.

## Implementation Notes
- `Finance.open_packages_online/2` is a single tenant-scoped `UPDATE … WHERE id IN … AND
  sold_online_chosen_at IS NULL AND NOT sold_online`.
- The web switch lives in the package panel under «Προχωρημένες ρυθμίσεις» (card «Πώληση»), saves
  at once with `PATCH {sold_online}`, and is disabled for free packages.
