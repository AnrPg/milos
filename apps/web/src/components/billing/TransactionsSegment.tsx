"use client";

import { useInfiniteQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useState } from "react";

import {
  fetchMyTransactions,
  fetchProviderRefundReceiptDocument,
  getProviderInvoiceDownloadUrl,
  myTransactionsKey,
  type BillingTransaction,
  type BillingTransactionKind,
} from "@/api/my-billing";
import { formatDate, StatusBadge } from "@/components/finance/MembershipEntitlement";
import { RefundReceiptDocumentDialog } from "@/components/finance/RefundReceiptDocumentDialog";
import { HubCard } from "@/components/member-app/HubParts";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";

import { totalsByCurrency, TRANSACTION_FILTER_THRESHOLD } from "./billing-model";
import { Detail, Empty } from "./parts";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

type T = ReturnType<typeof useTranslations<"Billing">>;

type InvoiceLine = {
  description?: string | null;
  quantity?: number | null;
  unit_amount_cents?: number | null;
  total_cents?: number | null;
};

type Details = {
  document_kind?: "invoice" | "receipt";
  invoice_number?: string | null;
  due_date?: string | null;
  balance_due_cents?: number;
  downloadable?: boolean;
  lines?: InvoiceLine[];
  payment_method?: string | null;
  reason?: string | null;
  refund_receipt_id?: string | null;
  receipt_number?: string | null;
};

const details = (entry: BillingTransaction) => (entry.details ?? {}) as Details;

/**
 * Συναλλαγές: the person's complete money history as one chronological feed
 * (invoices with their lines, payments, refunds, credit, event tickets and
 * their refunds at any host). A row opens its details and download; a kind
 * filter appears once there are more than ten entries, and the totals sum
 * what is on screen per currency.
 */
