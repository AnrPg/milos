# UBL 2.1 schemas (ADR-250)

Official OASIS UBL 2.1 schemas (OASIS Standard, 4 November 2013), copied
unchanged from https://docs.oasis-open.org/ubl/os-UBL-2.1/UBL-2.1.zip
(`xsd/common/*` and the `Invoice` and `CreditNote` main documents). Peppol
BIS Billing 3.0 uses UBL 2.1. Tests validate every generated invoice and
credit note against `maindoc/UBL-Invoice-2.1.xsd` and
`maindoc/UBL-CreditNote-2.1.xsd` with `xmllint`; the business rules of
EN 16931 and Peppol BIS (Schematron) that Palee's documents touch are
checked by `test/support/peppol_bis_rules.ex`.
