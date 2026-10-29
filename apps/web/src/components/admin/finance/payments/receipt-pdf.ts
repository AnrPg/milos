import type { FinanceReceipt } from "@/api/finance";
import { receiptPackageLabel } from "@/components/admin-finance-receipt";
import { generateExportFile, type ExportDocument } from "@/lib/document-export";

export type ReceiptCopy = {
  receipt: string;
  documentTitle: string;
  paymentReceived: string;
  reference: string;
  date: string;
  amountReceived: string;
  package: string;
  payment: string;
  purpose: string;
  method: string;
  status: string;
  paid: string;
  footer: string;
};

/** The receipt as a PDF the member can be handed or sent (ADR-189 receipt mode). */
export function receiptDocument(
  receipt: Pick<FinanceReceipt, "reference" | "issued_on" | "amount_cents" | "currency" | "description"> &
    Partial<Pick<FinanceReceipt, "package_name" | "package_code_snapshot" | "package_family_snapshot">>,
  uiLocale: string,
  copy: ReceiptCopy,
  methodLabel: string,
): ExportDocument {
  const amount = new Intl.NumberFormat(uiLocale, { style: "currency", currency: receipt.currency }).format(receipt.amount_cents / 100);
  const selectedPackage = receiptPackageLabel(receipt);
  return {
    icon: "✓",
    category: copy.receipt,
    title: copy.documentTitle,
    subtitle: copy.paymentReceived,
    metadata: [
      { label: copy.reference, value: receipt.reference },
      { label: copy.date, value: receipt.issued_on },
      { label: copy.amountReceived, value: amount },
      ...(selectedPackage ? [{ label: copy.package, value: selectedPackage }] : []),
    ],
    sections: [
      {
        icon: "€",
        title: copy.payment,
        items: [
          { label: copy.purpose, value: receipt.description },
          { label: copy.method, value: methodLabel },
          { label: copy.status, value: copy.paid },
        ],
      },
    ],
    footer: copy.footer,
  };
}

export async function downloadExportDocument(document: ExportDocument) {
  const file = await generateExportFile(document, "pdf");
  const url = URL.createObjectURL(file);
  const anchor = window.document.createElement("a");
  anchor.href = url;
  anchor.download = file.name;
  anchor.click();
  URL.revokeObjectURL(url);
}
