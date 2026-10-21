import type { CorporateInvoiceDocument, CorporatePaymentMethod } from "@/api/payment-models";
import { PRINT_TOKENS, rgbChannels, type ThemeTokens } from "@/lib/theme";

/** A print colour (PRINT_TOKENS) as jsPDF RGB channels. */
const ink = (token: keyof ThemeTokens) => rgbChannels(PRINT_TOKENS[token]);

// ADR-098 corporate invoicing: the invoice PDF is produced in the browser with
// jsPDF and the DejaVu fonts (as in document-export.ts) so Greek prints. The
// layout is built by a pure function; the drawing below stays thin.

export type CorporateInvoicePdfLabels = {
  invoice: string;
  billTo: string;
  contact: string;
  email: string;
  issuedOn: string;
  dueOn: string;
  period: string;
  status: string;
  description: string;
  quantity: string;
  unitPrice: string;
  amount: string;
  seatLine: string;
  total: string;
  paid: string;
  balanceDue: string;
  payments: string;
  reference: string;
  footer: string;
  statuses: Record<CorporateInvoiceDocument["status"], string>;
  methods: Record<CorporatePaymentMethod, string>;
};

export type CorporateInvoiceLayout = {
  issuer: string;
  title: string;
  status: string;
  billToTitle: string;
  billTo: string[];
  meta: Array<[string, string]>;
  tableHead: [string, string, string, string];
  tableRows: Array<[string, string, string, string]>;
  totals: Array<{ label: string; value: string; strong: boolean }>;
  paymentsTitle: string;
  payments: string[];
  footer: string;
  filename: string;
};

function formatters(locale: string) {
  const money = new Intl.NumberFormat(locale, { style: "currency", currency: "EUR" });
  const date = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
  return {
    money: (cents: number) => money.format(cents / 100),
    date: (iso: string | null | undefined) => {
      if (!iso) return "—";
      const parsed = new Date(`${iso.slice(0, 10)}T00:00:00Z`);
      return Number.isNaN(parsed.getTime()) ? iso : date.format(parsed);
    },
  };
}

/** Builds every text shown on the PDF; no drawing. */
export function buildCorporateInvoiceLayout(
  invoice: CorporateInvoiceDocument,
  labels: CorporateInvoicePdfLabels,
  locale: string,
): CorporateInvoiceLayout {
  const format = formatters(locale);
  const seats = invoice.seats_billed;
  const unitCents =
    typeof invoice.unit_price_cents === "number"
      ? invoice.unit_price_cents
      : seats > 0
        ? Math.round(invoice.total_cents / seats)
        : 0;
  const number = invoice.invoice_number ?? invoice.id.slice(0, 8).toUpperCase();
  const period = `${format.date(invoice.period_start)} – ${format.date(invoice.period_end)}`;
  const standing = invoice.payments.filter((payment) => !payment.reversed_at);

  return {
    issuer: invoice.issuer.name,
    title: `${labels.invoice} ${number}`,
    status: `${labels.status}: ${labels.statuses[invoice.status]}`,
    billToTitle: labels.billTo,
    billTo: [
      invoice.client.company_name,
      invoice.client.contact_name ? `${labels.contact}: ${invoice.client.contact_name}` : null,
      invoice.client.billing_email ? `${labels.email}: ${invoice.client.billing_email}` : null,
    ].filter((line): line is string => Boolean(line)),
    meta: [
      [labels.issuedOn, format.date(invoice.issued_on)],
      [labels.dueOn, format.date(invoice.due_on)],
      [labels.period, period],
    ],
    tableHead: [labels.description, labels.quantity, labels.unitPrice, labels.amount],
    tableRows: [
      [
        [labels.seatLine, invoice.client.package_name].filter(Boolean).join(" · "),
        String(seats),
        format.money(unitCents),
        format.money(invoice.total_cents),
      ],
    ],
    totals: [
      { label: labels.total, value: format.money(invoice.total_cents), strong: false },
      { label: labels.paid, value: format.money(invoice.paid_cents), strong: false },
      { label: labels.balanceDue, value: format.money(invoice.balance_cents), strong: true },
    ],
    paymentsTitle: labels.payments,
    payments: standing.map((payment) =>
      [
        format.date(payment.paid_on),
        labels.methods[payment.payment_method],
        format.money(payment.amount_cents),
        payment.reference ? `${labels.reference}: ${payment.reference}` : null,
      ]
        .filter(Boolean)
        .join(" · "),
    ),
    footer: labels.footer,
    filename: `${number.replace(/[^\p{L}\p{N}-]+/gu, "-")}.pdf`,
  };
}

function arrayBufferToBase64(buffer: ArrayBuffer) {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(binary);
}

async function loadPdfFont(path: string) {
  try {
    const response = await fetch(path);
    if (!response.ok) return null;
    return await response.arrayBuffer();
  } catch {
    return null;
  }
}

