# ADR-190: E-shop: catalog, inventory, orders and revenue lineage
Date: 2026-10-23
Status: Accepted

## Context
Gyms and coaches sell products (chalk, apparel, supplements, gear) at the
front desk and want members to buy them in the app for pickup. TD-189
recorded the owner's ask: a catalog with stock, selling at the desk (POS) and
in-app, and the purchases shown in the member's billing. The owner asked
that products can be created, published, managed, stocked and advertised,
and that shop sales count towards analytics and financials "with a distinct
lineage and observability".

What existed:

- **Finance** (ADR-126, ADR-153) owns invoices, invoice lines, payments
  (`membership_payments`), reversals and refund receipts. Every money row
  hung off a membership; nothing told a membership payment from any other
  kind of income.
- **Inventory** (ADR-104) tracks gym equipment and consumables with
  `StockPolicy` thresholds (critical under 7 days of cover, low under 21).
  It is not a retail catalog: no prices, variants or sales.
- **Branches** (ADR-186): staff may be scoped to branches; covering items are
  valid at every branch or at listed ones.
- **Demo businesses** (ADR-184) must not take money from real people
  (`GoLive.check_payment`).
- **Media** (ADR-148): purpose-scoped uploads with an orphan sweep.
- **Community posts** carry typed attachments (event, workout, …).

## Decision

### 1. A Shop context; money stays in Finance
`Palee.Shop` (facade) with pure domain modules under `Palee.Shop.Domain`
(`ProductPolicy`, `OrderLifecycle`, `OrderPricing`, `StockLedger`,
`StockStatus`, `PromotionPolicy`, `PickupCode`, `RevenueLineage`), a
`ShopStore` port with `EctoShopStore` (all through `RepoContext.run`), a
`PaymentProvider` port with `MockPaymentProvider`, and a `ShopNotifier` port
with a notifications adapter. Use cases live in `Palee.Application.Shop.*`
(`ManageCatalog`, `ManageStock`, `Checkout`, `Fulfilment`, `MemberShop`,
`PromoteProduct`, `ProductCards`, `ProductMedia`, `OrderMoney`,
`Observability`).

The shop never stores money of its own. An order's invoice, its lines,
payments, reversals and refund receipts are Finance rows.

### 2. Tables (all tenant scoped, forced RLS, composite `(id, organization_id)` FKs)
| Table | What it holds |
|---|---|
| `shop_products` | title, description, category, `media_ids`, up to two options (size × colour), status `draft → published → archived`, visibility `members_only | public`, `sell_in_app`, `sell_at_desk`, `member_discount_applies`, `per_person_limit`, branch coverage (`all_locations` / `location_ids`) |
| `shop_variants` | option values, SKU, barcode, `price_cents`, `compare_at_price_cents`, `cost_price_cents`, `tax_class` (a label), `track_inventory`, `low_stock_threshold`, cached `stock_status` (`ok | low | critical | out`), archived_at |
| `shop_stock_movements` | append-only ledger per variant and branch: `receive`, `sale`, `refund_restock`, `adjustment` (with a reason), `transfer`, `reserve`, `release`; actor, order and note |
| `shop_stock_levels` | the projection (on hand, reserved) per variant and branch, updated in the same transaction as the movement under a row lock |
| `shop_orders` | number (per business, advisory lock), `channel` (`online | pos`), `status` (`placed → ready_for_pickup → picked_up`, or `cancelled`), `payment_status` (`pending_payment | paid | partially_refunded | refunded | void`), `payment_mode`, `source` + `source_ref_id` (attribution), pickup branch, buyer (`user_id`, `membership_id`) or walk-in `customer_name`, paid and refunded cents, `pickup_code`, `expires_at`, `reminded_at`, `fiscal_receipt_ref`, `promotion_code_id`, idempotency key |
| `shop_order_lines` | variant, title and option snapshot, quantity, unit and discount cents |
| `shop_promotion_codes` | a code for one product (percent XOR fixed amount), window, redemption cap, the post that advertises it |
| `shop_stock_alerts` | «Ειδοποίησέ με»: a member waits for a sold-out variant; `notified_at` |

Migrations `20261211000000`–`20261211500000`. Every table is classified in
the tenancy audit and in `Shop.Domain.TenantDataPolicy` (retained with
Finance, 10 years, since orders are the source documents of shop revenue).

### 3. Revenue lineage
Migration `20261211000000` adds `revenue_stream`
(`membership | package | event | shop | other`, default `membership`) to
`finance_invoices`, `finance_invoice_lines`, `membership_payments`,
`finance_payment_reversals` and (`20261211200000`) `finance_refund_receipts`,
plus `source_type` / `source_id` on lines, payments and reversals.

- An order's invoice is `shop`; each line is `shop_item` with
  `source_type = 'shop_order_line'`; each payment points at the order
  (`source_type = 'shop_order'`).
- A reversal inherits stream and source from the payment it reverses, and a
  refund receipt from its reversal, by `BEFORE INSERT` triggers, so a refund
  keeps the lineage whatever path records it.
- Walk-in sales have no membership: `membership_id` / `user_id` became
  nullable on those rows, with checks that allow the gap for `shop` only.
