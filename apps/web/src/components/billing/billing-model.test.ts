import { describe, expect, it } from "vitest";

import { billingDocuments, billingTab, filterDocuments, sessionsLeft, validityProgress } from "./billing-model";

const usage = (limit: number | "unlimited", remaining: number | "unlimited") => ({
  limit,
  remaining,
  period: "subscription_period",
  period_start: "2026-10-01",
  period_end: "2026-10-31",
  committed: 0,
  extensions: 0,
});

describe("billingTab", () => {
  it("reads a known tab and falls back to the package", () => {
    expect(billingTab("documents")).toBe("documents");
    expect(billingTab("offers")).toBe("offers");
    expect(billingTab("nope")).toBe("membership");
    expect(billingTab(null)).toBe("membership");
  });
});

describe("billingDocuments", () => {
  const provider = {
    invoices: [
      {
        id: "i1",
        invoice_number: "INV-1",
        document_kind: "invoice" as const,
        status: "issued",
        issue_date: "2026-10-01",
        due_date: "2026-10-08",
        total_cents: 8900,
        balance_due_cents: 8900,
        currency: "EUR",
        downloadable: true,
      },
    ],
    payments: [{ id: "p1", amount_cents: 3600, net_amount_cents: 3600, currency: "EUR", paid_on: "2026-09-15" }],
    refund_receipts: [
      { id: "r1", receipt_number: "RFD-000001", amount_cents: 1500, currency: "EUR", issued_at: "2026-10-03T09:00:00Z" },
    ],
  };

  it("merges invoices, payments and refunds newest first, refunds negative", () => {
    const documents = billingDocuments(provider);
    expect(documents.map((document) => document.key)).toEqual(["refund:r1", "invoice:i1", "payment:p1"]);
    expect(documents[0].amountCents).toBe(-1500);
    expect(documents[0].downloadable).toBe(true);
    expect(documents[2].downloadable).toBe(false);
  });

  it("filters by kind", () => {
    const documents = billingDocuments(provider);
    expect(filterDocuments(documents, "all")).toHaveLength(3);
    expect(filterDocuments(documents, "payment").map((document) => document.id)).toEqual(["p1"]);
  });
});

describe("sessionsLeft", () => {
  it("prefers class visits and reports unlimited packages", () => {
    expect(sessionsLeft({ allowances: { bookings: usage(20, 3), class_visits: usage(12, 5) } })).toEqual({
      unlimited: false,
      remaining: 5,
      limit: 12,
    });
    expect(sessionsLeft({ allowances: { class_visits: usage("unlimited", "unlimited") } })).toEqual({ unlimited: true });
    expect(sessionsLeft({ allowances: {} })).toBeNull();
    expect(sessionsLeft(null)).toBeNull();
  });
});

describe("validityProgress", () => {
  it("is the share of the window that has passed", () => {
    expect(validityProgress("2026-10-01", "2026-10-31", new Date("2026-10-16T00:00:00Z"))).toBeCloseTo(0.5, 1);
    expect(validityProgress("2026-10-01", "2026-10-31", new Date("2026-12-01"))).toBe(1);
    expect(validityProgress(null, "2026-10-31", new Date())).toBeNull();
  });
});
