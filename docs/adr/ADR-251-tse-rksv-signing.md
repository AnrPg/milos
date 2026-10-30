# ADR-251: Till security devices – cloud TSE (DE) and RKSV (AT) through fiskaly
Date: 2026-10-29
Status: Accepted

## Context
Money taken at a till must be signed by a certified security device:
Germany's technical security system (TSE, §146a AO and KassenSichV) and
Austria's signature creation unit (Registrierkassensicherheitsverordnung,
RKSV). Both are available as cloud services; fiskaly offers SIGN DE (a
certified cloud TSE) and SIGN AT (RKSV with a cloud signature creation unit
and FinanzOnline registration). Receipts must print the signature data,
and both laws describe what happens when the device is down: in Germany
the failure is recorded and printed (AEAO zu §146a); in Austria the receipt
carries "Sicherheitseinrichtung ausgefallen".

## Decision
1. **When.** A document is signed when its country profile names a till
   device (`till_device: :tse` DE, `:rksv` AT) and it is a receipt, or a
   credit note of a receipt. Invoices are not till sales and are not signed.
2. **Side table.** Documents stay immutable (ADR-241); the signature lives
   in `fiscal_till_signatures` (transaction and receipt number, signature
   counter, value and algorithm, time format, device and register serials,
   start and end time, QR data) and is exposed as `print` lines for the
   receipt. Special rows (`start`, `null`, `monthly`, `yearly`, `closing`)
   have no document.
3. **Outbox.** States `pending` → `sending` (`FOR UPDATE SKIP LOCKED`) →
   `signed` | `device_failed` | `rejected` | `failed` (20 transient errors) |
   `uncertain`. A claim older than 5 minutes, a timeout or a finish answered
   without a signature makes the row `uncertain`; the next attempt only
   **reads it back** (`lookup`, after 30 s) and signs again only once the
   device says it does not have it. `fiscal_till_signature_attempts` is
   insert-only and logs the request body and answer, never credentials.
4. **Outages.** Germany: a receipt not signed within 5 minutes of its issue
   becomes `device_failed`, is journaled (`till_device_failed`) and prints
   "TSE ausgefallen"; it is not retried (a signature hours later would
   misstate when the sale happened). Austria: when fiskaly reports a unit
   outage (hint "Sicherheitseinrichtung ausgefallen"; the signature is the
   base64 of that text) the row is `device_failed` and prints the marker;
   unsigned AT receipts print it too. Staff can ask for a null receipt
   (Nullbeleg) once the unit is back.
5. **Port and adapters.** `Fiscal.Ports.CashRegisterSecurity`
   (`provision/2`, `sign/2`, `lookup/2`) chosen by `{device, provider}`:
   `Sandbox` (local, deterministic), `FiskalySignDe` (v2: auth; TSS
   create → UNINITIALIZED → admin PIN → INITIALIZED; client; per receipt
   `PUT /tss/{id}/tx/{id}?tx_revision=1` ACTIVE then `=2` FINISHED with the
   `standard_v1` receipt) and `FiskalySignAt` (v1: signature creation unit,
   cash register REGISTERED → INITIALIZED, which signs the start receipt;
   `PUT /cash-register/{id}/receipt/{id}`). Palee chooses the transaction
   ids, so a retry reuses them.
6. **Credentials.** fiskaly key, secret and the generated TSE admin PIN are
   encrypted at rest, never returned, journaled or logged; the export
   policy excludes `api_key`, `api_secret` and `admin_pin`.
7. **Journal.** `till_connection_saved`, `receipt_signed` and
   `till_device_failed` (ADR-242).
8. **Endpoints** (staff; reads `view_finance_reports`, writes
   `manage_billing`): `GET/PUT /fiscal/till-connections/:device`,
   `GET /fiscal/till-signatures`, `GET /fiscal/till-signatures/:id`,
   `POST /fiscal/till-signatures/:id/retry`,
   `POST /fiscal/till-signatures/null-receipts`; documents show
   `till_signature` with its print lines.

