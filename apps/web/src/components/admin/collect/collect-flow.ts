import type { DeskOptions, DeskPerson, TerminalPayment, TerminalStart } from "@/api/desk-collect";

/*
 * «Είσπραξη» on the staff phone (mockup pilot-gaps screen 2, alternative A):
 * Ποιος › Τι › Έλεγχος › Viva.com Terminal › Αποτέλεσμα. The pure rules of
 * the flow, kept apart from the screens so they are tested on their own.
 */

export type Step = "who" | "what" | "confirm" | "wait" | "result";

/** Who pays: a person of the box (member, athlete or guest) or a walk-in. */
export type Payer =
  | { kind: "person"; userId: string; name: string; relation: DeskPerson["relation"] }
  | { kind: "walk_in" };

export type ChargeCategory = NonNullable<TerminalStart["charge_category"]>;

export const CHARGE_CATEGORIES: ChargeCategory[] = ["product", "personal_training", "event", "other"];

/** One line of «Τι πληρώνει;». */
export type Choice =
  | { key: string; kind: "renewal"; purposeId: string; name: string; amountCents: number; currency: string }
  | { key: string; kind: "invoice"; purposeId: string; number: string | null; description: string | null; amountCents: number; currency: string }
  | { key: string; kind: "order"; purposeId: string; number: number; summary: string; amountCents: number; currency: string }
  | { key: "package"; kind: "package" }
  | { key: "free"; kind: "free" };

export type FreeSale = { description: string; amount: string; category: ChargeCategory };

export const FREE_SALE_MAX = 120;

/**
 * What the payer can pay, in the mockup's order: the suggested renewal,
 * unpaid invoices, orders waiting at the desk, another package (members and
 * guests only) and a free amount. A walk-in pays only an order or a free
 * sale (ADR-264).
 */
export function choicesFor(options: DeskOptions | null | undefined, payer: Payer): Choice[] {
  const choices: Choice[] = [];
  const person = payer.kind === "person";
  if (options && person && options.renewal) {
    const renewal = options.renewal;
    choices.push({ key: `renewal:${renewal.id}`, kind: "renewal", purposeId: renewal.id, name: renewal.name, amountCents: renewal.price_cents, currency: renewal.currency });
  }
  if (options && person) {
    for (const invoice of options.invoices) {
      if (invoice.balance_due_cents <= 0) continue;
      choices.push({
        key: `invoice:${invoice.id}`,
        kind: "invoice",
        purposeId: invoice.id,
        number: invoice.number,
        description: invoice.description,
        amountCents: invoice.balance_due_cents,
        currency: invoice.currency,
      });
    }
  }
  for (const order of options?.shop_orders ?? []) {
    choices.push({ key: `order:${order.id}`, kind: "order", purposeId: order.id, number: order.number, summary: order.summary, amountCents: order.total_cents, currency: order.currency });
  }
  if (options && person && options.packages.length > 0) choices.push({ key: "package", kind: "package" });
  choices.push({ key: "free", kind: "free" });
  return choices;
}

/** The suggested line: the renewal when there is one, else the first line. */
export function defaultChoice(choices: Choice[]): Choice | null {
  return choices.find((choice) => choice.kind === "renewal") ?? choices[0] ?? null;
}

/** «12», «12,5», «12.50» → cents; anything else (or ≤ 0) → null. */
export function parseAmountCents(text: string): number | null {
  const clean = text.replace(/\s/g, "").replace(/[€$£]/g, "");
  if (!/^\d{1,6}([.,]\d{1,2})?$/.test(clean)) return null;
  const [whole, fraction = ""] = clean.split(/[.,]/);
  const cents = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
  return cents > 0 ? cents : null;
}

export type FreeSaleErrors = Partial<Record<"description" | "amount", "descriptionRequired" | "amountRequired">>;

/** The free-sale form's errors, shown under their field. */
export function freeSaleErrors(sale: FreeSale): FreeSaleErrors {
  const errors: FreeSaleErrors = {};
  const description = sale.description.trim();
  if (description === "" || description.length > FREE_SALE_MAX) errors.description = "descriptionRequired";
  if (parseAmountCents(sale.amount) === null) errors.amount = "amountRequired";
  return errors;
}

