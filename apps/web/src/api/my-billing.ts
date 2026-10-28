import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

type Schemas = components["schemas"];

export type MyBilling = Schemas["MyBilling"];
export type BillingProvider = Schemas["BillingProvider"];
export type BillingInvoice = Schemas["BillingInvoice"];
export type BillingSubscription = Schemas["BillingSubscription"];

export const MY_BILLING_QUERY_KEY = ["me", "billing"] as const;

/** Εγώ › Πληρωμές: one section per gym or coach the person is a client of. */
export function fetchMyBilling(token: string) {
  return apiRequest<MyBilling>("/me/billing", { token, scope: "account" });
}

export type MyBillingTransactions = Schemas["MyBillingTransactions"];
export type BillingTransaction = Schemas["BillingTransaction"];
export type BillingTransactionKind = BillingTransaction["kind"];

export const myTransactionsKey = (organizationId: string | null, kind: string | null) =>
  ["me", "billing", "transactions", organizationId ?? "all", kind ?? "all"] as const;

/**
 * Συναλλαγές: the complete money history, newest first. `organizationId`
 * narrows it to one provider but keeps events of hosts that are not providers.
 */
export function fetchMyTransactions(
  token: string,
  params: { organizationId?: string | null; kind?: string | null; cursor?: string | null; limit?: number } = {},
) {
  const query = new URLSearchParams();
  if (params.organizationId) query.set("organization_id", params.organizationId);
  if (params.kind) query.set("kind", params.kind);
  if (params.cursor) query.set("cursor", params.cursor);
  if (params.limit) query.set("limit", String(params.limit));
  const qs = query.toString();
  return apiRequest<MyBillingTransactions>(`/me/billing/transactions${qs ? `?${qs}` : ""}`, { token, scope: "account" });
}

const orgPath =(slug: string, path: string) => `/org/${encodeURIComponent(slug)}${path}`;

/** A provider's invoice PDF, always at that provider (not the selected box). */
export function getProviderInvoiceDownloadUrl(token: string, slug: string, invoiceId: string) {
  return apiRequest<{ download_url: string; file_name: string }>(
    orgPath(slug, `/me/invoices/${encodeURIComponent(invoiceId)}/download-url`),
    { token },
  );
}

/** A provider's printable refund receipt (ADR-126). */
export function fetchProviderRefundReceiptDocument(token: string, slug: string, receiptId: string, locale?: string) {
  const query = locale ? `?locale=${encodeURIComponent(locale)}` : "";
  return apiRequest<string>(orgPath(slug, `/me/refund-receipts/${encodeURIComponent(receiptId)}/document${query}`), {
    token,
    responseType: "text",
  });
}

// ── ADR-220: the member's renewal choice and leaving the box ────────────────

/** Turns renewal of one of the member's subscriptions at a provider on or off. */
export function setMyAutoRenew(token: string, slug: string, subscriptionId: string, autoRenew: boolean) {
  return apiRequest<{ package_subscription: Record<string, unknown> }>(
    orgPath(slug, `/me/membership/subscriptions/${encodeURIComponent(subscriptionId)}/auto-renew`),
    { token, method: "PUT", body: { auto_renew: autoRenew } },
  );
}

/** The member leaves the provider: renewals stop, access lasts to the paid end. */
export function leaveProvider(token: string, slug: string, reason: string | null) {
  return apiRequest<{ leaving_on: string; voided_invoice_count: number; outstanding_cents: number }>(
    orgPath(slug, "/me/membership/leave"),
    { token, method: "POST", body: { reason } },
  );
}

/** The member changes their mind before their last day. */
export function stayWithProvider(token: string, slug: string) {
  return apiRequest<{ membership: Record<string, unknown> }>(orgPath(slug, "/me/membership/leave"), {
    token,
    method: "DELETE",
  });
}
