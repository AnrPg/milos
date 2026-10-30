# ADR-240: Fiscal context, business legal identity and country profiles
Date: 2026-10-29
Status: Accepted

## Context
v3.0.0 (`docs/plans/v3-pilot-ready.md`) makes Palee take real money in the MVP
markets: Greece, Cyprus, the German-speaking countries (DE, AT, CH, LI, LU),
the French-speaking ones (FR, BE, CH, LU, MC), the UK and the USA
(`docs/plans/government-fiscal-integrations.md`). Every one of them needs a
legal document for a sale, and five of them need more: Greece reports every
document to myDATA, France needs an inalterable register (NF525), Germany and
Austria need a signing device when money is taken at a till (TSE, RKSV),
Belgium needs Peppol for B2B invoices from 2026.

What existed: Finance (ADR-126, ADR-190, ADR-222) issues invoices, receipts
and refund receipts with gapless numbers, but an organization has no country,
legal name, tax id, tax office or address, so no document Palee prints is a
legal one, and nothing knows which rules apply where.

## Decision
1. **New bounded context `Palee.Fiscal`** owns what the law asks of a sale:
   the business's legal identity, the country profile, fiscal documents
   (ADR-241), the inalterable journal and period closings (ADR-242), and,
   later, the gateways to tax authorities, signing devices and e-invoicing
   networks (ADR-243, ADR-250, ADR-251). Finance keeps packages, memberships,
   balances and payments, and asks Fiscal for the legal document of a sale.
   Fiscal never reads Finance tables; it receives sale lines.
2. **Business legal identity** (`fiscal_business_identities`, one row per
   organization, tenant scoped, forced RLS): legal name, trade name,
   country, national tax id (ΑΦΜ, SIREN, Steuernummer, UTR, EIN…), VAT
   number (with its country prefix, empty when not VAT registered), tax
   office (ΔΟΥ, Greece only), registration number (ΓΕΜΗ, RCS,
   Handelsregister, Companies House), activity code (ΚΑΔ, NAF, WZ),
   VAT scheme (`standard`, `small_business`, `exempt`), structured address
   (street, number, postal code, city, region: Swiss QR-bill v2.4 accepts only
   structured addresses), contact email and phone, document language,
   currency and branch code (myDATA installation number). Every change is
   written to the journal (ADR-242) with the fields that changed.
3. **Country profiles** (`Fiscal.Domain.CountryProfile`, pure data): for each
   supported country the currency, default document language, tax id and VAT
   number formats, which identity fields are required, the tax authority
   channel (`mydata` or `none`), the register rules (`nf525` or `standard`),
   the till signing device (`tse`, `rksv` or `none`), the B2B e-invoicing
   network (`peppol` or `none`) and the minimum retention in years. A new
   country is a new profile plus adapters, never a change to the domain.
4. **Tax id checks** (`Fiscal.Domain.TaxId`): format per country plus the
   published check digits where they exist (Greek ΑΦΜ, French SIREN and VAT
   key, Belgian enterprise number, German VAT number ISO 7064, Swiss UID).
   Checking that a VAT number is live (VIES, HMRC) is a later port.
5. **API**: `GET /admin/fiscal/identity` (capability `view_finance_reports`)
   returns the identity, the country profile and the list of missing
   fields; `PUT /admin/fiscal/identity` (capability `manage_billing`) saves
   it. `GET /admin/fiscal/countries` lists the supported profiles.

## Rationale
- A separate context keeps the law out of Finance's business rules: Finance
  changes with how gyms sell, Fiscal changes with tax law. Each can be tested
  alone, and new countries do not touch Finance.
- One identity per organization matches how a gym is registered. Per-branch
  codes (Greek υποκατάστημα) are a field, not a second identity.
- Profiles as data keep every country rule in one reviewable place.

## Alternatives Considered
- **Columns on `organizations`**: the organizations table is
  platform-administered and read everywhere; legal identity is tenant data
  with a ten-year retention. Rejected.
- **Free-text address**: Swiss QR-bill v2.4 and Peppol (EN 16931) need
  structured addresses. Rejected.
- **Validating VAT numbers online on save**: VIES is often down and a gym in
  set-up should not be blocked by it. Planned as a background check instead.

## Consequences
- A gym cannot issue fiscal documents until its identity is complete
  (`fiscal_identity_incomplete`).
- Retention: Fiscal data is retained for 10 years, the longest minimum among
  the MVP countries (Germany, Switzerland, Luxembourg, Liechtenstein, Monaco).
- The screens for the identity wait for ANR's choice on mockups (rule of
  2026-10-29); the API ships first.

## Implementation Notes
- Migration `20270201000000_create_fiscal.exs`.
- Profiles: GR, CY, DE, AT, CH, LI, LU, FR, BE, MC, GB, US.
