import type { BillingProvider } from "@/api/my-billing";
import { visibleBillingAllowances } from "@/components/finance/billing-entitlement-visibility";

/** The three segments of Εγώ › Πληρωμές, kept in `?tab=`. */
export const BILLING_TABS = ["membership", "documents", "offers"] as const;
export type BillingTab = (typeof BILLING_TABS)[number];

export function billingTab(value: string | null | undefined): BillingTab {
  return (BILLING_TABS as readonly string[]).includes(value ?? "") ? (value as BillingTab) : "membership";
}

/** Above this many documents the «Αποδείξεις» list offers a type filter. */
export const DOCUMENT_FILTER_THRESHOLD = 10;

export type DocumentKind = "invoice" | "payment" | "refund";
export type DocumentFilter = "all" | DocumentKind;

export type BillingDocument = {
  key: string;
  kind: DocumentKind;
  id: string;
  /** ISO date or date-time the row is sorted and shown by. */
  date: string | null;
  amountCents: number;
  currency: string;
  status: string | null;
  number: string | null;
  /** Invoices: a receipt (`receipt`) or an invoice. */
  documentKind?: "invoice" | "receipt";
  balanceDueCents?: number;
  dueDate?: string | null;
  downloadable: boolean;
  method?: string | null;
  reason?: string | null;
  invoiceNumber?: string | null;
};

/** Invoices, payments and refund receipts as one list, newest first. */
export function billingDocuments(provider: Pick<BillingProvider, "invoices" | "payments" | "refund_receipts">): BillingDocument[] {
  const invoices: BillingDocument[] = provider.invoices.map((invoice) => ({
    key: `invoice:${invoice.id}`,
    kind: "invoice",
    id: invoice.id,
    date: invoice.issue_date ?? invoice.due_date ?? null,
    amountCents: invoice.total_cents,
    currency: invoice.currency,
    status: invoice.status,
    number: invoice.invoice_number ?? null,
    documentKind: invoice.document_kind,
    balanceDueCents: invoice.balance_due_cents,
    dueDate: invoice.due_date ?? null,
    downloadable: invoice.downloadable,
  }));
  const payments: BillingDocument[] = provider.payments.map((payment) => ({
    key: `payment:${payment.id}`,
    kind: "payment",
    id: payment.id,
    date: payment.paid_on ?? null,
    amountCents: payment.net_amount_cents ?? payment.amount_cents ?? 0,
    currency: payment.currency,
    status: payment.payment_status ?? null,
    number: null,
    downloadable: false,
    method: payment.payment_method ?? null,
  }));
  const refunds: BillingDocument[] = provider.refund_receipts.map((receipt) => ({
    key: `refund:${receipt.id}`,
    kind: "refund",
    id: receipt.id,
    date: receipt.issued_at ?? null,
    amountCents: -Math.abs(receipt.amount_cents),
    currency: receipt.currency,
    status: null,
    number: receipt.receipt_number,
    downloadable: true,
    reason: receipt.reason ?? null,
    invoiceNumber: receipt.invoice_number ?? null,
  }));
  return [...invoices, ...payments, ...refunds].sort((a, b) => sortKey(b.date).localeCompare(sortKey(a.date)));
}

function sortKey(date: string | null) {
  return date ?? "";
}

export function filterDocuments(documents: BillingDocument[], filter: DocumentFilter) {
  return filter === "all" ? documents : documents.filter((document) => document.kind === filter);
}

type Allowance = { limit: number | "unlimited"; remaining: number | "unlimited" };

/**
 * What is left of the package for the summary: the visits allowance when
 * there is one (classes before other kinds), else the first counted one.
 * `null` when the package counts nothing.
 */
export function sessionsLeft(
  entitlement: { allowances?: Record<string, unknown> | null } | null | undefined,
): { unlimited: true } | { unlimited: false; remaining: number; limit: number } | null {
  const entries = visibleBillingAllowances((entitlement?.allowances ?? {}) as Record<string, Allowance | undefined>).filter(
    (entry): entry is [string, Allowance] => Boolean(entry[1]),
  );
  if (entries.length === 0) return null;
  const preferred = entries.find(([key]) => key === "class_visits") ?? entries.find(([key]) => key.includes("visits")) ?? entries[0];
  const usage = preferred[1];
  if (usage.remaining === "unlimited" || usage.limit === "unlimited") return { unlimited: true };
  return { unlimited: false, remaining: usage.remaining, limit: usage.limit };
}

/** How much of the validity window has passed, 0..1, or null without both ends. */
export function validityProgress(startsOn: string | null | undefined, endsOn: string | null | undefined, now: Date) {
  if (!startsOn || !endsOn) return null;
  const start = Date.parse(startsOn);
  const end = Date.parse(endsOn);
  if (Number.isNaN(start) || Number.isNaN(end) || end <= start) return null;
  return Math.min(1, Math.max(0, (now.getTime() - start) / (end - start)));
}
