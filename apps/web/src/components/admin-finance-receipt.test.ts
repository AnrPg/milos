import { describe, expect, it } from "vitest";

import {
  buildFinanceReceiptPayload,
  receiptPackageLabel,
} from "@/components/admin-finance-receipt";

describe("buildFinanceReceiptPayload", () => {
  it("includes the selected member package subscription", () => {
    expect(
      buildFinanceReceiptPayload(
        {
          amount: "45.00",
          paymentMethod: "cash",
          paidOn: "2026-08-01",
          description: "August membership",
          notes: "Paid at the desk",
          packageSubscriptionId: "subscription-1",
        },
        "receipt-request-1",
      ),
    ).toEqual({
      amount_cents: 4_500,
      payment_method: "cash",
      paid_on: "2026-08-01",
      description: "August membership",
      notes: "Paid at the desk",
      membership_package_subscription_id: "subscription-1",
      idempotency_key: "receipt-request-1",
    });
  });

  it("keeps package association optional", () => {
    expect(
      buildFinanceReceiptPayload(
        {
          amount: "10",
          paymentMethod: "other",
          paidOn: "",
          description: "Drop-in",
          notes: "",
          packageSubscriptionId: "",
        },
        "receipt-request-2",
      ),
    ).not.toHaveProperty("membership_package_subscription_id");
  });
});

describe("receiptPackageLabel", () => {
  it("prefers the live package name and falls back to receipt snapshots", () => {
    expect(receiptPackageLabel({ package_name: "Unlimited Monthly" })).toBe(
      "Unlimited Monthly",
    );
    expect(receiptPackageLabel({ package_code_snapshot: "legacy_monthly" })).toBe(
      "legacy_monthly",
    );
    expect(receiptPackageLabel({ package_family_snapshot: "unlimited" })).toBe(
      "unlimited",
    );
  });
});