export function TransactionsSegment({ organizationId }: { organizationId: string }) {
  const t = useTranslations("Billing");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [kind, setKind] = useState<BillingTransactionKind | "all">("all");
  const [open, setOpen] = useState<BillingTransaction | null>(null);

  const feed = useInfiniteQuery({
    queryKey: myTransactionsKey(organizationId, kind === "all" ? null : kind),
    enabled: Boolean(token),
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) =>
      fetchMyTransactions(token!, { organizationId, kind: kind === "all" ? null : kind, cursor: pageParam }),
    getNextPageParam: (page) => page.next_cursor ?? null,
  });

  if (feed.isPending) return <Empty>{t("loading")}</Empty>;
  if (feed.isError) return <ErrorNotice>{t("loadFailed")}</ErrorNotice>;

  const pages = feed.data.pages;
  const entries = pages.flatMap((page) => page.transactions);
  const first = pages[0];
  const total = first?.total ?? 0;
  const kinds = first?.kinds ?? [];

  if (total === 0) return <Empty>{t("noTransactions")}</Empty>;

  const totals = totalsByCurrency(entries);

  return (
    <>
      {total > TRANSACTION_FILTER_THRESHOLD ? (
        <Select
          aria-label={t("filterTransactions")}
          value={kind}
          onValueChange={(value) => setKind(value as BillingTransactionKind | "all")}
          className="min-h-11 w-full rounded-2xl px-3 text-sm font-semibold"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          <option value="all">{t("filterAll")}</option>
          {kinds.map((value) => (
            <option key={value} value={value}>
              {kindLabel(t, value)}
            </option>
          ))}
        </Select>
      ) : null}
      <HubCard>
        {first?.partial ? <p className="mb-2 text-xs" role="status" style={{ color: "var(--warning)" }}>{t("partial")}</p> : null}
        {entries.length === 0 ? (
          <Empty>{t("noTransactions")}</Empty>
        ) : (
          <ul className="flex flex-col">
            {entries.map((entry) => (
              <li key={entry.id} style={{ borderBottom: "1px solid var(--border)" }}>
                <button type="button" onClick={() => setOpen(entry)} className="flex min-h-12 w-full min-w-0 items-center gap-3 py-2.5 text-start">
                  <KindIcon kind={entry.kind} />
                  <span className="flex min-w-0 flex-1 flex-col">
                    <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{entryTitle(t, entry)}</span>
                    <span className="truncate text-xs" style={{ color: "var(--dim)" }}>
                      {[entry.counterparty.name ?? t("eventHost"), entry.date ? formatDate(locale, entry.date) : null].filter(Boolean).join(" · ")}
                    </span>
                  </span>
                  <span className="flex shrink-0 flex-col items-end gap-1">
                    <span
                      className="text-sm font-bold tabular-nums"
                      style={{ color: entry.amount_cents < 0 ? "var(--success)" : "var(--text)" }}
                    >
                      {formatMinorUnits(locale, entry.amount_cents, entry.currency)}
                    </span>
                    {entry.status ? <StatusBadge status={entry.status} /> : null}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}
        {totals.length > 0 ? (
          <p className="mt-3 text-xs font-semibold tabular-nums" style={{ color: "var(--text-soft)" }}>
            {t("shownTotal", { amounts: totals.map((sum) => formatMinorUnits(locale, sum.cents, sum.currency)).join(" · ") })}
          </p>
        ) : null}
        {feed.hasNextPage ? (
          <button
            type="button"
            onClick={() => void feed.fetchNextPage()}
            disabled={feed.isFetchingNextPage}
            className="mt-3 flex min-h-11 w-full items-center justify-center rounded-2xl text-sm font-semibold"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {feed.isFetchingNextPage ? t("loading") : t("loadMore")}
          </button>
        ) : null}
      </HubCard>
      {open ? <TransactionDialog entry={open} onClose={() => setOpen(null)} /> : null}
    </>
  );
}

function TransactionDialog({ entry, onClose }: { entry: BillingTransaction; onClose: () => void }) {
  const t = useTranslations("Billing");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);
  const [receipt, setReceipt] = useState<string | null>(null);
  const info = details(entry);
  const slug = entry.counterparty.slug;
  const canDownload =
    Boolean(slug) &&
    ((entry.kind === "invoice" && info.downloadable === true) || (entry.kind === "refund" && Boolean(info.refund_receipt_id)));

  async function download() {
    if (!tokens?.access_token || !slug) return;
    setBusy(true);
    setFailed(false);
    try {
      if (entry.kind === "refund" && info.refund_receipt_id) {
        setReceipt(await fetchProviderRefundReceiptDocument(tokens.access_token, slug, info.refund_receipt_id, locale));
      } else {
        const data = await getProviderInvoiceDownloadUrl(tokens.access_token, slug, entry.source_id);
        if (data?.download_url) window.open(data.download_url, "_blank", "noopener,noreferrer");
      }
    } catch {
      setFailed(true);
    } finally {
      setBusy(false);
    }
  }

  if (receipt) return <RefundReceiptDocumentDialog html={receipt} receiptNumber={info.receipt_number ?? ""} onClose={onClose} />;

  return (
    <Dialog
      onClose={onClose}
      title={entryTitle(t, entry)}
      closeLabel={t("close")}
      variant="sheet"
      size="sm"
      footer={
        <>
          <DialogButton onClick={onClose}>{t("close")}</DialogButton>
          {entry.source_url?.startsWith("/") ? (
            <Link
              href={entry.source_url}
              className="inline-flex min-h-11 items-center px-3 text-sm font-semibold"
              style={{ color: "var(--primary-strong)" }}
            >
              {t("view")} ›
            </Link>
          ) : null}
          {canDownload ? (
            <DialogButton tone="primary" onClick={() => void download()} disabled={busy}>
              {entry.kind === "refund" ? t("view") : t("download")}
            </DialogButton>
          ) : null}
        </>
      }
    >
      <dl className="flex flex-col gap-2 text-sm">
        <Detail label={t("kind")} value={kindLabel(t, entry.kind)} />
        <Detail label={t("counterparty")} value={entry.counterparty.name ?? t("eventHost")} />
        <Detail label={t("amount")} value={formatMinorUnits(locale, entry.amount_cents, entry.currency)} />
        <Detail label={t("date")} value={entry.date ? formatDate(locale, entry.date) : "—"} />
        {entry.status ? <Detail label={t("status")} value={<StatusBadge status={entry.status} />} /> : null}
        {info.due_date ? <Detail label={t("dueDate")} value={formatDate(locale, info.due_date)} /> : null}
        {(info.balance_due_cents ?? 0) > 0 ? (
          <Detail label={t("outstanding")} value={formatMinorUnits(locale, info.balance_due_cents ?? 0, entry.currency)} />
        ) : null}
        {info.payment_method ? <Detail label={t("method")} value={<SemanticLabel value={info.payment_method} />} /> : null}
        {info.receipt_number ? <Detail label={t("receipt")} value={info.receipt_number} /> : null}
        {info.reason ? <Detail label={t("reason")} value={info.reason} /> : null}
      </dl>
      {info.lines && info.lines.length > 0 ? (
        <div className="mt-4">
          <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("lines")}</p>
          <ul className="mt-1 flex flex-col">
            {info.lines.map((line, index) => (
              <li key={index} className="flex min-w-0 items-start justify-between gap-3 py-1.5 text-sm" style={{ borderBottom: "1px solid var(--border)" }}>
                <span className="min-w-0 break-words" style={{ color: "var(--text)" }}>
                  {line.description ?? "—"}
                  {line.quantity && line.quantity !== 1 && line.unit_amount_cents != null ? (
                    <span className="block text-xs" style={{ color: "var(--dim)" }}>
                      {t("lineQuantity", { quantity: line.quantity, amount: formatMinorUnits(locale, line.unit_amount_cents, entry.currency) })}
                    </span>
                  ) : null}
                </span>
                <span className="shrink-0 font-semibold tabular-nums">{formatMinorUnits(locale, line.total_cents ?? 0, entry.currency)}</span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
      {failed ? <ErrorNotice variant="field" className="mt-3">{t("downloadFailed")}</ErrorNotice> : null}
    </Dialog>
  );
}

export function kindLabel(t: T, kind: BillingTransactionKind) {
  switch (kind) {
    case "invoice":
      return t("invoice");
    case "payment":
      return t("payment");
    case "refund":
      return t("refund");
    case "credit":
      return t("creditEntry");
    case "event_payment":
      return t("eventPayment");
    case "event_refund":
      return t("eventRefund");
    case "shop_order":
      return t("shopOrder");
  }
}

function entryTitle(t: T, entry: BillingTransaction) {
  const info = details(entry);
  const label = entry.kind === "invoice" && info.document_kind === "receipt" ? t("receipt") : kindLabel(t, entry.kind);
  return entry.title ? `${label} · ${entry.title}` : label;
}

function KindIcon({ kind }: { kind: BillingTransactionKind }) {
  const glyph = { invoice: "🧾", payment: "€", refund: "↩", credit: "+", event_payment: "🎟", event_refund: "↩", shop_order: "🛍" }[kind];
  return (
    <span
      aria-hidden="true"
      className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-sm font-bold"
      style={{ background: "var(--panel-muted)", color: kind.endsWith("refund") || kind === "credit" ? "var(--success)" : "var(--text-soft)" }}
    >
      {glyph}
    </span>
  );
}