/** Draws the layout on an A4 page and returns the PDF file. */
export async function renderCorporateInvoicePdf(layout: CorporateInvoiceLayout): Promise<File> {
  const { jsPDF } = await import("jspdf");
  const pdf = new jsPDF({ unit: "pt", format: "a4" });
  const [regularFont, boldFont] = await Promise.all([
    loadPdfFont("/fonts/DejaVuSans.ttf"),
    loadPdfFont("/fonts/DejaVuSans-Bold.ttf"),
  ]);
  const font = regularFont && boldFont ? "DejaVuSans" : "helvetica";
  if (regularFont && boldFont) {
    pdf.addFileToVFS("DejaVuSans.ttf", arrayBufferToBase64(regularFont));
    pdf.addFileToVFS("DejaVuSans-Bold.ttf", arrayBufferToBase64(boldFont));
    pdf.addFont("DejaVuSans.ttf", font, "normal");
    pdf.addFont("DejaVuSans-Bold.ttf", font, "bold");
  }
  const pageWidth = pdf.internal.pageSize.getWidth();
  const pageHeight = pdf.internal.pageSize.getHeight();
  const margin = 48;
  const right = pageWidth - margin;
  const bottom = pageHeight - 60;
  let y = 56;

  const text = (value: string, x: number, size: number, options: { bold?: boolean; align?: "left" | "right"; color?: [number, number, number] } = {}) => {
    pdf.setFont(font, options.bold ? "bold" : "normal");
    pdf.setFontSize(size);
    pdf.setTextColor(...(options.color ?? ink("text")));
    pdf.text(value, x, y, { align: options.align ?? "left" });
  };
  const ensureSpace = (height: number) => {
    if (y + height <= bottom) return;
    pdf.addPage();
    y = 56;
  };

  // The issuer and the (long) invoice number get their own lines so they
  // never overlap.
  text(layout.issuer, margin, 15, { bold: true });
  y += 26;
  text(layout.title, margin, 17, { bold: true, color: ink("primary") });
  text(layout.status, right, 9.5, { align: "right", color: ink("muted") });
  y += 34;

  const blockTop = y;
  text(layout.billToTitle.toLocaleUpperCase(), margin, 8, { bold: true, color: ink("muted") });
  y += 15;
  layout.billTo.forEach((line, index) => {
    text(line, margin, index === 0 ? 11.5 : 9.5, { bold: index === 0 });
    y += 15;
  });
  const billToBottom = y;
  y = blockTop;
  layout.meta.forEach(([label, value]) => {
    text(`${label}: ${value}`, right, 9.5, { align: "right", color: ink("textSoft") });
    y += 15;
  });
  y = Math.max(billToBottom, y) + 22;

  const columns = [margin, right - 230, right - 120, right];
  pdf.setFillColor(...ink("panelMuted"));
  pdf.rect(margin, y - 13, right - margin, 20, "F");
  layout.tableHead.forEach((head, index) => {
    text(head, index === 0 ? columns[0] + 6 : columns[index] - (index === 3 ? 6 : 0), 9, {
      bold: true,
      align: index === 0 ? "left" : "right",
      color: ink("textSoft"),
    });
  });
  y += 22;
  for (const row of layout.tableRows) {
    ensureSpace(20);
    const description = pdf.splitTextToSize(row[0], columns[1] - columns[0] - 40) as string[];
    pdf.setFont(font, "normal");
    pdf.setFontSize(10);
    pdf.setTextColor(...ink("text"));
    pdf.text(description, columns[0] + 6, y);
    row.slice(1).forEach((cell, index) => text(cell, columns[index + 1] - (index === 2 ? 6 : 0), 10, { align: "right" }));
    y += description.length * 14 + 6;
  }
  pdf.setDrawColor(...ink("border"));
  pdf.line(margin, y, right, y);
  y += 20;

  for (const total of layout.totals) {
    ensureSpace(18);
    text(total.label, right - 160, total.strong ? 11 : 9.5, { bold: total.strong, align: "right" });
    text(total.value, right - 6, total.strong ? 11 : 9.5, { bold: total.strong, align: "right" });
    y += total.strong ? 20 : 16;
  }

  if (layout.payments.length > 0) {
    y += 14;
    ensureSpace(30);
    text(layout.paymentsTitle, margin, 11, { bold: true, color: ink("primary") });
    y += 16;
    for (const payment of layout.payments) {
      ensureSpace(14);
      text(payment, margin, 9.5, { color: ink("textSoft") });
      y += 14;
    }
  }

  const pages = pdf.getNumberOfPages();
  for (let page = 1; page <= pages; page += 1) {
    pdf.setPage(page);
    pdf.setDrawColor(...ink("border"));
    pdf.line(margin, pageHeight - 37, right, pageHeight - 37);
    pdf.setFont(font, "normal");
    pdf.setFontSize(8);
    pdf.setTextColor(...ink("dim"));
    pdf.text(layout.footer, margin, pageHeight - 24);
    pdf.text(`${page} / ${pages}`, right, pageHeight - 24, { align: "right" });
  }

  const blob = pdf.output("blob");
  return new File([blob], layout.filename, { type: "application/pdf" });
}