## Rationale
A cloud TSE / cloud signature creation unit needs no hardware at the box
and works from any device Palee runs on. Treating every unanswered write as
uncertain and reading it back keeps the signature counter honest: a
transaction signed twice is a gap auditors see.

## Alternatives Considered
- **Hardware TSE (USB/SD) or smart-card RKSV.** Needs a fixed till PC; boxes
  sell from phones and tablets.
- **Signing synchronously while issuing.** Couples issuing to fiskaly's
  availability; the outbox signs within seconds and records outages as the
  law asks.
- **Signing late German receipts anyway.** Rejected: the signature time
  would be wrong; the law asks to record the failure instead.

## Consequences
- AT: registering the cash register with FinanzOnline needs the business's
  FinanzOnline web-service user, which fiskaly asks for; until then the
  register stays in fiskaly's REGISTERED state and Palee's connection in
  `provisioning` with the error shown.
- DE: the TSE must also be notified to the tax office (§146a(4) AO, via ELSTER
  since 2025); this is not automated.
- DSFinV-K export and AT DEP export come from fiskaly's portal, not Palee.
- A failed provisioning may leave an unused TSS/unit at fiskaly; saving again
  with `reprovision` creates new ones.

## Implementation Notes
- The SIGN DE request and response fields were checked against fiskaly's
  published OpenAPI; the SIGN AT receipt schema (rate names STANDARD,
  REDUCED_1 10 %, REDUCED_2 13 %, ZERO, SPECIAL 19 %) is to be confirmed on a
  test account.
