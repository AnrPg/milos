import { describe, expect, it } from "vitest";

import {
  choosePurpose,
  fieldForErrorCode,
  findPurpose,
  initialForm,
  missingFields,
  outcome,
  parseAmountCents,
  paymentPurposes,
  receiveBody,
} from "./receive-payment";

const profile = {
  invoices: [
    { id: "inv-late", invoice_number: "INV-2", status: "overdue", balance_due_cents: 2500, due_date: "2026-10-30" },
    { id: "inv-old", invoice_number: "INV-1", status: "partially_paid", balance_due_cents: 1000, due_date: "2026-10-01" },
    { id: "inv-paid", invoice_number: "INV-0", status: "paid", balance_due_cents: 0, due_date: "2026-09-01" },
    { id: "inv-draft", invoice_number: "INV-9", status: "draft", balance_due_cents: 4000, due_date: "2026-11-01" },
  ],
  package_subscriptions: [
    { id: "sub-1", status: "active", package_name: "Unlimited", price_cents_snapshot: 6000 },
    { id: "sub-2", status: "ended", package_name: "Old", price_cents_snapshot: 3000 },
  ],
};
const name = (subscription: Record<string, unknown>) => String(subscription.package_name ?? "");

describe("receive payment form", () => {
  it("offers open invoices oldest first, then active packages, then something else", () => {
    const purposes = paymentPurposes(profile, name);
    expect(purposes.map((p) => (p.kind === "other" ? "other" : p.id))).toEqual(["inv-old", "inv-late", "sub-1", "other"]);
  });

  it("starts on the oldest open invoice with what it still owes, in cash", () => {
    const form = initialForm(paymentPurposes(profile, name));
    expect(form).toMatchObject({ purpose: "invoice:inv-old", amount: "10.00", method: "cash", paidOn: "" });
    expect(initialForm(paymentPurposes({}, name))).toMatchObject({ purpose: "other", amount: "" });
  });

  it("fills in what is owed when the purpose changes, and keeps a typed amount for something else", () => {
    const purposes = paymentPurposes(profile, name);
    const form = choosePurpose(initialForm(purposes), purposes, "package:sub-1");
    expect(form.amount).toBe("60.00");
    expect(choosePurpose({ ...form, amount: "12" }, purposes, "other").amount).toBe("12");
  });

  it("reads amounts with a comma or a dot and refuses anything that is not above zero", () => {
    expect(parseAmountCents("40")).toBe(4000);
    expect(parseAmountCents("40,50")).toBe(4050);
    expect(parseAmountCents(" 1.5 ")).toBe(150);
    for (const bad of ["", "0", "-3", "abc", "1.234", "1,2,3"]) expect(parseAmountCents(bad)).toBeNull();
  });

  it("previews the document the billing setup will issue", () => {
    const purposes = paymentPurposes(profile, name);
    expect(outcome("receipt", findPurpose(purposes, "invoice:inv-old"))).toBe("settles_invoice");
    expect(outcome("receipt", findPurpose(purposes, "package:sub-1"))).toBe("receipt");
    expect(outcome("invoice", findPurpose(purposes, "other"))).toBe("invoice");
    expect(outcome(undefined, findPurpose(purposes, "other"))).toBe("invoice");
  });

  it("names the fields to fix before sending", () => {
    const purposes = paymentPurposes(profile, name);
    const invoice = findPurpose(purposes, "invoice:inv-old");
    const base = initialForm(purposes);
    expect(missingFields(base, invoice)).toEqual({});
    expect(missingFields({ ...base, amount: "11" }, invoice)).toEqual({ amount_cents: "amountAboveBalance" });
    expect(missingFields({ ...base, amount: "x" }, invoice)).toEqual({ amount_cents: "amountInvalid" });
    expect(missingFields({ ...base, purpose: "other", description: " " }, { kind: "other" })).toEqual({ description: "descriptionRequired" });
  });

  it("sends only what belongs to the chosen purpose", () => {
    const purposes = paymentPurposes(profile, name);
    const base = { ...initialForm(purposes), method: "card_manual" as const, notes: " front desk " };
    expect(receiveBody(base, findPurpose(purposes, "invoice:inv-old"), "key-1")).toEqual({
      amount_cents: 1000,
      payment_method: "card_manual",
      paid_on: null,
      notes: "front desk",
      idempotency_key: "key-1",
      finance_invoice_id: "inv-old",
    });
    expect(receiveBody({ ...base, amount: "60" }, findPurpose(purposes, "package:sub-1"), "k")).toMatchObject({
      membership_package_subscription_id: "sub-1",
      amount_cents: 6000,
    });
    const other = receiveBody({ ...base, description: " Water ", chargeCategory: "product", paidOn: "2026-10-27" }, { kind: "other" }, "k");
    expect(other).toMatchObject({ description: "Water", charge_category: "product", paid_on: "2026-10-27" });
    expect(other).not.toHaveProperty("finance_invoice_id");
  });

  it("puts an API refusal under the field it is about", () => {
    expect(fieldForErrorCode("payment_exceeds_invoice_balance")).toBe("amount_cents");
    expect(fieldForErrorCode("payment_purpose_required")).toBe("description");
    expect(fieldForErrorCode("invoice_already_paid")).toBe("purpose");
    expect(fieldForErrorCode("business_not_activated")).toBeNull();
  });
});
