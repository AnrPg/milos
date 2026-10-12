"use client";

import { useTranslations } from "next-intl";

/**
 * ADR-108: previews a server-rendered refund receipt in a fully sandboxed
 * iframe (no scripts, no same-origin access) and opens it in its own tab for
 * printing or saving as PDF.
 */
export function RefundReceiptDocumentDialog({
  html,
  receiptNumber,
  onClose,
}: {
  html: string;
  receiptNumber: string;
  onClose: () => void;
}) {
  const t = useTranslations("FinanceAccounting");

  const openPrintable = () => {
    const url = URL.createObjectURL(new Blob([html], { type: "text/html" }));
    window.open(url, "_blank", "noopener");
    window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
  };

  return (
    <div
      aria-label={t("documentTitle", { number: receiptNumber })}
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      role="dialog"
      style={{ background: "color-mix(in srgb, var(--bg) 70%, transparent)" }}
    >
      <div
        className="flex h-[85vh] w-full max-w-3xl flex-col gap-3 rounded-[2rem] p-5"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>
            {t("documentTitle", { number: receiptNumber })}
          </h2>
          <div className="flex gap-2">
            <button
              className="rounded-full px-4 py-2 text-sm font-semibold"
              onClick={openPrintable}
              style={{ background: "var(--text)", color: "var(--bg)" }}
              type="button"
            >
              {t("openPrintable")}
            </button>
            <button
              className="rounded-full px-4 py-2 text-sm font-semibold"
              onClick={onClose}
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
              type="button"
            >
              {t("close")}
            </button>
          </div>
        </div>
        <iframe
          className="w-full flex-1 rounded-xl"
          sandbox=""
          srcDoc={html}
          style={{ border: "1px solid var(--border)", background: "#fff" }}
          title={t("documentTitle", { number: receiptNumber })}
        />
      </div>
    </div>
  );
}