- Sources: §146a AO (https://www.gesetze-im-internet.de/ao_1977/__146a.html),
  KassenSichV (https://www.gesetze-im-internet.de/kassensichv/),
  DSFinV-K (https://www.bzst.de/DE/Unternehmen/Aussenpruefungen/DigitaleSchnittstelleFinV/digitaleschnittstellefinv_node.html),
  fiskaly SIGN DE v2 (https://workspace.fiskaly.com/specs/sign-de-v2.json),
  RKSV (https://www.ris.bka.gv.at/GeltendeFassung.wxe?Abfrage=Bundesnormen&Gesetzesnummer=20009390),
  BMF Registrierkassen (https://www.bmf.gv.at/themen/steuern/fuer-unternehmen/registrierkassen.html),
  fiskaly SIGN AT (https://workspace.fiskaly.com/api/rksv/v1/).

## Update 2026-10-29: invoices paid at the till are signed too
Product-owner decision of 2026-10-29, checked against the sources below.

**Rule.** §146a (1) AO asks an electronic recording system with a till
function to record *every* transaction it records ("jeden
aufzeichnungspflichtigen Geschäftsvorfall und anderen Vorgang") and to
protect it with the TSE. A system has a till function as soon as it can
record payments that are at least partly in cash (AEAO zu §146a Nr. 1.2;
the BMF FAQ applies this to invoicing software or an invoicing module that
can record cash payments). DSFinV-K Anhang B, process type `Beleg`: "umfasst
alle Vorgänge, die über die Kasse abgeschlossen werden. Der Vorgangstyp
umfasst neben der Rechnung (§ 14 UStG) auch Gutschriften und
Korrekturrechnungen", with every payment type (cash and non-cash). An
invoice paid at Palee's desk is therefore a till transaction like a
receipt. An invoice paid later by bank transfer or online is not closed at
the till: the BMF FAQ puts only "this part" of a mixed system under §146a,
and DSFinV-K only describes invoices paid later when the till itself
records the claim (`Forderungsentstehung`, settled by a `Beleg` with
`Forderungsaufloesung`). Palee's transfer invoices are issued by its
invoicing, not at the till, so they stay unsigned.

Austria: the cash register duty and RKSV signing apply to every cash sale
(Barumsatz). §131b (1) Z 3 BAO counts payment by debit or credit card and
comparable forms as cash payment, and a later payment by bank transfer or
e-banking is not a cash sale (oesterreich.gv.at / USP "Bargeldgeschäft");
online-shop sales the customer does not pay in cash at the business are
exempt (USP Registrierkassen). Same rule as Germany.

**Decision 1, amended.** A document is signed when its country profile
names a till device and it records money taken at the till
(`TillSigningPolicy.required?/3`):
- a receipt;
- an invoice with `payment_method` `cash` or `card` (desk card payments,
  including the card terminal `card_terminal` of ADR-249, are issued as
  `card`);
- a credit note correcting one of these (it copies the corrected
  document's payment method and is a "Korrekturrechnung" / storno receipt).

Invoices with `bank_transfer`, `online`, `other` or no payment method, and
their credit notes, are not signed. The signature row's kind stays
`receipt` for all of them (DSFinV-K `Beleg`, process type
`Kassenbeleg-V1`, receipt type `RECEIPT`), so the German 5-minute outage
rule applies to till invoices too.

**Printing (ADR-245).** Every signed document, receipt or invoice, prints a
till block next to the authority block in its HTML and PDF template:
title "Technical security system (TSE)" / "Cash register security device
(RKSV)" in the document's language, then the lines of §6 KassenSichV
(TSE serial, till serial, transaction number, signature counter, start and
end, algorithm, time format, signature) or, in Austria, the cash register
id, receipt number and "Sicherheitseinrichtung ausgefallen" when the unit
was out, with the machine-readable code as a QR code (RKSV
Detailspezifikation Z 12; DSFinV-K Anhang I for Germany). Long values wrap
inside the block. A pending German signature prints "Signatur ausstehend"
and a TSE failure "TSE ausgefallen", as before.

**Open points.** `other` payments at the desk (e.g. a voucher) are not
signed on invoices; AEAO Nr. 1.2 counts vouchers accepted instead of money
as till payments, so if boxes use `other` for that it should be mapped to a
till method. Receipts are still signed whatever their method, including
`online` receipts of online payments; whether those should leave the TSE
(online-shop sales are outside §146a / the RKSV) is a separate decision.

**Sources.** AEAO zu §146a Nr. 1.2 (summarised by Bayerisches Landesamt für
Steuern, https://www.lfst.bayern.de/fileadmin/RESSOURCEN/INFORMATIONEN/Steuerinfos/Weitere_Themen/Elektronische_Kassensysteme/2019-06-17-einfuehrung-paragraf-146a-AO_eKassen.pdf),
BMF FAQ on invoicing and inventory systems (quoted in
https://ecovis-kso.com/blog/tse-auch-fuer-warenwirtschaftssystem-und-faktura-system/),
DSFinV-K 2.4 Anhang B (`Beleg`, `AVRechnung`) and Anhang C
(`Forderungsentstehung`, `Forderungsaufloesung`) and the examples of
Anhang H (https://kassensichv.com/downloads/DSFinV-K-Vers-2-4.pdf; official
https://www.bzst.de/DE/Unternehmen/Aussenpruefungen/DigitaleSchnittstelleFinV/digitaleschnittstellefinv_node.html),
fiskaly DSFinV-K process types (https://developer.fiskaly.com/dsfinvk/process_types_business_transaction_types),
§131b BAO (https://www.ris.bka.gv.at/eli/bgbl/1961/194/P131b/NOR40186000),
USP Registrierkassen (https://www.usp.gv.at/steuern-finanzen/steuerliche-rechte-und-pflichten/registrierkassen.html),
USP "Bargeldgeschäft" (https://www.usp.gv.at/services/suchen-und-finden/lexikon/bargeldgeschaeft.html).

## Update 2026-10-29: France (SIGN FR) and shared fiskaly credentials
- France is the third device, `sign_fr`, through fiskaly SIGN FR on the
  Unified API (ADR-266), with the same outbox, side table and endpoints.
- The e-invoicing connection (ADR-250 update) reuses this connection's
  fiskaly key and secret of the same environment when it has none of its
  own. Open: SIGN DE v2 and SIGN AT v1 keys are older per-product keys and
  may not be accepted by the Unified API; a business may then need a
  Unified API key on the e-invoicing connection itself.
