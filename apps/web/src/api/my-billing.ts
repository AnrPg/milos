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

const orgPath = (slug: string, path: string) => `/org/${encodeURIComponent(slug)}${path}`;

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
