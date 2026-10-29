# ADR-244: Tax categories on what gyms sell, sale lines and the sales tax port
Date: 2026-10-29
Status: Accepted

## Context
ADR-241 issues immutable fiscal documents whose lines carry a tax category
(`standard`, `reduced`, `second_reduced`, `super_reduced`, `special`,
`zero`, `exempt`, `sales_tax`) resolved to a rate by `VatRates` for the
seller's country. What gyms sell (Finance membership packages, Shop
products and variants) did not say which category applies: a Greek gym
selling drinks at 13 %, a German gym under §19 UStG, or a US gym in a
state that taxes memberships all ended up `standard`. The next step
(V3 payments) wires Finance and Shop payments to `Fiscal.issue/4`, so the
mapping from a sale to request lines must exist, be pure and be stable.

US gyms pay state and local sales tax with thousands of rates by ZIP code;
VAT rates do not apply there.

## Decision
1. **Category on what is sold.** `membership_packages`, `shop_products`
   and `shop_variants` get nullable `tax_category` (20) and
   `exemption_reason` (300). A database check allows only known categories
   and requires a reason for `exempt`. The changeset
   (`Fiscal.TaxCategoryChangeset`) trims, checks the category is known and
   requires the reason; the use cases (`Application.Fiscal.SoldItemTax`)
   check the category is one the gym's country offers
   (`VatRates.categories(country)`, `not_available_in_country`). `nil`
   means "the default": a variant inherits its product's category, and
   anything without one is `standard` (`sales_tax` in the US).
   `shop_variants.tax_class` is deprecated: it is back-filled into
   `tax_category` and kept in sync both ways for old clients.
2. **Sale lines (stable API).** `Palee.Fiscal.Domain.SaleLines` is the one
   place that turns a sale into `Fiscal.issue/4` request lines.

   Input of `lines(items, seller)`: `seller` is `%{country_code,
   vat_scheme}`; each item is

   ```
   %{description, quantity \\ 1, unit_price_cents, discount_cents \\ 0,
     tax_category, default_tax_category, exemption_reason,
     default_exemption_reason, rate_bp, source_type, source_id}
   ```

   Output: `{:ok, [%{description, quantity, unit_price_cents,
   discount_cents, tax_category, exemption_reason, rate_bp, source_type,
   source_id}]}` or `{:error, {:invalid_sale_line, index, reason}}` with
   reason `invalid_quantity | invalid_amount | discount_exceeds_amount |
   missing_description | unknown_tax_category | exemption_reason_required`.

   Rules: own category, else the parent's, else the country default; a
   `small_business` seller prints every line `exempt` with its country's
   legal mention (`TaxCategories.small_business_reason/1`, e.g. DE "Gemäß
   § 19 UStG wird keine Umsatzsteuer berechnet (Kleinunternehmerregelung)", FR "TVA non applicable,
   art. 293 B du CGI"); an `exempt` scheme keeps the items' reasons.

   Builders: `package_item/2` (Finance package), `variant_item/3` (Shop
   variant with its product), `shop_order_line_item/2` (priced order line,
   whose `tax_class` is the category snapshot) and `finance_invoice/4`
   (an invoice with its lines and a `taxes` lookup by source id, package
   code or subscription, charge category, default) returning
   `%{currency, prices_include_tax: true, source_type: "finance_invoice",
   source_id, lines}` that the caller completes with `kind`, `issue_date`,
   `buyer`, `payment_method` and `idempotency_key`.
3. **Sales tax port.** `Fiscal.Ports.SalesTaxCalculator.rate(context,
   %{country_code, tax_category, date, region, postal_code})` returns
   `{:ok, rate_bp}`. The default adapter
   `Infrastructure.Fiscal.RateTableSalesTaxCalculator` answers VAT
   categories from `VatRates` and US `sales_tax` from the gym's own table
   `fiscal_sales_tax_rates` (state, optional 5-digit ZIP, `rate_bp`,
   label): a ZIP rate wins over its state's rate; no match is
   `sales_tax_rate_missing`. `Fiscal.Taxes.apply_sales_tax/4` fills
   `rate_bp` of US lines without one, at the gym's address unless a place
   is given.
4. **API.** `tax_category`/`exemption_reason` on package and product/variant
   bodies and responses; `GET /admin/fiscal/tax-categories`,
   `GET|PUT /admin/fiscal/sales-tax-rates` (reads `view_finance_reports`,
   writes `manage_billing`; saving is journaled as `sales_tax_rates_saved`).

## Rationale
The category belongs to the thing sold, the rate to the country and date:
storing categories (not rates) keeps catalogues valid across rate changes
and countries. One pure function shared by Finance, Shop and Payments
means a single place to audit the tax rules, and it can be unit-tested
without a database. A port for sales tax keeps the door open for Stripe
Tax, Avalara or TaxJar without touching callers.

## Alternatives Considered
- **Rate on the product.** Simple, but rates change (e.g. CH 2024) and gyms
  in several countries would need several products. Rejected.
- **External sales tax API now** (Stripe Tax, TaxJar, Avalara). Accurate
  rooftop rates, but a paid dependency and a network call at checkout
  before any US pilot exists. The manual table is enough for a single
  location gym and the port allows the swap.
- **Category only on variants.** Products without variants (and packages)
  would still need one; inheritance from the product covers both.

## Consequences
- Payments must call `SaleLines` (then `Taxes.apply_sales_tax/4` for US
  gyms) before `Fiscal.issue/4`; it never wires documents itself.
- US prices are treated as the price charged including tax
  (`prices_include_tax: true`) like everywhere else; US gyms usually quote
  net prices. Open question for the product owner.
- A gym changing country may hold categories its new country does not
  offer; issuing then fails with `unknown_tax_category` until fixed.

## Implementation Notes
- Migration `20270203000000_tax_categories_and_accounting_exports` adds the
  columns, back-fills variants from `tax_class` (legacy exempt rows get the
  reason "exempt", to be reviewed), and creates the tenant tables
  `fiscal_sales_tax_rates` and `fiscal_export_settings` (forced RLS and the
  `palee_apply_tenant_context` trigger).
- Sources: Stripe Tax and TaxJar rate APIs were reviewed for the port's
  shape (https://docs.stripe.com/tax/calculating,
  https://developers.taxjar.com/api/reference/#rates).
