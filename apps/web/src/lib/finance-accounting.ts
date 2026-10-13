import { ApiError } from "@/api/client";
import type { ReconciliationLineRequest } from "@/api/finance-accounting";

// ADR-126 UI rules. The backend remains authoritative; these mirror its
// validation so admins get immediate feedback before a request is sent.

export const EXPORT_INLINE_MAX_DAYS = 31;
export const EXPORT_MAX_RANGE_DAYS = 1830;
const PROVIDER_PATTERN = /^[a-z0-9][a-z0-9_.-]{0,39}$/;
const DAY_MS = 86_400_000;

/** Parses a decimal money input ("25", "25.5", "25,50") into positive integer cents. */
export function parseAmountToCents(input: string): number | null {
  const normalized = input.trim().replace(",", ".");
  if (!/^\d+(\.\d{1,2})?$/.test(normalized)) return null;
  const [whole, fraction = ""] = normalized.split(".");
  const cents = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
  return Number.isSafeInteger(cents) && cents > 0 ? cents : null;
}

function parseIsoDate(value: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const time = Date.parse(`${value}T00:00:00Z`);
  return Number.isNaN(time) ? null : time;
}

/** Inclusive day count of an ISO date range, or null when malformed. */
export function rangeDays(start: string, end: string): number | null {
  const from = parseIsoDate(start);
  const to = parseIsoDate(end);
  if (from === null || to === null) return null;
  return Math.round((to - from) / DAY_MS) + 1;
}

export type ExportRangeCheck = "ok" | "invalid" | "too_long";

export function validateExportRange(start: string, end: string, today: string): ExportRangeCheck {
  const days = rangeDays(start, end);
  const todayTime = parseIsoDate(today);
  const startTime = parseIsoDate(start);
  if (days === null || todayTime === null || startTime === null || days < 1) return "invalid";
  if (startTime > todayTime) return "invalid";
  if (days > EXPORT_MAX_RANGE_DAYS) return "too_long";
  return "ok";
}

export function exportRunsInBackground(start: string, end: string): boolean {
  const days = rangeDays(start, end);
  return days !== null && days > EXPORT_INLINE_MAX_DAYS;
}

export type ReconciliationForm = {
  provider: string;
  externalReference: string;
  externalType: "payment" | "refund";
  externalStatus: "settled" | "pending" | "failed";
  amount: string;
  currency: string;
  occurredOn: string;
  description: string;
};

export type ReconciliationFormResult =
  | { ok: true; body: ReconciliationLineRequest }
  | { ok: false; error: "required" | "amount" | "provider" | "currency" };

export function buildReconciliationLine(form: ReconciliationForm): ReconciliationFormResult {
  const provider = form.provider.trim().toLowerCase();
  const reference = form.externalReference.trim();
  if (!provider || !reference || !form.occurredOn || !form.amount.trim()) {
    return { ok: false, error: "required" };
  }
  if (!PROVIDER_PATTERN.test(provider)) return { ok: false, error: "provider" };
  const cents = parseAmountToCents(form.amount);
  if (cents === null) return { ok: false, error: "amount" };
  const currency = form.currency.trim().toUpperCase() || "EUR";
  if (!/^[A-Z]{3}$/.test(currency)) return { ok: false, error: "currency" };

  return {
    ok: true,
    body: {
      provider,
      external_reference: reference,
      external_type: form.externalType,
      external_status: form.externalStatus,
      statement_amount_cents: cents,
      statement_currency: currency,
      statement_occurred_on: form.occurredOn,
      statement_description: form.description.trim() || null,
    },
  };
}

const DISCREPANCY_KEYS: Record<string, string> = {
  type_mismatch: "discrepancyTypeMismatch",
  amount_mismatch: "discrepancyAmountMismatch",
  currency_mismatch: "discrepancyCurrencyMismatch",
  date_out_of_tolerance: "discrepancyDateOutOfTolerance",
  provider_not_settled: "discrepancyProviderNotSettled",
  internal_not_settled: "discrepancyInternalNotSettled",
};

export function discrepancyMessageKey(code: string): string {
  return DISCREPANCY_KEYS[code] ?? "discrepancyOther";
}

const ERROR_KEYS: Record<string, string> = {
  invalid_export_range: "errorRangeInvalid",
  export_range_too_long: "errorRangeTooLong",
  reconciliation_reference_conflict: "errorReferenceConflict",
  reconciliation_target_already_matched: "errorAlreadyMatched",
  export_job_unavailable: "errorJobUnavailable",
  accounting_export_not_ready: "errorExportNotReady",
};

/** Message key for an ADR-126 API error, falling back to the generic one. */
export function accountingErrorKey(error: unknown): string {
  if (error instanceof ApiError && error.payload.code && ERROR_KEYS[error.payload.code]) {
    return ERROR_KEYS[error.payload.code];
  }
  return "errorGeneric";
}

export function formatMinorUnits(locale: string, cents: number | null | undefined, currency = "EUR") {
  if (cents === null || cents === undefined) return "—";
  try {
    return new Intl.NumberFormat(locale, { style: "currency", currency }).format(cents / 100);
  } catch {
    return `${(cents / 100).toFixed(2)} ${currency}`;
  }
}

export function todayIso(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10);
}

export function shiftIsoDate(value: string, days: number): string {
  const time = parseIsoDate(value);
  if (time === null) return value;
  return new Date(time + days * DAY_MS).toISOString().slice(0, 10);
}
