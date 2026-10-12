import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";
import {
  accountingErrorKey,
  buildReconciliationLine,
  discrepancyMessageKey,
  exportRunsInBackground,
  formatMinorUnits,
  parseAmountToCents,
  rangeDays,
  shiftIsoDate,
  validateExportRange,
  type ReconciliationForm,
} from "@/lib/finance-accounting";

const form: ReconciliationForm = {
  provider: " Stripe ",
  externalReference: " ch_1 ",
  externalType: "payment",
  externalStatus: "settled",
  amount: "50,00",
  currency: "eur",
  occurredOn: "2026-10-10",
  description: "  ",
};

describe("parseAmountToCents", () => {
  it("parses decimal inputs exactly", () => {
    expect(parseAmountToCents("25")).toBe(2500);
    expect(parseAmountToCents("25.5")).toBe(2550);
    expect(parseAmountToCents("0,07")).toBe(7);
    expect(parseAmountToCents(" 1234.56 ")).toBe(123456);
  });

  it("rejects zero, negatives, extra decimals and text", () => {
    for (const input of ["0", "-5", "1.234", "abc", "", "1e3"]) {
      expect(parseAmountToCents(input)).toBeNull();
    }
  });
});

describe("export ranges", () => {
  it("counts inclusive days", () => {
    expect(rangeDays("2026-10-01", "2026-10-31")).toBe(31);
    expect(rangeDays("2026-10-01", "nope")).toBeNull();
  });

  it("mirrors the backend validation", () => {
    expect(validateExportRange("2026-10-01", "2026-10-12", "2026-10-12")).toBe("ok");
    expect(validateExportRange("2026-10-05", "2026-10-01", "2026-10-12")).toBe("invalid");
    expect(validateExportRange("2026-10-13", "2026-10-20", "2026-10-12")).toBe("invalid");
    expect(validateExportRange("2015-01-01", "2026-10-01", "2026-10-12")).toBe("too_long");
  });

  it("flags ranges over 31 days as background exports", () => {
    expect(exportRunsInBackground("2026-10-01", "2026-10-31")).toBe(false);
    expect(exportRunsInBackground("2026-09-30", "2026-10-31")).toBe(true);
  });

  it("shifts dates by whole days", () => {
    expect(shiftIsoDate("2026-03-01", -1)).toBe("2026-02-28");
  });
});

describe("buildReconciliationLine", () => {
  it("normalizes a valid statement line into the API body", () => {
    expect(buildReconciliationLine(form)).toEqual({
      ok: true,
      body: {
        provider: "stripe",
        external_reference: "ch_1",
        external_type: "payment",
        external_status: "settled",
        statement_amount_cents: 5000,
        statement_currency: "EUR",
        statement_occurred_on: "2026-10-10",
        statement_description: null,
      },
    });
  });

  it("reports the first problem", () => {
    expect(buildReconciliationLine({ ...form, externalReference: "" })).toEqual({ ok: false, error: "required" });
    expect(buildReconciliationLine({ ...form, provider: "Bad Provider" })).toEqual({ ok: false, error: "provider" });
    expect(buildReconciliationLine({ ...form, amount: "-1" })).toEqual({ ok: false, error: "amount" });
    expect(buildReconciliationLine({ ...form, currency: "euro" })).toEqual({ ok: false, error: "currency" });
  });
});

describe("messages", () => {
  it("maps discrepancy codes and API errors to catalog keys", () => {
    expect(discrepancyMessageKey("amount_mismatch")).toBe("discrepancyAmountMismatch");
    expect(discrepancyMessageKey("something_new")).toBe("discrepancyOther");
    expect(accountingErrorKey(new ApiError(409, "x", { code: "reconciliation_target_already_matched" }))).toBe(
      "errorAlreadyMatched",
    );
    expect(accountingErrorKey(new ApiError(500, "x", {}))).toBe("errorGeneric");
    expect(accountingErrorKey(new Error("boom"))).toBe("errorGeneric");
  });

  it("formats minor units with a fallback for unknown currencies", () => {
    expect(formatMinorUnits("en", 1250, "EUR")).toBe("€12.50");
    expect(formatMinorUnits("en", null)).toBe("—");
    expect(formatMinorUnits("en", 1250, "XX")).toBe("12.50 XX");
  });
});
