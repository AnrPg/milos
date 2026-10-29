import type { Closing, FiscalDocument, FiscalDocumentDetail, FiscalDocumentLine, RefundOption, Transmission } from "@/api/fiscal";

/**
 * Mockup s2, option A as the product owner changed it: the list of fiscal
 * documents grouped per day, each day «Κλειστή» when a day closing exists
 * (ADR-242) and «Ανοιχτή» otherwise.
 */

export type DayGroup = { date: string; closed: boolean; documents: FiscalDocument[] };

/** Days newest first, documents in the order the API gave them (newest first). */
export function groupByDay(documents: FiscalDocument[], closings: Pick<Closing, "period_kind" | "period_start" | "period_end">[]): DayGroup[] {
  const closedDays = new Set<string>();
  for (const closing of closings) {
    if (closing.period_kind !== "day") continue;
    closedDays.add(closing.period_start);
  }
  const byDay = new Map<string, FiscalDocument[]>();
  for (const document of documents) {
    const list = byDay.get(document.issue_date) ?? [];
    list.push(document);
    byDay.set(document.issue_date, list);
  }
  return [...byDay.keys()]
    .sort((a, b) => (a < b ? 1 : a > b ? -1 : 0))
    .map((date) => ({ date, closed: closedDays.has(date), documents: byDay.get(date)! }));
}

/** How a document's report to the tax authority stands, for its pill. */
export type TransmissionState = "none" | "accepted" | "pending" | "rejected";

export function transmissionState(transmission: Pick<Transmission, "status"> | null | undefined): TransmissionState {
  if (!transmission) return "none";
  if (transmission.status === "accepted") return "accepted";
  if (transmission.status === "rejected") return "rejected";
  return "pending";
}

/** Staff may send again only what was rejected or failed (ADR-243). */
export function canRetry(transmission: Pick<Transmission, "status"> | null | undefined) {
  return transmission?.status === "rejected" || transmission?.status === "failed";
}

export type KindFilter = "all" | "receipt" | "invoice" | "credit_note" | "pending";

export function matchesFilter(document: FiscalDocument, filter: KindFilter) {
  if (filter === "all") return true;
  if (filter === "pending") return transmissionState(document.transmission) === "pending";
  return document.kind === filter;
}

/** The first and last day of the month `offset` months from `today` (YYYY-MM-DD). */
export function monthRange(today: string, offset = 0): { from: string; to: string } {
  const [year, month] = today.split("-").map(Number);
  const first = new Date(Date.UTC(year, month - 1 + offset, 1));
  const last = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0));
  return { from: iso(first), to: iso(last) };
}

export function yearRange(today: string): { from: string; to: string } {
  const year = today.slice(0, 4);
  return { from: `${year}-01-01`, to: `${year}-12-31` };
}

function iso(date: Date) {
  return date.toISOString().slice(0, 10);
}

/** Today in the viewer's time zone, YYYY-MM-DD. */
export function localToday(now = new Date()) {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/** The amount already credited back on a document, positive cents. */
export function creditedCents(document: Pick<FiscalDocumentDetail, "credit_notes">) {
  return (document.credit_notes ?? []).reduce((sum, note) => sum + Math.abs(note.gross_cents), 0);
}

/** Whether a credit note can still be issued for the document. */
export function canCredit(document: Pick<FiscalDocumentDetail, "kind" | "gross_cents" | "credit_notes">) {
  return document.kind !== "credit_note" && creditedCents(document) < Math.abs(document.gross_cents);
}

/** The credit note's amount: every line, or only the ticked ones. */
export function creditAmount(lines: Pick<FiscalDocumentLine, "position" | "gross_cents">[], full: boolean, picked: ReadonlySet<number>) {
  return lines.filter((line) => full || picked.has(line.position)).reduce((sum, line) => sum + line.gross_cents, 0);
}

/** The lines a partial credit note sends (whole quantities). */
export function creditLines(lines: Pick<FiscalDocumentLine, "position" | "quantity">[], picked: ReadonlySet<number>) {
  return lines.filter((line) => picked.has(line.position)).map((line) => ({ position: line.position, quantity: line.quantity }));
}

/** The buyer's name as printed, when the document has one. */
export function buyerName(document: Pick<FiscalDocument, "buyer">): string | null {
  const name = document.buyer?.name;
  return typeof name === "string" && name.trim() ? name : null;
}

/** The buyer's email as printed, the default address of «Αποστολή με email». */
export function buyerEmail(document: Pick<FiscalDocument, "buyer">): string | null {
  const email = document.buyer?.email;
  return typeof email === "string" && email.trim() ? email.trim() : null;
}

/** The card a refund goes back to, as the mockup prints it: «••4242». */
export function cardLabel(option: Pick<RefundOption, "card_last4" | "card_brand">): string {
  if (option.card_last4) return `••${option.card_last4}`;
  return option.card_brand?.trim() || "••••";
}

const PROVIDER_NAMES: Record<string, string> = { viva: "Viva", stripe: "Stripe", sandbox: "Sandbox" };

/** A payment provider's brand name («Μέσω Viva»); brand names are not translated. */
export function providerName(provider: string): string {
  return PROVIDER_NAMES[provider] ?? provider.charAt(0).toUpperCase() + provider.slice(1);
}

/** The seller as printed on the document, in one line. */
export function sellerLine(seller: Record<string, unknown>): string {
  const text = (key: string) => (typeof seller[key] === "string" && (seller[key] as string).trim() ? (seller[key] as string) : null);
  const place = [text("postal_code"), text("city")].filter(Boolean).join(" ");
  const street = [text("street"), text("building_number")].filter(Boolean).join(" ");
  return [text("legal_name"), text("tax_id"), text("tax_office"), [street, place].filter(Boolean).join(", ")]
    .filter(Boolean)
    .join(" · ");
}

/** A tax rate in basis points as a percentage: 2400 → "24", 1300 → "13", 550 → "5.5". */
export function ratePercent(rateBp: number) {
  return String(rateBp / 100);
}

/** A `YYYY-MM-DD` day as midnight UTC, for formatting a day without shifting it. */
export function utcDay(iso: string): Date {
  const [year, month, day] = iso.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day));
}

/** The audit archive's file name for a period. */
export function archiveFileName(from: string, to: string): string {
  return ["palee-fiscal", from, to].join("-") + ".zip";
}