- `finance_invoices.fiscal_receipt_ref` holds the legal receipt reference
  (myDATA MARK or the register's number) when staff record one.
- `GET /staff/shop/orders/:id/lineage` walks order → invoice → lines →
  payments → reversals; `GET /staff/shop/revenue-streams` totals by stream.
  Reporting (refining `membership` into package/event/other) is ADR-192.

### 4. Ordering, stock and payment
- **Online** (`Checkout.place_online`): one transaction prices the cart from
  the catalog, writes the order and lines, `reserve` movements at the pickup
  branch (refused when short: never oversold), redeems a promotion code
  under its row lock, and opens the invoice. Payment is at pickup, on
  account, or `online` through the payment port. The mock reports online
  card payments unavailable, so `online` is refused with
  `online_payment_unavailable` until a vendor is wired.
- **Desk sale** (`Checkout.desk_sale`): order `picked_up` on the spot,
  `sale` movements, invoice and payment (cash, card at the terminal,
  transfer, other), to a member or a walk-in.
- Both are idempotent by `idempotency_key`.
- Unpaid online holds expire after seven days (`ShopOrderSweepJob`, hourly):
  the reservation is released and the buyer told; orders ready for 24 hours
  get one pickup reminder carrying the pickup code.
- Refunds are Finance reversals of the order's payments, with optional
  `refund_restock` movements.
- Members see shop invoices and payments through
  `MemberShop.billing_transactions(context, user_id)`
  (`GET /me/shop/transactions`), the facade member billing calls.

### 5. Pricing, discounts and promotion
- The member discount (the package's percent) applies to products marked
  `member_discount_applies`. A promotion code (`shop_promotion_codes`) never
  stacks with it: each line takes the larger discount. The cart preview
  names both.
- «Προώθηση» (`POST /staff/shop/products/:id/promote`) writes a code (new or
  existing) and a community post with a `product` attachment, to
  announcements, a member group or PT squad channel, or the public feed, in
  one transaction. Feeds render the attachment as a product card with a buy
  link that carries `source = club_post`, the post id and the code, so the
  order is attributed.
- A price change emits `shop_variant_price_changed` with before and after.

### 6. Access, branches and demo gating
- Capabilities `manage_shop` (catalog, stock, promotion, refunds) and
  `sell_shop` (desk sale, pickup, payment, the ready-order check at
  check-in). Branch-scoped staff see and act on their branches only
  (`LocationScopePolicy`); products cover branches like ADR-186 §8 items.
- A demo business can build a catalog but publishing for members and taking
  money from real people are gated by `GoLive`.

### 7. Observability
Every order transition, stock movement, stock status change and catalog
change emits a `[:palee, :shop, …]` telemetry event (bounded labels), an
audit analytics event (`shop_*` in `EventCatalog`) and a structured log line
with `organization_id`, `shop_event`, `order_id`, `product_id`,
`variant_id`, `channel` and `amount_cents` metadata.

## Rationale
- Keeping money in Finance means one ledger, one export and one set of
  refund rules; the shop adds a stream and a source instead of a parallel
  payments table.
- A stored stream plus source ids make lineage a query, not text parsing,
  and triggers keep reversals honest even for writers that predate the shop.
- An append-only movement ledger with a locked projection gives an audit
  trail and prevents overselling without a separate reservation service.
- A payment port with a mock lets the full flow ship before a card vendor is
  chosen.

## Alternatives Considered
- **Extend Inventory (ADR-104) into retail.** Rejected: equipment tracking
  has no prices, variants, orders or member visibility, and mixing them
  would complicate both.
- **A shop-owned payments table.** Rejected: it would split revenue
  reporting, exports and refunds across two ledgers.
- **Deriving the stream from line text or package type only.** Rejected for
  storage (fragile, unindexed); ADR-192 still refines the `membership`
  default at read time.
- **Stacking promotion and member discounts.** Rejected: margins on retail
  products are thin and the larger of the two is easy to explain.

## Consequences
- Finance rows may now lack a membership (shop walk-ins); any code that
  assumed `membership_id` is present must check the stream.
- Shop orders, lines and stock alerts are retained with Finance; stock
  alerts holding `user_id` for ten years is a known gap (TD-202).
- Follow-up work is tracked in TD-190 and TD-196–TD-203: fiscal receipts and
  tax, a real payment provider, delivery, reviews, bundles, gift cards,
  visitor ordering and a server cart.

## Implementation Notes
- Staff routes live under `/api/org/:slug/staff/shop` (like inventory, so
  the front desk is admitted), not `/admin/shop`; the console's base path
  must point there.
- Product photos use the media purpose `shop_product_photo` (public bucket,
  8 MB) and are marked attached so the orphan sweep keeps them; product JSON
  carries resolved URLs.
- Pickup codes are six characters from an unambiguous alphabet, drawn under
  the order-number advisory lock; staff may type them in any case with
  spaces or dashes.
- Concurrency (stock rows, promotion caps, order numbers) relies on row and
  advisory locks; the Ecto sandbox cannot exercise real parallel
  transactions, so tests cover the sequential refusals.
- The `member_discount` rule shown in the cart comes from the package; the
  member-billing branch reads shop rows only through the facade above.
