# Shop (e-shop + desk sale) and partner perks: proposal

Date: 2026-10-23 · Status: proposal, mockup stage (no production code)
Mockup: [`mockups/palee-shop-perks-mockup.html`](mockups/palee-shop-perks-mockup.html), which you can click through: console screens, member phone screens, alternatives, cited research.
Backend is being built in parallel: catalogue, inventory and orders in **ADR-190** (branch `…-shop-api`), partner perks in **ADR-191** (`…-perks-api`), and shop analytics in **ADR-192** (`…-shop-analytics`). Where this sketch and those ADRs differ, the ADRs win.
Follows the [product brief](2026-10-15-palee-product-vision-and-ia.md). Its §4 principles win wherever this proposal conflicts with them.

## 1. What we are building

- **Shop (priority).** A gym or independent coach sells physical products (apparel, supplements, accessories) to its members. Members order in the app and collect at the box. They pay at pickup in the MVP, and online later. Staff also sell at the front desk ("Ταμείο"). Every sale is a Finance invoice and shows in the member's `Εγώ › Πληρωμές › Συναλλαγές`.
- **Partner perks.** The owner publishes offers from partner businesses for the box's members, e.g. "−10% at Nutri Store with code ΚΥΨΕΛΗ10" or a coach's own code for their PT clients. Members find them in `Εγώ › Πληρωμές › Προσφορές`. This is **not a marketplace**: only the box's own members see these perks, and they never appear in `Γύρω μου` (brief §1, §5.2).

## 2. IA decision

| Surface | Decision | Why |
|---|---|---|
| Console: shop | Its own top-level section **«Κατάστημα»** with full-grid segments **Προϊόντα · Παραγγελίες · Απόθεμα**. **Ταμείο** (desk sale) and **+ Νέο προϊόν** sit in the header. Empty state is a 3-step checklist. | The shop has daily jobs of its own: preparing orders and keeping stock. Finance already has 8–9 tabs. «Εξοπλισμός» (ADR-104) tracks cost (machines, consumables) and the shop tracks revenue. Front desk should be able to prepare and hand over an order without Finance access. |
| Console: shop analytics | A 4th segment **Αναλυτικά**: sales over time (weekly bars, net of discounts and refunds), top products with units, revenue and margin, app vs desk, by branch, stock value at cost plus low stock, and **attribution** (code used → post or perk the product was opened from within 7 days → Box card → none). Every number drills down to its order lines. | The owner asked for the shop's own reports. They sit next to the data they explain, which keeps them out of the already-long Αναφορές. |
| Console: finance | `Οικονομικά › Επισκόπηση` splits revenue **by stream**: Συνδρομές · Πακέτα PT/υπηρεσίες · Events/σεζόν · **Κατάστημα**. The stream comes from the invoice line's source (`line_type`), never from its text. Shop rows link to the order and the product. A **reconciliation card** checks orders = invoices, every sale has a stock movement, and flags manual «Προϊόν» charges with no product. | Distinct lineage and observability: shop money is traceable from the KPI down to the line, order, variant and stock movement. |
| Console: advertising | No new campaign system. A **«Προώθηση»** action on a product opens the existing tools prefilled: (a) a club post in `#ανακοινώσεις` with the product card attached, (b) a product-scoped discount code in `Οικονομικά › Προσφορές`. A "Νέο" label appears automatically for 14 days. | Reuses the promotions (`promotion_campaigns/codes`) and posts already built. One place per object (principle 1). |
| Console: perks | **`Οικονομικά › Προσφορές`**, with a segment **Του box · Συνεργατών**. | Uses the same word as the member side (`Πληρωμές › Προσφορές`). All discounts live in one place. It adds no tab, and a box without a shop can still publish a perk. |
| Member: shop | **`Box › Κατάστημα`**: a fixed card below Συνδρομή (4 thumbnails, "2 νέα"). The action row stays 4 items. The card is absent for everyone while the shop is closed. A ready order shows as a fixed link at the top of the shop. | Buying from the box is part of the service relationship (Box), not the social space (principle 6). Slots are fixed (principle 2). The bottom bar does not change. |
| Member: discovery | Club posts can carry a product card that links to `Box › Κατάστημα` (a reference, not a second home). | Principle 1. Matches how events and WODs appear in the feed. |
| Member: orders/money | The order lives in Box › Κατάστημα. Its invoice and payment appear in `Εγώ › Πληρωμές › Συναλλαγές`. Desk sales land in the same place. | One money history (the member-billing work). |
| Member: perks | `Εγώ › Πληρωμές › Προσφορές`, in a section «Από συνεργάτες του box» above the used offers, seasons and referral rewards. A perk opens a page with the code, **Αντιγραφή**, **Δείξε QR**, terms, address and a «Συνεργασία» disclosure. | This is the segment the billing page already reserves (`perks: []`, flag off). |
| Check-in desk | When a member with a ready order checks in, the desk shows "έχει παραγγελία έτοιμη · Παράδοση". | The door already identifies the member. Pickup costs zero extra steps. |

