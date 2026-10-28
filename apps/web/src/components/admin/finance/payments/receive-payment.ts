import type { FinanceRecord } from "@/api/finance";

/**
 * ADR-222: «Είσπραξη», money a client handed over at the desk. These are the
 * pure parts of the form: what the money can be for, what it pre-fills, what
 * the box's billing setup will issue and the body sent to
 * `POST /admin/finance/members/:id/payments/receive`.
 */

export const PAYMENT_METHODS = ["cash", "card_manual", "bank_transfer", "other"] as const;
export type PaymentMethod = (typeof PAYMENT_METHODS)[number];

export type PaymentPurpose =
  | { kind: "invoice"; id: string; number: string; amountCents: number; status: string }
  | { kind: "package"; id: string; name: string; amountCents: number }
  | { kind: "other" };

/** The document a payment leaves behind; the API decides, this only previews it. */
export type PaymentOutcome = "settles_invoice" | "receipt" | "invoice";

export type ReceivePaymentForm = {
  purpose: string;
  amount: string;
  method: PaymentMethod;
  paidOn: string;
  description: string;
  chargeCategory: string;
  notes: string;
};

export type ReceivePaymentField = "purpose" | "amount_cents" | "payment_method" | "description";

const OPEN_INVOICE_STATUSES = new Set(["issued", "partially_paid", "overdue"]);

function text(record: FinanceRecord | null | undefined, key: string) {
  const value = record?.[key];
  return value === null || value === undefined ? "" : String(value);
}

function cents(record: FinanceRecord | null | undefined, key: string) {
  const value = record?.[key];
  return typeof value === "number" ? value : Number(value ?? 0) || 0;
}

/**
 * What the money can be for: the client's open invoices (oldest first, the
 * one to settle first), then their active πακέτα συνδρομής, then anything
 * else staff describe.
 */
export function paymentPurposes(
  profile: FinanceRecord | null | undefined,
  packageName: (subscription: FinanceRecord) => string,
): PaymentPurpose[] {
  const invoices = ((profile?.invoices as FinanceRecord[] | undefined) ?? [])
    .filter((invoice) => OPEN_INVOICE_STATUSES.has(text(invoice, "status")) && cents(invoice, "balance_due_cents") > 0)
    .sort((a, b) => text(a, "due_date").localeCompare(text(b, "due_date")))
    .map<PaymentPurpose>((invoice) => ({
      kind: "invoice",
      id: text(invoice, "id"),
      number: text(invoice, "invoice_number") || text(invoice, "id"),
      amountCents: cents(invoice, "balance_due_cents"),
      status: text(invoice, "status"),
    }));

  const packages = ((profile?.package_subscriptions as FinanceRecord[] | undefined) ?? [])
    .filter((subscription) => text(subscription, "status") === "active")
    .map<PaymentPurpose>((subscription) => ({
      kind: "package",
      id: text(subscription, "id"),
      name: packageName(subscription),
      amountCents: cents(subscription, "price_cents_snapshot"),
    }));

  return [...invoices, ...packages, { kind: "other" }];
}

export function purposeValue(purpose: PaymentPurpose): string {
  return purpose.kind === "other" ? "other" : `${purpose.kind}:${purpose.id}`;
}

export function findPurpose(purposes: PaymentPurpose[], value: string): PaymentPurpose {
  return purposes.find((purpose) => purposeValue(purpose) === value) ?? { kind: "other" };
}

/** «12,50» or «12.50» → 1250; null when it is not an amount above zero. */
export function parseAmountCents(value: string): number | null {
  const normalized = value.trim().replace(/\s/g, "").replace(",", ".");
  if (!/^\d+(\.\d{1,2})?$/.test(normalized)) return null;
  const amount = Math.round(Number(normalized) * 100);
  return amount > 0 ? amount : null;
}

export function amountInput(amountCents: number): string {
  return amountCents > 0 ? (amountCents / 100).toFixed(2) : "";
}

/** A fresh form: the first purpose (the oldest open invoice, if any) and cash. */
export function initialForm(purposes: PaymentPurpose[]): ReceivePaymentForm {
  const first = purposes[0] ?? { kind: "other" };
  return {
    purpose: purposeValue(first),
    amount: first.kind === "other" ? "" : amountInput(first.amountCents),
    method: "cash",
    paidOn: "",
    description: "",
    chargeCategory: "",
    notes: "",
  };
}

/** Picking a purpose fills in what is owed for it. */
export function choosePurpose(form: ReceivePaymentForm, purposes: PaymentPurpose[], value: string): ReceivePaymentForm {
  const purpose = findPurpose(purposes, value);
  return {
    ...form,
    purpose: value,
    amount: purpose.kind === "other" ? form.amount : amountInput(purpose.amountCents),
  };
}

export function outcome(documentMode: string | null | undefined, purpose: PaymentPurpose): PaymentOutcome {
  if (purpose.kind === "invoice") return "settles_invoice";
  return documentMode === "receipt" ? "receipt" : "invoice";
}

/** What must be filled in before the form can be sent; field → message key. */
export function missingFields(form: ReceivePaymentForm, purpose: PaymentPurpose): Partial<Record<ReceivePaymentField, string>> {
  const missing: Partial<Record<ReceivePaymentField, string>> = {};
  const amountCents = parseAmountCents(form.amount);
  if (amountCents === null) missing.amount_cents = "amountInvalid";
  else if (purpose.kind === "invoice" && amountCents > purpose.amountCents) missing.amount_cents = "amountAboveBalance";
  if (purpose.kind === "other" && !form.description.trim()) missing.description = "descriptionRequired";
  return missing;
}

export function receiveBody(form: ReceivePaymentForm, purpose: PaymentPurpose, idempotencyKey: string): FinanceRecord {
  const body: FinanceRecord = {
    amount_cents: parseAmountCents(form.amount),
    payment_method: form.method,
    paid_on: form.paidOn || null,
    notes: form.notes.trim() || null,
    idempotency_key: idempotencyKey,
  };
  if (purpose.kind === "invoice") body.finance_invoice_id = purpose.id;
  if (purpose.kind === "package") body.membership_package_subscription_id = purpose.id;
  if (purpose.kind === "other") {
    body.description = form.description.trim();
    if (form.chargeCategory) body.charge_category = form.chargeCategory;
  }
  return body;
}

/** The form field an API error belongs to, so its reason shows under it. */
export function fieldForErrorCode(code: string | undefined): ReceivePaymentField | null {
  switch (code) {
    case "invalid_payment_amount":
    case "payment_exceeds_invoice_balance":
      return "amount_cents";
    case "invalid_payment_method":
      return "payment_method";
    case "payment_purpose_required":
      return "description";
    case "invoice_already_paid":
    case "invoice_void":
      return "purpose";
    default:
      return null;
  }
}
