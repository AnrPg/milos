import { describe, expect, it } from "vitest";

import { manualInvoiceBody } from "@/components/admin/finance/shared/charge-category";
import { commitmentConflict } from "@/components/admin/finance/shared/membership-commitment";
import { ApiError } from "@/api/client";

const base = { amountCents: 2500, description: "", dueDate: "", subscriptionId: "", chargeCategory: "", fallbackDescription: "Product" };

describe("manualInvoiceBody", () => {
  it("sends a categorised manual charge as an explicit line", () => {
    expect(manualInvoiceBody({ ...base, chargeCategory: "product", description: "Shaker", dueDate: "2026-11-01" })).toEqual({
      due_date: "2026-11-01",
      description: "Shaker",
      lines: [
        { line_type: "manual_charge", charge_category: "product", description: "Shaker", quantity: 1, unit_amount_cents: 2500 },
      ],
    });
  });

  it("falls back to the category name when the description is empty", () => {
    const body = manualInvoiceBody({ ...base, chargeCategory: "product" });
    expect(body.description).toBe("Product");
  });

  it("keeps the amount form without a category or with a package link", () => {
    expect(manualInvoiceBody(base)).toEqual({ due_date: undefined, amount_cents: 2500, description: undefined, membership_package_subscription_id: undefined });
    expect(manualInvoiceBody({ ...base, chargeCategory: "event", subscriptionId: "sub-1" })).toMatchObject({
      amount_cents: 2500,
      membership_package_subscription_id: "sub-1",
    });
  });
});

describe("commitmentConflict", () => {
  it("returns the commitment end date for a package_commitment_active refusal", () => {
    const error = new ApiError(409, "commitment", { code: "package_commitment_active", params: { commitment_ends_on: "2027-03-31" } });
    expect(commitmentConflict(error)).toEqual({ endsOn: "2027-03-31" });
  });

  it("ignores other errors", () => {
    expect(commitmentConflict(new ApiError(422, "x", { code: "validation_failed" }))).toBeNull();
    expect(commitmentConflict(new Error("x"))).toBeNull();
  });
});
