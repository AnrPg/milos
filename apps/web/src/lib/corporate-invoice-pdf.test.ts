import { describe, expect, it } from "vitest";

import type { CorporateInvoiceDocument } from "@/api/payment-models";

import { buildCorporateInvoiceLayout, type CorporateInvoicePdfLabels } from "./corporate-invoice-pdf";

const labels: CorporateInvoicePdfLabels = {
  invoice: "Invoice",
  billTo: "Bill to",
  contact: "Contact",
  email: "Email",
  issuedOn: "Issued",
  dueOn: "Due",
  period: "Period",
  status: "Status",
  description: "Description",
  quantity: "Seats",
  unitPrice: "Price",
  amount: "Amount",
  seatLine: "Corporate seats",
  total: "Total",
  paid: "Paid",
  balanceDue: "Balance due",
  payments: "Payments",
  reference: "Ref",
  footer: "Thank you",
  statuses: { issued: "Issued", overdue: "Overdue", paid: "Paid", void: "Void" },
  methods: { cash: "Cash", bank_transfer: "Bank transfer", card_manual: "Card", other: "Other" },
};

function invoice(overrides: Partial<CorporateInvoiceDocument> = {}): CorporateInvoiceDocument {
  return {
    id: "8f0c2d4e-0000-0000-0000-000000000000",
    corporate_client_id: "c1",
    invoice_number: "INV-000123-CORP-1",
    issued_on: "2026-10-01",
    due_on: "2026-10-15",
    period_start: "2026-10-01",
    period_end: "2026-10-31",
    seats_billed: 4,
    unit_price_cents: 5000,
    total_cents: 20000,
    paid_cents: 5000,
    balance_cents: 15000,
    status: "overdue",
    payments: [
      { id: "p1", amount_cents: 5000, payment_method: "bank_transfer", paid_on: "2026-10-05", reference: "TX-1" },
      { id: "p2", amount_cents: 1000, payment_method: "cash", paid_on: "2026-10-06", reversed_at: "2026-10-07T00:00:00Z" },
    ],
    client: {
      id: "c1",
      membership_package_id: "pkg",
      company_name: "Ακμή Α.Ε.",
      contact_name: "Μαρία",
      billing_email: "billing@akmi.gr",
      enrollment_code: "ABC",
      active_seats: 4,
      status: "active",
      package_name: "Corporate Gold",
    },
    issuer: { name: "Milos Gym" },
    ...overrides,
  } as CorporateInvoiceDocument;
}

describe("buildCorporateInvoiceLayout", () => {
  it("lays out header, bill-to, line and totals", () => {
    const layout = buildCorporateInvoiceLayout(invoice(), labels, "en-GB");
    expect(layout.issuer).toBe("Milos Gym");
    expect(layout.title).toBe("Invoice INV-000123-CORP-1");
    expect(layout.status).toBe("Status: Overdue");
    expect(layout.billTo).toEqual(["Ακμή Α.Ε.", "Contact: Μαρία", "Email: billing@akmi.gr"]);
    expect(layout.meta[0]).toEqual(["Issued", "1 Oct 2026"]);
    expect(layout.meta[1]).toEqual(["Due", "15 Oct 2026"]);
    expect(layout.tableRows).toEqual([["Corporate seats · Corporate Gold", "4", "€50.00", "€200.00"]]);
    expect(layout.totals.map((total) => total.value)).toEqual(["€200.00", "€50.00", "€150.00"]);
    expect(layout.totals[2].strong).toBe(true);
    expect(layout.filename).toBe("INV-000123-CORP-1.pdf");
  });

  it("lists only standing payments", () => {
    const layout = buildCorporateInvoiceLayout(invoice(), labels, "en-GB");
    expect(layout.payments).toEqual(["5 Oct 2026 · Bank transfer · €50.00 · Ref: TX-1"]);
  });

  it("derives the unit price and number when missing", () => {
    const layout = buildCorporateInvoiceLayout(
      invoice({ unit_price_cents: undefined, invoice_number: null, client: { ...invoice().client, contact_name: null, billing_email: null } }),
      labels,
      "en-GB",
    );
    expect(layout.tableRows[0][2]).toBe("€50.00");
    expect(layout.title).toBe("Invoice 8F0C2D4E");
    expect(layout.billTo).toEqual(["Ακμή Α.Ε."]);
  });
});
