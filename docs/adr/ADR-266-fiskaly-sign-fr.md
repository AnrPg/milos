# ADR-266: French till receipts signed through fiskaly SIGN FR, next to Palee's own journal
Date: 2026-10-29
Status: Accepted

## Context
France asks every cash register system (logiciel ou système de caisse) to
keep sales data inalterable, secured, kept and archived (ISCA conditions,
CGI art. 286 I 3° bis, BOI-TVA-DECLA-30-10-30). Since the 2026 finance law
(loi 2026-103) a publisher may again prove this either with a certificate
(NF525 from Infocert, or LNE) or with its own attestation. Palee already
meets the conditions with its own NF525-style journal: immutable documents
(ADR-241) and a hash-chained, signed journal with period closings and an
audit archive (ADR-242).

The product owner decided on 2026-10-29 that fiskaly is the single vendor
for fiscal work outside Greece (ADR-250 update, ADR-251). fiskaly SIGN FR
(Unified API `2026-06-01`) signs, journals and archives French till
transactions in fiskaly's cloud and holds the certification for that part,
so Palee does not have to carry an NF525 certificate or sign its own
attestation for every French box alone.

## Decision
1. **Third device.** France's country profile names the till device
   `:sign_fr`. Receipts and credit notes of receipts are signed exactly like
   TSE (DE) and RKSV (AT) receipts: same outbox, side table
   (`fiscal_till_signatures`), attempts log, uncertain handling and
   endpoints (`/fiscal/till-connections/sign_fr`), behind the
   `CashRegisterSecurity` port of ADR-251. Invoices are not till sales and
   are not signed (as in DE/AT).
2. **Adapter.** `Palee.Infrastructure.Fiscal.FiskalySignFr` on the shared
   Unified API client `FiskalyUnified` (ADR-250 update).
   - *Provision* (saving the connection): `POST /taxpayers` (type `COMPANY`,
     fiscalization `FR` with the SIREN taken from the identity's
     registration number or tax id, 9 or 14 digits; credentials type from
     config, `SELF_ATTESTATION` by default) and commission it; `POST
     /locations` (`BRANCH`, label = SIRET) and commission it; `POST /systems`
     (`FISCAL_DEVICE`, producer `PALEE`, software Palee and its version) and
     commission it. The taxpayer id is stored as the unit serial and the
     system id as the register serial. A business without a SIREN is refused
     (`siren_missing`).
   - *Sign*: an `INTENTION` record, then a `TRANSACTION` record of type
     `RECEIPT` (entries, VAT breakdown with the System's VAT codes, payments
     `CASH` / `ONLINE`), or a `CORRECTION` pointing at the original receipt's
     fiskaly record for a credit note (it waits, as a transient error, until
     the original is signed).
     The answer's `compliance.sequence` (number, signature) and `journal`
     (signature, signed_at) are stored as the signature; the receipt prints
     "N° séquence fiskaly" and a shortened "Signature".
   - *Lookup*: replays the same requests (same idempotency keys) and reads
     the record back, so an uncertain row is never signed twice.
   - Every POST and PATCH carries a UUID v3 `X-Idempotency-Key` derived from
     `sign_fr:<receipt>` (or `sign_fr:<register>:taxpayer` and so on).
3. **Outages.** As in Austria, a receipt fiskaly cannot reach stays queued
   and is retried; one sent 5 minutes or more after its issue goes as
   `offline` (`document.offline` with reason and the receipt number as
   reference) so fiskaly journals it as issued during an outage. Until it is
   signed the receipt prints "Enregistrement fiskaly en attente". The sale
   itself is already secured in Palee's journal the moment it is issued.
4. **Two chains, one truth.** Palee's journal (ADR-241/242) stays the
   internal audit chain for every country, France included: it is what the
   audit archive exports, what period closings and the perpetual grand total
   are computed from, and what Palee's own integrity checks verify. fiskaly
   SIGN FR is the external, certified copy of the till part: it holds the
   signed sequence, its own journal and the archive a French tax inspector
   can ask fiskaly for. Each signature row links the two (document id on
   Palee's side, fiskaly record id on fiskaly's side), and
   `till_connection_saved`, `receipt_signed` are journaled by Palee as for
   DE/AT. Neither replaces the other: if they ever disagree, Palee's journal
   is the source and the difference is a support case.
5. **Credentials.** The fiskaly key and secret of the business (the same
   ones as for e-invoicing, ADR-250 update) are stored encrypted on the till
   connection, never returned, journaled or logged.
6. **Monaco.** Monaco keeps `till_device: :none`: SIGN FR fiscalizes
   taxpayers by SIREN and SIRET, which Monegasque businesses do not have, and
   fiskaly does not list Monaco. Monegasque boxes rely on Palee's journal
   alone until fiskaly says otherwise.

## Rationale
- One vendor for DE, AT and FR till security and for e-invoicing: one
  contract, one set of credentials per business, one client in the code.
- Keeping Palee's own journal means nothing changes for audit archives,
  closings or Greek/German/Swiss record keeping, and France gets a second,
  certified chain instead of a migration.
- Reusing the ADR-251 outbox gives France the same never-sign-twice rules
  as Germany and Austria without new tables (the migration only widens the
  allowed device values).

## Alternatives Considered
- **Palee's own NF525 certification or self-attestation only.** Possible
  since loi 2026-103, but Palee would carry the legal statement and any
  certification audit itself for every French box. Kept as the fallback if
  fiskaly cannot confirm coverage.
- **Another French vendor.** Rejected by the single-vendor decision.
- **Signing invoices too.** Not required for B2B invoices outside the till;
  French B2B e-invoicing is a separate track (ADR-250 update; fiskaly
  E-INVOICE France is announced).

## Consequences
- **Before the first French box:** fiskaly must confirm in writing that SIGN
  FR covers the certification requirement for Palee as the cash register
  software publisher (an NF525/LNE certificate, or the attestation route of
  loi 2026-103), and which `credentials` type (`LNE`, `INFOCERT`,
  `SELF_ATTESTATION`) Palee must send for the taxpayer. Until then the
  default `SELF_ATTESTATION` is a placeholder in config
  (`:palee, :fiskaly_sign_fr, credentials:`).
- French businesses need a SIREN/SIRET in their fiscal identity and a fiskaly
  account with a Unified API key of their unit.
- The receipt texts are French and fixed; the staff screens follow
  ontology §4.16 ("fiskaly SIGN FR").

## Implementation Notes
- Migration `20270222000000_fiskaly_einvoice_and_sign_fr.exs` allows device
  `sign_fr` on `fiscal_till_connections` and `fiscal_till_signatures`.
- `Palee.Fiscal.Domain.SignFrReceipt` builds the device-neutral schema the
  adapter sends (and the attempts log keeps); credentials never reach it.
- `SandboxCashRegisterSecurity` signs `sign_fr` receipts locally for the
  sandbox environment.
- Tests: `test/palee/fiscal/till_signing_test.exs` ("France (SIGN FR)":
  sandbox, credit note, stubbed fiskaly provisioning and signing with
  `Req.Test`, late receipt flagged offline, no credentials in attempts).
- Sources: fiskaly SIGN FR OpenAPI
  (https://workspace.fiskaly.com/specs/fiskaly.uapi.sign-fr.2026-06-01.yaml),
  Postman collection
  (https://workspace.fiskaly.com/static/postman/UAPI_2026-06-01/fiskaly_sign_fr_2026-06-01_postman_collection.json),
  BOI-TVA-DECLA-30-10-30 and CGI art. 286 I 3° bis (as cited in ADR-242).
