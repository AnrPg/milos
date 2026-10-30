import { beforeEach, describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import type { OnlinePayment, PublicPackage } from "@/api/my-payments";

import {
  bookingOffer,
  buyableHere,
  canPayWithAnotherCard,
  checkoutTarget,
  isRecurring,
  needsPackage,
  payErrorKey,
  paymentOutcome,
  pendingCheckout,
  providerLabel,
  rememberCheckout,
  renewalPackages,
  salesPageSections,
  withdrawalOpen,
} from "./checkout-flow";

const pkg = (over: Partial<PublicPackage>): PublicPackage => ({
  id: over.id ?? "p",
  name: over.name ?? "Unlimited",
  description: null,
  package_type: "membership",
  billing_period: "monthly",
  base_price_cents: 7500,
  currency: "EUR",
  services: { "group_classes.included": true },
  ...over,
});

const payment = (over: Partial<OnlinePayment>): OnlinePayment => ({
  id: "pay-1",
  provider: "sandbox",
  environment: "test",
  initiation: "payer",
  purpose_type: "membership_package",
  purpose_id: "pkg",
  amount_cents: 7500,
  currency: "EUR",
  description: "Unlimited",
  status: "succeeded",
  fulfilment_status: "done",
  refunded_cents: 0,
  declines: 0,
  retries: 3,
  metadata: { withdrawal: { applies: true, deadline: "2026-11-12T10:00:00Z" } },
  ...over,
});

describe("member checkout flow (ADR-246/248/256)", () => {
  beforeEach(() => window.localStorage.clear());

  it("remembers a checkout for the return page, for a day", () => {
    rememberCheckout({ paymentId: "a", slug: "box-k", kind: "package", itemName: "Unlimited", origin: "box", autopay: true }, 1000);
    expect(pendingCheckout("a", 2000)?.slug).toBe("box-k");
    expect(pendingCheckout("a", 1000 + 25 * 3600 * 1000)).toBeNull();
    expect(pendingCheckout("other", 2000)).toBeNull();
    expect(pendingCheckout(null)).toBeNull();
  });

  it("opens our own return page in-app for the sandbox and a provider's page outside", () => {
    expect(checkoutTarget("http://localhost:3000/pay/return?payment=1&sandbox_checkout=x", "http://localhost:3000")).toEqual({
      kind: "internal",
      path: "/pay/return?payment=1&sandbox_checkout=x",
    });
    expect(checkoutTarget("https://www.vivapayments.com/web/checkout?ref=1", "https://palee.app")).toEqual({
      kind: "external",
      url: "https://www.vivapayments.com/web/checkout?ref=1",
    });
  });

  it("reads the provider's answer as done, waiting, not paid or cancelled", () => {
    expect(paymentOutcome({ status: "succeeded" })).toBe("succeeded");
    expect(paymentOutcome({ status: "awaiting_payer" })).toBe("pending");
    expect(paymentOutcome({ status: "processing" })).toBe("pending");
    expect(paymentOutcome({ status: "awaiting_payer" }, true)).toBe("cancelled");
    expect(paymentOutcome({ status: "failed" })).toBe("failed");
    expect(paymentOutcome({ status: "expired" })).toBe("failed");
    expect(paymentOutcome({ status: "cancelled" })).toBe("cancelled");
  });

  it("offers withdrawal only within the 14 days of a fulfilled package purchase", () => {
    const before = new Date("2026-11-01T00:00:00Z");
    expect(withdrawalOpen(payment({}), before)).toBe(true);
    expect(withdrawalOpen(payment({}), new Date("2026-11-13T00:00:00Z"))).toBe(false);
    expect(withdrawalOpen(payment({ metadata: { withdrawal: { applies: false } } }), before)).toBe(false);
    expect(withdrawalOpen(payment({ refunded_cents: 7500 }), before)).toBe(false);
    expect(withdrawalOpen(payment({ purpose_type: "finance_invoice" }), before)).toBe(false);
    expect(withdrawalOpen(payment({ fulfilment_status: "pending" }), before)).toBe(false);
  });

  it("lets a declined saved-card charge be paid with another card", () => {
    expect(canPayWithAnotherCard(payment({ purpose_type: "finance_invoice", initiation: "merchant", status: "failed" }))).toBe(true);
    expect(canPayWithAnotherCard(payment({ purpose_type: "finance_invoice", initiation: "merchant", status: "succeeded" }))).toBe(false);
    expect(canPayWithAnotherCard(payment({ purpose_type: "finance_invoice", initiation: "payer", status: "failed" }))).toBe(false);
  });

  it("never offers a digital-only package inside the store apps", () => {
    const online = pkg({ id: "online", services: { "group_classes.included": false } });
    const classes = pkg({ id: "classes" });
    expect(buyableHere([online, classes], null).map((p) => p.id)).toEqual(["online", "classes"]);
    expect(buyableHere([online, classes], "ios").map((p) => p.id)).toEqual(["classes"]);
    expect(buyableHere([online, classes], "android").map((p) => p.id)).toEqual(["classes"]);
  });

  it("renews to packages, books with one visit or a package, and shows the trial first on the sales page", () => {
    const visit = pkg({ id: "drop", package_type: "drop_in", billing_period: "one_off" });
    const trial = pkg({ id: "trial", package_type: "trial", billing_period: "one_off" });
    const pt = pkg({ id: "pt", package_type: "pt_pack", billing_period: "one_off" });
    const unl = pkg({ id: "unl" });
    const v12 = pkg({ id: "v12", package_type: "visit_pack", billing_period: "one_off" });
    expect(renewalPackages([visit, trial, unl, v12]).map((p) => p.id)).toEqual(["unl", "v12"]);
    expect(bookingOffer([pt, unl, visit])).toEqual({ visit, pack: unl });
    const sections = salesPageSections([unl, trial, v12, visit, pt]);
    expect(sections.trial).toBe(trial);
    expect(sections.top.map((p) => p.id)).toEqual(["unl", "v12", "drop"]);
    expect(sections.more.map((p) => p.id)).toEqual(["pt"]);
  });

  it("knows recurring periods, provider names, booking refusals and payment errors", () => {
    expect(isRecurring("monthly")).toBe(true);
    expect(isRecurring("one_off")).toBe(false);
    expect(providerLabel("viva")).toBe("Viva");
    expect(providerLabel(null)).toBeNull();
    expect(needsPackage(new ApiError(403, "x", { code: "finance_profile_missing" }))).toBe(true);
    expect(needsPackage(new ApiError(409, "x", { code: "slot_full" }))).toBe(false);
    expect(payErrorKey(new ApiError(409, "x", { code: "withdrawal_period_over" }))).toBe("errorWithdrawalOver");
    expect(payErrorKey(new Error("unsafe_checkout_url"))).toBe("errorProviderPage");
    expect(payErrorKey(new ApiError(500, "x", {}))).toBeNull();
  });
});