Alternatives that were weighed (each shown in the mockup, with A recommended): the shop as Finance tabs; a 5th Box action; online card payment now; perks under Κατάστημα › Συνεργάτες; personal single-use perk codes.

## 3. Flows (MVP)

1. **Create product.** Photos (square), name, description, category, price incl. VAT, optional cost. Up to **2 options** (e.g. size × colour), with stock per combination and an optional per-variant price. Settings: published toggle (new = draft); "Ποιοι αγοράζουν": **Μόνο μέλη | Και επισκέπτες** (visitors = any Palee account, via the public box page); channels **App / Ταμείο**; member package discount applies (ADR-097 `member_discount_percent` on `charge_category: product`); optional per-person limit; pickup point(s). Archive, never delete.
2. **Member buys.** Shop grid → product (every size visible, sold-out ones struck through with "Ειδοποίησέ με") → cart and checkout on **one screen with zero typed fields**. The member chooses a pickup point if there are several, a payment mode (**Στην παραλαβή**, or **Στον λογαριασμό μου** if the owner allows it), and can open "Έχεις κωδικό;" behind a link. Placing the order reserves stock and creates the invoice with an open balance.
3. **Staff fulfil.** `Παραγγελίες`: Για ετοιμασία → **Έτοιμη για παραλαβή** (push to the member, with where and when) → **Παραδόθηκε**, recording the payment (cash, card at terminal, on account). Reminder on day 3. Auto-cancel after 7 days (setting), which releases the stock. **Refund** issues the existing refund receipt and asks whether the item goes back to stock.
4. **Desk sale (Ταμείο).** Favourites tiles (+ search/barcode) → variant quick-pick → member attached (search by name or phone; the member who just checked in is suggested; "Πελάτης χωρίς λογαριασμό" for walk-ins) → payment chips → **Χρέωση**. If stock is short it warns but does not block. An open order for the same member is surfaced in the cart.
5. **Stock.** Movements: receive, recount, damage, return, sale, reserve and release. Status uses **days of stock left** (`StockPolicy` from ADR-104: critical < 7, low < 21, optional reorder level). Alerts fire only when the status worsens, and stock goes into the existing 07:07 daily digest.
6. **Partner perk.** Partner (name, type, address or site, logo) → offer (percentage, amount or gift; what it covers; terms) → redemption (**one shared code + QR** in the MVP) → audience (**all members | specific packages**, which lets a coach give a code only to PT clients) → validity (themed date pickers) → disclosure toggle "the box benefits" (shows «Συνεργασία») → optional announcement post → publish. The list shows **reveals** (members who opened the code) and **uses** (member "Το χρησιμοποίησα" self-reports plus a monthly tally entered from the partner).

## 4. Data model sketch

New bounded context **`Shop`**. Everything is tenant-scoped with forced RLS and composite `(id, organization_id)` FKs, like ADR-104. Money stays in **Finance**.

```
shop_products         id, organization_id, title, description, category, status (draft|active|archived),
                      audience (members|everyone), sell_in_app bool, sell_at_desk bool,
                      member_discount_applies bool, per_person_limit int?, all_locations bool, location_ids[],
                      photos [media refs], unit_cost_cents?, price_cents, published_at, position
shop_product_options  id, product_id, position (1..2), name, values[]
shop_variants         id, product_id, option_values {name: value}, sku?, barcode?, price_cents? (override),
                      on_hand int, reserved int, reorder_level int?, stock_status (ok|low|critical|out), archived
shop_stock_movements  id, variant_id, kind (receive|recount|damage|return|sale|reserve|release), delta int,
                      unit_cost_cents?, order_line_id?, note, actor_id, occurred_at   -- append-only; on_hand derives from it
shop_orders           id, number (K-1042), buyer_user_id? (null = walk-in), channel (app|desk),
                      status (placed|ready|picked_up|cancelled), payment_mode (at_pickup|on_account|online),
                      pickup_location_id, finance_invoice_id, ready_at, picked_up_at, cancelled_at, cancel_reason,
                      expires_at, handled_by_id
shop_order_lines      id, order_id, variant_id, title_snapshot, variant_snapshot, quantity, unit_amount_cents,
                      discount_cents, total_cents, finance_invoice_line_id, refunded_quantity
```