export type Purchase = { choice: Choice; packageId: string | null; free: FreeSale };

/** The amount of the picked line, or null while it is incomplete. */
export function pickedAmount(pick: Purchase, options: DeskOptions | null | undefined): { cents: number; currency: string } | null {
  const { choice } = pick;
  if (choice.kind === "free") {
    const cents = parseAmountCents(pick.free.amount);
    return cents === null ? null : { cents, currency: options?.packages[0]?.currency ?? options?.renewal?.currency ?? "EUR" };
  }
  if (choice.kind === "package") {
    const chosen = options?.packages.find((entry) => entry.id === pick.packageId);
    return chosen ? { cents: chosen.price_cents, currency: chosen.currency } : null;
  }
  return { cents: choice.amountCents, currency: choice.currency };
}

/** The body of `POST /admin/payments/terminal` for the picked line. */
export function startBody(pick: Purchase, payer: Payer, options: DeskOptions | null | undefined, idempotencyKey: string): TerminalStart | null {
  const amount = pickedAmount(pick, options);
  if (!amount) return null;
  const userId = payer.kind === "person" ? payer.userId : null;
  const base = { amount_cents: amount.cents, idempotency_key: idempotencyKey, user_id: userId, started_on: "phone" as const };
  switch (pick.choice.kind) {
    case "renewal":
      return { ...base, purpose: "membership_package", purpose_id: pick.choice.purposeId };
    case "package":
      return { ...base, purpose: "membership_package", purpose_id: pick.packageId };
    case "invoice":
      return { ...base, purpose: "finance_invoice", purpose_id: pick.choice.purposeId };
    case "order":
      return { ...base, purpose: "shop_order", purpose_id: pick.choice.purposeId };
    case "free":
      if (Object.keys(freeSaleErrors(pick.free)).length > 0) return null;
      return { ...base, purpose: "free_sale", description: pick.free.description.trim(), charge_category: pick.free.category };
  }
}

export type Outcome = "waiting" | "unconfirmed" | "paid" | "cancelled" | "declined" | "mismatch" | "failed";

const DECLINED = new Set(["terminal_declined", "terminal_failed"]);

/** What the result screen shows for a terminal payment. */
export function outcomeOf(payment: Pick<TerminalPayment, "status" | "failure_code">): Outcome {
  switch (payment.status) {
    case "succeeded":
      return "paid";
    case "cancelled":
      return "cancelled";
    case "awaiting_payer":
    case "processing":
      return payment.failure_code === "terminal_unconfirmed" ? "unconfirmed" : "waiting";
    case "failed":
      if (payment.failure_code === "amount_mismatch") return "mismatch";
      return payment.failure_code && DECLINED.has(payment.failure_code) ? "declined" : "failed";
    default:
      return "failed";
  }
}


/** Everything the card paid: the amount, the card surcharge and the tip. */
export function cardTotalCents(payment: Pick<TerminalPayment, "amount_cents" | "tip_cents" | "surcharge_cents">): number {
  return payment.amount_cents + (payment.surcharge_cents ?? 0) + (payment.tip_cents ?? 0);
}

/** Whose the tip is, as the person looking at the phone reads it (ADR-272). */
export function tipOwner(
  payment: Pick<TerminalPayment, "tip_cents" | "tip_attribution" | "tip_recipient_user_id">,
  viewerId: string | null | undefined,
): "you" | "desk" | "staff" | null {
  if (!payment.tip_cents) return null;
  if (payment.tip_recipient_user_id && payment.tip_recipient_user_id === viewerId) return "you";
  if (payment.tip_attribution === "front_desk_role") return "desk";
  return "staff";
}

/** A fresh idempotency key for one attempt. */
export function newAttemptKey(): string {
  const random = typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  return `collect-${random}`;
}

/** «ΜΚ» for «Μαρία Κωνσταντίνου». */
export function initials(name: string | null | undefined): string {
  const parts = (name ?? "").trim().split(/\s+/).filter(Boolean);
  return parts
    .slice(0, 2)
    .map((part) => part[0]!.toLocaleUpperCase())
    .join("");
}

/** A simple shape check before the API sees an email. */
export function looksLikeEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim());
}
