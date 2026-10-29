import { describe, expect, it } from "vitest";

import type { FiscalDocument } from "@/api/fiscal";
import {
  buyerEmail,
  buyerName,
  canCredit,
  cardLabel,
  canRetry,
  creditAmount,
  creditLines,
  groupByDay,
  matchesFilter,
  monthRange,
  providerName,
  ratePercent,
  sellerLine,
  transmissionState,
  yearRange,
} from "./documents-model";

const doc = (id: string, issue_date: string, extra: Partial<FiscalDocument> = {}) =>
  ({ id, issue_date, kind: "receipt", gross_cents: 1000, transmission: null, buyer: null, ...extra }) as FiscalDocument;

describe("groupByDay", () => {
  it("groups per day, newest first, closed when a day closing exists", () => {
    const groups = groupByDay(
      [doc("a", "2026-10-29"), doc("b", "2026-10-28"), doc("c", "2026-10-29"), doc("d", "2026-10-27")],
      [
        { period_kind: "day", period_start: "2026-10-28", period_end: "2026-10-28" },
        { period_kind: "month", period_start: "2026-10-01", period_end: "2026-10-31" },
      ],
    );
    expect(groups.map((group) => [group.date, group.closed, group.documents.map((d) => d.id)])).toEqual([
      ["2026-10-29", false, ["a", "c"]],
      ["2026-10-28", true, ["b"]],
      ["2026-10-27", false, ["d"]],
    ]);
  });
});

describe("transmissions", () => {
  it("reads the state for the pill and when a retry is allowed", () => {
    expect(transmissionState(null)).toBe("none");
    expect(transmissionState({ status: "accepted" })).toBe("accepted");
    expect(transmissionState({ status: "sending" })).toBe("pending");
    expect(transmissionState({ status: "failed" })).toBe("pending");
    expect(transmissionState({ status: "rejected" })).toBe("rejected");
    expect(canRetry({ status: "pending" })).toBe(false);
    expect(canRetry({ status: "failed" })).toBe(true);
    expect(canRetry({ status: "rejected" })).toBe(true);
  });

  it("filters by kind and by pending transmission", () => {
    const pending = doc("p", "2026-10-29", { transmission: { status: "pending" } as FiscalDocument["transmission"] });
    expect(matchesFilter(pending, "pending")).toBe(true);
    expect(matchesFilter(doc("a", "2026-10-29"), "pending")).toBe(false);
    expect(matchesFilter(doc("c", "2026-10-29", { kind: "credit_note" }), "credit_note")).toBe(true);
    expect(matchesFilter(doc("c", "2026-10-29", { kind: "credit_note" }), "receipt")).toBe(false);
  });
});

describe("periods", () => {
  it("gives a month, the previous month across a year, and a year", () => {
    expect(monthRange("2026-10-29")).toEqual({ from: "2026-10-01", to: "2026-10-31" });
    expect(monthRange("2026-01-15", -1)).toEqual({ from: "2025-12-01", to: "2025-12-31" });
    expect(monthRange("2028-03-01", -1)).toEqual({ from: "2028-02-01", to: "2028-02-29" });
    expect(yearRange("2026-10-29")).toEqual({ from: "2026-01-01", to: "2026-12-31" });
  });
});

describe("credit notes", () => {
  const lines = [
    { position: 1, quantity: 1, gross_cents: 9000 },
    { position: 2, quantity: 2, gross_cents: 500 },
  ];

  it("sums every line or only the ticked ones and sends whole quantities", () => {
    expect(creditAmount(lines, true, new Set())).toBe(9500);
    expect(creditAmount(lines, false, new Set([2]))).toBe(500);
    expect(creditLines(lines, new Set([2]))).toEqual([{ position: 2, quantity: 2 }]);
  });

  it("allows a credit note until the whole amount is credited, never on a credit note", () => {
    expect(canCredit({ kind: "receipt", gross_cents: 9500, credit_notes: [] })).toBe(true);
    expect(canCredit({ kind: "receipt", gross_cents: 9500, credit_notes: [{ gross_cents: 500 }] as never })).toBe(true);
    expect(canCredit({ kind: "receipt", gross_cents: 9500, credit_notes: [{ gross_cents: 9500 }] as never })).toBe(false);
    expect(canCredit({ kind: "credit_note", gross_cents: 9500, credit_notes: [] })).toBe(false);
  });
});

describe("printed parties", () => {
  it("reads the buyer and the seller as printed", () => {
    expect(buyerName({ buyer: { name: "ACME Α.Ε." } })).toBe("ACME Α.Ε.");
    expect(buyerName({ buyer: null })).toBeNull();
    expect(
      sellerLine({ legal_name: "ΚΥΨΕΛΗ ΑΘΛΗΤΙΚΗ Ι.Κ.Ε.", tax_id: "801234567", tax_office: "Ζ΄ Αθηνών", street: "Φωκίωνος Νέγρη", building_number: "12", postal_code: "11361", city: "Αθήνα" }),
    ).toBe("ΚΥΨΕΛΗ ΑΘΛΗΤΙΚΗ Ι.Κ.Ε. · 801234567 · Ζ΄ Αθηνών · Φωκίωνος Νέγρη 12, 11361 Αθήνα");
    expect(ratePercent(2400)).toBe("24");
    expect(ratePercent(550)).toBe("5.5");
  });
});

describe("ADR-265 helpers", () => {
  it("reads the buyer's email as printed", () => {
    expect(buyerEmail({ buyer: { email: " maria@example.com " } })).toBe("maria@example.com");
    expect(buyerEmail({ buyer: { name: "Maria" } })).toBeNull();
    expect(buyerEmail({ buyer: null })).toBeNull();
  });

  it("names the card and the provider of a refund", () => {
    expect(cardLabel({ card_last4: "4242", card_brand: "visa" })).toBe("••4242");
    expect(cardLabel({ card_last4: null, card_brand: "visa" })).toBe("visa");
    expect(cardLabel({ card_last4: null, card_brand: null })).toBe("••••");
    expect(providerName("viva")).toBe("Viva");
    expect(providerName("stripe")).toBe("Stripe");
    expect(providerName("mollie")).toBe("Mollie");
  });
});
