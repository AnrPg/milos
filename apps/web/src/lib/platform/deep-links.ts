// ADR-256: where a link the operating system opens the app with leads.
//
// Universal links (iOS) and App Links (Android) hand the app a full https
// URL on the web app's own host (app-links.json lists the paths). Most of
// them are simply opened as an in-app page. The payment return is special:
// the provider's checkout page (ADR-246) ran in the in-app browser, so the
// app must close that browser and ask the API about the payment.
import { inAppPath } from "./app-links";

export const PAYMENT_RETURN_PATH = "/pay/return";

/** What the provider's redirect tells us, in the shape of the API's return body. */
export type PaymentReturn = {
  payment_id?: string;
  provider_ref?: string;
  transaction_id?: string;
  cancelled: boolean;
};

export type DeepLink = { kind: "payment_return"; path: string; payment: PaymentReturn } | { kind: "page"; path: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// The API accepts at most 200 characters for a provider reference.
const REFERENCE = /^[A-Za-z0-9_\-.:]{1,200}$/;

function reference(value: string | null): string | undefined {
  const trimmed = value?.trim();
  return trimmed && REFERENCE.test(trimmed) ? trimmed : undefined;
}

/**
 * Reads the query of a /pay/return URL: `payment` is ours (the intent id the
 * API put in return_url), `cancelled=1` comes from the cancel_url, and Viva
 * adds `s` (order code) and `t` (transaction id) to its redirect.
 */
export function parsePaymentReturn(search: string | URLSearchParams): PaymentReturn {
  const params = typeof search === "string" ? new URLSearchParams(search) : search;
  const payment = params.get("payment")?.trim();
  const result: PaymentReturn = {
    cancelled: params.get("cancelled") === "1" || params.get("cancelled") === "true",
  };
  if (payment && UUID.test(payment)) result.payment_id = payment.toLowerCase();
  const providerRef = reference(params.get("s"));
  if (providerRef) result.provider_ref = providerRef;
  const transactionId = reference(params.get("t"));
  if (transactionId) result.transaction_id = transactionId;
  return result;
}

/** The body for POST /me/payments/return, or null when the URL names no payment at all. */
export function paymentReturnBody(payment: PaymentReturn) {
  if (!payment.payment_id && !payment.provider_ref) return null;
  const body: { payment_id?: string; provider_ref?: string; transaction_id?: string } = {};
  if (payment.payment_id) body.payment_id = payment.payment_id;
  if (payment.provider_ref) body.provider_ref = payment.provider_ref;
  if (payment.transaction_id) body.transaction_id = payment.transaction_id;
  return body;
}

/**
 * Where a link the app was opened with leads, or null when it is not on this
 * web app's own host (those are never opened inside the app).
 */
export function routeDeepLink(url: string, currentOrigin: string): DeepLink | null {
  const path = inAppPath(url, currentOrigin);
  if (!path) return null;

  const target = new URL(path, "https://app.invalid");
  const pathname = target.pathname.replace(/\/+$/, "") || "/";
  if (pathname === PAYMENT_RETURN_PATH) {
    return { kind: "payment_return", path, payment: parsePaymentReturn(target.searchParams) };
  }
  return { kind: "page", path };
}

/** The page the app shows when the payer closes the checkout without being redirected back. */
export function checkoutClosedPath(paymentId: string): string {
  const params = new URLSearchParams({ payment: paymentId, closed: "1" });
  return `${PAYMENT_RETURN_PATH}?${params.toString()}`;
}
