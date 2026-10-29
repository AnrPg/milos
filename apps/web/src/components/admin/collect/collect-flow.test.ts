import { describe, expect, it } from "vitest";

import type { DeskOptions } from "@/api/desk-collect";

import {
  cardTotalCents,
  choicesFor,
  defaultChoice,
  freeSaleErrors,
  initials,
  outcomeOf,
  parseAmountCents,
  pickedAmount,
  startBody,
  tipOwner,
  type Payer,
} from "./collect-flow";

const options: DeskOptions = {
  user_id: "u1",
  relation: "member",
  renewal: { id: "pkg-12", name: "12 επισκέψεις", price_cents: 9000, currency: "EUR", ends_on: "2026-10-29" },
  invoices: [
    { id: "inv-1", number: "I-000212", description: "Προσωπική προπόνηση", balance_due_cents: 3000, currency: "EUR" },
    { id: "inv-paid", number: "I-000200", description: null, balance_due_cents: 0, currency: "EUR" },
  ],
  packages: [
    { id: "pkg-12", name: "12 επισκέψεις", price_cents: 9000, currency: "EUR" },
    { id: "pkg-8", name: "8 επισκέψεις", price_cents: 6500, currency: "EUR" },
  ],
  shop_orders: [{ id: "ord-104", number: 104, total_cents: 750, currency: "EUR", customer_name: null, summary: "Νερό 500 ml ×2" }],
};

const member: Payer = { kind: "person", userId: "u1", name: "Μαρία Κωνσταντίνου", relation: "member" };
const walkIn: Payer = { kind: "walk_in" };

describe("what a payer can pay", () => {
  it("offers the renewal first, open invoices, orders, another package and a free amount", () => {
    const choices = choicesFor(options, member);
    expect(choices.map((choice) => choice.kind)).toEqual(["renewal", "invoice", "order", "package", "free"]);
    expect(defaultChoice(choices)?.kind).toBe("renewal");
  });

  it("gives a walk-in only orders and a free sale (ADR-264)", () => {
    const choices = choicesFor({ ...options, user_id: null, relation: "walk_in" }, walkIn);
    expect(choices.map((choice) => choice.kind)).toEqual(["order", "free"]);
    expect(defaultChoice(choices)?.kind).toBe("order");
  });

  it("still offers a free amount before the options load", () => {
    expect(choicesFor(undefined, member).map((choice) => choice.kind)).toEqual(["free"]);
  });
});

describe("the free sale", () => {
  it("reads amounts the way people type them", () => {
    expect(parseAmountCents("12")).toBe(1200);
    expect(parseAmountCents("12,5")).toBe(1250);
    expect(parseAmountCents(" 7.50 € ")).toBe(750);
    expect(parseAmountCents("0")).toBeNull();
    expect(parseAmountCents("12,345")).toBeNull();
    expect(parseAmountCents("abc")).toBeNull();
  });

  it("asks for what is sold and an amount, under each field", () => {
    expect(freeSaleErrors({ description: " ", amount: "", category: "other" })).toEqual({
      description: "descriptionRequired",
      amount: "amountRequired",
    });
    expect(freeSaleErrors({ description: "x".repeat(121), amount: "5", category: "other" })).toEqual({ description: "descriptionRequired" });
    expect(freeSaleErrors({ description: "Day pass", amount: "12", category: "other" })).toEqual({});
  });
});

describe("starting the payment", () => {
  const free = { description: "", amount: "", category: "other" as const };

  it("pays the renewal as a membership package of the member", () => {
    const choice = choicesFor(options, member)[0]!;
    expect(startBody({ choice, packageId: null, free }, member, options, "key-1")).toEqual({
      purpose: "membership_package",
      purpose_id: "pkg-12",
      amount_cents: 9000,
      user_id: "u1",
      idempotency_key: "key-1",
      started_on: "phone",
    });
  });

  it("needs a picked package before it has an amount", () => {
    const choice = choicesFor(options, member).find((entry) => entry.kind === "package")!;
    expect(pickedAmount({ choice, packageId: null, free }, options)).toBeNull();
    expect(startBody({ choice, packageId: "pkg-8", free }, member, options, "key-2")).toMatchObject({
      purpose: "membership_package",
      purpose_id: "pkg-8",
      amount_cents: 6500,
    });
  });

  it("sends a walk-in's free sale with no member, its description and category", () => {
    const choice = choicesFor(options, walkIn).find((entry) => entry.kind === "free")!;
    const sale = { description: " Day pass ", amount: "12", category: "product" as const };
    expect(startBody({ choice, packageId: null, free: sale }, walkIn, options, "key-3")).toEqual({
      purpose: "free_sale",
      amount_cents: 1200,
      user_id: null,
      description: "Day pass",
      charge_category: "product",
      idempotency_key: "key-3",
      started_on: "phone",
    });
    expect(startBody({ choice, packageId: null, free }, walkIn, options, "key-4")).toBeNull();
  });
});

describe("the result", () => {
  it("reads every state of a terminal payment", () => {
    expect(outcomeOf({ status: "succeeded", failure_code: null })).toBe("paid");
    expect(outcomeOf({ status: "cancelled", failure_code: "terminal_cancelled" })).toBe("cancelled");
    expect(outcomeOf({ status: "failed", failure_code: "terminal_declined" })).toBe("declined");
    expect(outcomeOf({ status: "failed", failure_code: "amount_mismatch" })).toBe("mismatch");
    expect(outcomeOf({ status: "failed", failure_code: "terminal_app_error" })).toBe("failed");
    expect(outcomeOf({ status: "awaiting_payer", failure_code: "terminal_unconfirmed" })).toBe("unconfirmed");
    expect(outcomeOf({ status: "awaiting_payer", failure_code: null })).toBe("waiting");
    expect(outcomeOf({ status: "expired", failure_code: "terminal_no_result" })).toBe("failed");
  });

  it("adds the surcharge and the tip to what the card paid", () => {
    expect(cardTotalCents({ amount_cents: 9000, surcharge_cents: 180, tip_cents: 500 })).toBe(9680);
  });

  it("says whose the tip is (ADR-272)", () => {
    const base = { tip_cents: 500, tip_attribution: "started_payment" as const, tip_recipient_user_id: "me" };
    expect(tipOwner(base, "me")).toBe("you");
    expect(tipOwner(base, "someone-else")).toBe("staff");
    expect(tipOwner({ tip_cents: 500, tip_attribution: "front_desk_role", tip_recipient_user_id: null }, "me")).toBe("desk");
    expect(tipOwner({ ...base, tip_cents: 0 }, "me")).toBeNull();
  });

  it("draws initials", () => {
    expect(initials("Μαρία Κωνσταντίνου")).toBe("ΜΚ");
    expect(initials(null)).toBe("");
  });
});
