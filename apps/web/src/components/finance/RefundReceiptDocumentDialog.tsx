"use client";

import { useTranslations } from "next-intl";
import { Dialog } from "@/components/ui/Dialog";

/**
 * ADR-126: previews a server-rendered refund receipt in a fully sandboxed
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
    <Dialog
      onClose={onClose}
      title={t("documentTitle", { number: receiptNumber })}
      ariaLabel={t("documentTitle", { number: receiptNumber })}
      closeLabel={t("close")}
      size="3xl"
      variant="center"
      panelClassName="h-[85dvh]"
      plainBody
      bodyClassName="px-5 pb-5 sm:px-6"
      headerActions={
        <button
          className="rounded-full px-4 py-2 text-sm font-semibold"
          onClick={openPrintable}
          style={{ background: "var(--text)", color: "var(--bg)" }}
          type="button"
        >
          {t("openPrintable")}
        </button>
      }
    >
      <iframe
        className="w-full flex-1 rounded-xl"
        sandbox=""
        srcDoc={html}
        style={{ border: "1px solid var(--border)", background: "var(--paper)" }}
        title={t("documentTitle", { number: receiptNumber })}
      />
    </Dialog>
  );
}