Finance reuse (no new money tables):
- An order or desk sale creates a `finance_invoice`. Each line is a `finance_invoice_line` with `line_type: "shop_item"`, `charge_category: "product"` and the package `member_discount_percent` (ADR-097).
- Payment: `membership_payment` (cash, card_manual, bank_transfer, other). Online payment arrives with the gateway.
- Refund: `finance_refund_receipt` + `finance_payment_reversal`. Restocking is a separate `return` movement.
- Product discount codes: the existing `promotion_campaigns` / `promotion_codes`, with a scope in `params` (`{"scope": "shop", "product_ids": [...]}`). Redemption goes through `promotion_redemptions`.

Perks (Finance › Προσφορές, a new kind next to promotions):
```
partner_perks         id, organization_id, partner_name, partner_category, partner_address?, partner_url?, logo,
                      offer_kind (percent|amount|gift), offer_value?, offer_text, terms,
                      code_mode (shared|personal), shared_code?, show_qr bool,
                      starts_on, ends_on?, audience (all_members|packages), package_ids[], all_locations, location_ids[],
                      box_benefits bool (disclosure), status (draft|active|paused|ended), announce_post_id?
partner_perk_reveals  perk_id, user_id, first_revealed_at, last_revealed_at, reveal_count
partner_perk_uses     id, perk_id, user_id?, source (member_report|partner_tally|partner_check), quantity, occurred_on
partner_perk_codes    perk_id, user_id, code, used_at?            -- later, personal codes only
```
The member billing read model (`MyBilling`) fills its existing `perks` list from `partner_perks` that are active and visible to that member.

Rights: a new `manage_shop` capability (owner, admin, front desk) for products, stock and orders. `take_payments` is needed to record a payment or run the Ταμείο. Coaches may get read-only stock (as with `report_inventory`). Perks follow the promotions rights.

### Analytics and lineage (ADR-192)

- **Lineage chain:** `finance_invoice_line (line_type: shop_item, source_type: shop_order_line, source_id)` → `shop_order_line` → `shop_variant` → `shop_product`, plus `shop_stock_movement.order_line_id`. Refunds come from `finance_refund_receipt` lines tied to the same order line. Revenue is counted from Finance (paid and refunded amounts). Units and margin come from the Shop tables. Margin is shown only where a unit cost exists, with that coverage stated (e.g. "6/7 προϊόντα"). A missing cost is never counted as 100% margin.
- **Attribution:** `shop_orders.attribution {kind: code|post|perk|box_card|none, id}`, set at placement. The rule: code used, else the last post or perk the product page was opened from within 7 days, else the Box card. Desk sales are `none`.
- **Observability:** a daily reconciliation job counts orders without an invoice, invoice lines with `shop_item` and no order line, sales without a stock movement, and manual `charge_category: product` charges with no product. The counts show on the Finance overview card and go into the inventory digest when non-zero. Shop events (`shop.order_placed|ready|picked_up|cancelled|refunded`, `shop.stock_status_changed`) are emitted for metrics.
- **Read model:** per-day rollups `shop_sales_daily (organization_id, location_id, channel, product_id, variant_id, units, gross_cents, discount_cents, refund_cents, cost_cents)` feed the charts. The drill-down reads the source rows.

## 5. MVP vs later

**MVP:** products with ≤2 options and per-variant stock; draft/published; members-only or everyone; Box › Κατάστημα; one-screen checkout with pickup and pay-at-pickup (plus on-account if enabled); the order lifecycle with push, reminder, auto-cancel and refund; the Ταμείο; stock movements with days-left status, alerts and the digest; Προώθηση (post + product code); partner perks with a shared code + QR, reveals and reported uses; the check-in desk pickup hint; Κατάστημα › Αναλυτικά and the shop stream in the Finance overview, with drill-down and the reconciliation card.

**Later:** online card payment (with the payment provider); apparel pre-orders with a close date; a product as a gift inside a package or season; personal perk codes plus a no-login partner check page; courier delivery; sales, cost and margin reports in Αναφορές; "notify me when back in stock" (in the mockup the UI only shows the entry).

## 6. Open questions

1. **Legal receipt for goods.** Greek retail sales need a receipt that goes through myDATA and is tied to the shop's card terminal and cash register. Does Palee's invoice serve as that receipt (via an e-invoicing provider), or does the gym keep issuing it from its own register while Palee only records the sale? This decides whether the MVP Ταμείο can be the gym's only till.
2. **Payment provider timing.** Online card payment for shop orders should ship together with online membership renewals rather than separately. Which provider, and when?
3. **Auto-cancel default.** 7 days for unpicked orders, with a reminder on day 3: does that suit gyms, or should it be per product (supplements vs apparel)?
