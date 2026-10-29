"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";

import type { BillingInvoice, BillingProvider } from "@/api/my-billing";
import { fetchInvoiceTerms, invoiceTermsKey, termsLanguage } from "@/api/my-payments";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";

import { InvoicePaySheet } from "./InvoicePaySheet";

const CLOSED = new Set(["paid", "void", "voided", "draft", "cancelled", "written_off"]);

/** The open invoice to pay first: the one due soonest. */
export function nextOpenInvoice(invoices: BillingInvoice[]): BillingInvoice | null {
  const open = invoices.filter((invoice) => invoice.balance_due_cents > 0 && !CLOSED.has(invoice.status));
  open.sort((a, b) => (a.due_date ?? a.issue_date ?? "").localeCompare(b.due_date ?? b.issue_date ?? ""));
  return open[0] ?? null;
}

/**
 * «Πληρωμή» for what the member owes (ADR-246), when the box takes online
 * payments; otherwise the page's «pay at the box» line stays.
 */
export function PayOpenInvoice({ provider, fallback }: { provider: BillingProvider; fallback: ReactNode }) {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  const language = termsLanguage(locale);
  const token = useSession().tokens?.access_token ?? null;
  const [open, setOpen] = useState(false);
  const invoice = nextOpenInvoice(provider.invoices);

  const terms = useQuery({
    queryKey: invoiceTermsKey(provider.slug, invoice?.id ?? "none", language),
    enabled: Boolean(token && invoice),
    queryFn: () => fetchInvoiceTerms(token!, provider.slug, invoice!.id, language),
    retry: false,
  });

  if (!invoice || !terms.data?.available) return <>{fallback}</>;
  const label = invoice.invoice_number ? t("invoiceLabel", { number: invoice.invoice_number }) : t("invoice");

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="mt-2 flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        data-testid="pay-open-invoice"
      >
        {t("pay", { amount: formatMinorUnits(locale, terms.data.amount_cents, terms.data.currency) })}
      </button>
      {open ? <InvoicePaySheet slug={provider.slug} invoiceId={invoice.id} label={label} onClose={() => setOpen(false)} /> : null}
    </>
  );
}
