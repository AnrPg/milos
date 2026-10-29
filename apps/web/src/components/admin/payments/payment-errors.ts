import { ApiError } from "@/api/client";
import { localizeError, type UiTranslator } from "@/i18n/presentation";

type Translate = (key: string, values?: Record<string, string>) => string;

/** Payment error codes (fallback_controller.ex, ADR-246/260/261) in plain words. */
const CODES: Record<string, string> = {
  payment_provider_unavailable: "errUnavailable",
  connect_not_available: "errConnectNotAvailable",
  connect_not_configured: "errConnectNotAvailable",
  online_payments_unavailable: "errNotConnected",
  payment_not_retryable: "errNotRetryable",
  payment_method_inactive: "errCardInactive",
  payment_method_expired: "errCardInactive",
};

/** What went wrong with an online-payments request, for the person. */
export function paymentErrorText(error: unknown, t: Translate, ui: UiTranslator): string {
  const code = error instanceof ApiError ? error.payload.code : undefined;
  if (code && CODES[code]) return t(CODES[code]);
  return localizeError(error, ui);
}
