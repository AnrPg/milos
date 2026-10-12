"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { fetchMyRefundReceiptDocument, listMyRefundReceipts } from "@/api/finance-accounting";
import { RefundReceiptDocumentDialog } from "@/components/finance/RefundReceiptDocumentDialog";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { accountingErrorKey, formatMinorUnits } from "@/lib/finance-accounting";

/** ADR-108: the signed-in member's own refund receipts on the billing page. */
export function MyRefundReceipts() {
  const t = useTranslations("FinanceAccounting");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const [document, setDocument] = useState<{ html: string; number: string } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const receiptsQuery = useQuery({
    queryKey: ["me", "finance", "refund-receipts"],
    enabled: Boolean(token),
    queryFn: () => listMyRefundReceipts(token!),
  });

  const receipts = receiptsQuery.data?.refund_receipts ?? [];

  const open = async (id: string, number: string) => {
    setError(null);
    try {
      setDocument({ html: await fetchMyRefundReceiptDocument(token!, id, locale), number });
    } catch (cause) {
      setError(t(accountingErrorKey(cause)));
    }
  };

  if (receiptsQuery.isLoading) return null;

  return (
    <section className="flex flex-col gap-2">
      <h2 className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>{t("myReceiptsTitle")}</h2>
      {error ? (
        <p className="text-sm" role="alert" style={{ color: "var(--danger)" }}>{error}</p>
      ) : null}
      {receipts.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("myReceiptsEmpty")}</p>
      ) : (
        receipts.map((receipt) => (
          <div
            className="flex items-center justify-between rounded-xl px-4 py-3"
            key={receipt.id}
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <div className="flex flex-col gap-0.5">
              <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                {receipt.receipt_number} · {formatMinorUnits(locale, receipt.amount_cents, receipt.currency)}
              </span>
              <span className="text-xs" style={{ color: "var(--dim)" }}>
                {receipt.issued_at.slice(0, 10)}
                {receipt.invoice_number ? ` · ${receipt.invoice_number}` : ""}
              </span>
            </div>
            <button
              className="rounded-full px-3 py-1 text-xs font-semibold"
              onClick={() => void open(receipt.id, receipt.receipt_number)}
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
              type="button"
            >
              {t("viewDocument")}
            </button>
          </div>
        ))
      )}
      {document ? (
        <RefundReceiptDocumentDialog html={document.html} onClose={() => setDocument(null)} receiptNumber={document.number} />
      ) : null}
    </section>
  );
}
