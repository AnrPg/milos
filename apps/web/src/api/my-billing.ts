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
