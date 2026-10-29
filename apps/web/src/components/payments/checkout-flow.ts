// Member › paying online (ADR-246/248/256; mockup s4 option B): the pure
// parts of the flow, kept apart from the screens so they can be tested.
import { ApiError } from "@/api/client";
import type { OnlinePayment, PublicPackage } from "@/api/my-payments";
import { canBuyHere } from "@/lib/platform/store-policy";
import type { NativePlatform } from "@/lib/platform";

/** Where the member started, so the return page leads back there. */
export type CheckoutOrigin = "box" | "schedule" | "public" | "payments";

/**
 * What the return page needs to know about a checkout it did not start:
 * `/pay/return` has no box in its URL, and the provider's page sits in
 * between. Kept on the device for a day.
 */
export type PendingCheckout = {
  paymentId: string;
  slug: string;
  kind: "package" | "visit" | "invoice";
  itemName: string;
  origin: CheckoutOrigin;
  /** The member chose to pay what falls due with the saved card. */
  autopay: boolean;
  /** The class booked once paid («CrossFit · σήμερα 18:00»). */
  classLabel?: string | null;
  savedAt: number;
};

const STORAGE_KEY = "palee.pendingCheckouts";
const KEEP_MS = 24 * 60 * 60 * 1000;

function readAll(): PendingCheckout[] {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    const list = raw ? (JSON.parse(raw) as unknown) : [];
    return Array.isArray(list) ? (list as PendingCheckout[]) : [];
  } catch {
    return [];
  }
}

export function rememberCheckout(entry: Omit<PendingCheckout, "savedAt">, now = Date.now()) {
  try {
    const kept = readAll().filter((item) => item.paymentId !== entry.paymentId && now - item.savedAt < KEEP_MS);
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify([...kept.slice(-4), { ...entry, savedAt: now }]));
  } catch {
    // Private mode: the return page falls back to the selected box.
  }
}

export function pendingCheckout(paymentId: string | null | undefined, now = Date.now()): PendingCheckout | null {
  if (!paymentId) return null;
  return readAll().find((item) => item.paymentId === paymentId && now - item.savedAt < KEEP_MS) ?? null;
}

/**
 * Where the provider's checkout opens. The sandbox provider (dev and test)
 * sends the payer straight to our own /pay/return, which is an in-app page;
 * real providers are an https page outside the app.
 */
export function checkoutTarget(redirectUrl: string, origin: string): { kind: "internal"; path: string } | { kind: "external"; url: string } {
  try {
    const url = new URL(redirectUrl, origin);
    if (url.origin === origin) return { kind: "internal", path: `${url.pathname}${url.search}` };
  } catch {
    // Fall through: openCheckout refuses anything that is not https.
  }
  return { kind: "external", url: redirectUrl };
}

export type PaymentOutcome = "succeeded" | "pending" | "failed" | "cancelled";

/** What the return page shows for a payment the API just checked with the provider. */
export function paymentOutcome(payment: Pick<OnlinePayment, "status">, cancelledInUrl = false): PaymentOutcome {
  switch (payment.status) {
    case "succeeded":
      return "succeeded";
    case "failed":
    case "expired":
      return "failed";
    case "cancelled":
      return "cancelled";
    default:
      return cancelledInUrl ? "cancelled" : "pending";
  }
}

type WithdrawalRecord = { applies?: boolean; deadline?: string };

/** The 14-day withdrawal of a package bought online is still open. */
export function withdrawalOpen(payment: OnlinePayment, now: Date): boolean {
  const record = (payment.metadata?.withdrawal ?? null) as WithdrawalRecord | null;
  if (payment.purpose_type !== "membership_package" || payment.status !== "succeeded") return false;
  if (payment.fulfilment_status !== "done" || payment.refunded_cents >= payment.amount_cents) return false;
  if (!record?.applies || !record.deadline) return false;
  const deadline = Date.parse(record.deadline);
  return Number.isFinite(deadline) && deadline >= now.getTime();
}

export function withdrawalDeadline(payment: OnlinePayment): string | null {
  const record = (payment.metadata?.withdrawal ?? null) as WithdrawalRecord | null;
  return record?.deadline ?? null;
}

/** A declined saved-card charge of an invoice: the member can pay it with another card. */
export function canPayWithAnotherCard(payment: OnlinePayment): boolean {
  return payment.purpose_type === "finance_invoice" && payment.initiation === "merchant" && payment.status !== "succeeded";
}

/** The provider's name as people know it. */
export function providerLabel(provider: string | null | undefined): string | null {
  switch (provider) {
    case "viva":
      return "Viva";
    case "stripe":
      return "Stripe";
    case "sandbox":
      return "Sandbox";
    default:
      return null;
  }
}

/** Packages billed again every period ask whether the card pays the next ones. */
export function isRecurring(billingPeriod: string | null | undefined): boolean {
  return Boolean(billingPeriod) && billingPeriod !== "one_off" && billingPeriod !== "with_base";
}

/** ADR-256: what this screen may sell (digital-only packages never in the store apps). */
export function buyableHere(packages: PublicPackage[], platform: NativePlatform | null): PublicPackage[] {
  return packages.filter((pkg) =>
    canBuyHere({ kind: "subscription_package", fields: (pkg.services ?? {}) as Record<string, unknown> }, platform),
  );
}

const VISIT_TYPES = new Set(["drop_in", "trial"]);

/** «Ανανέωση»: the packages a member renews to (not a single visit or a trial). */
export function renewalPackages(packages: PublicPackage[]): PublicPackage[] {
  return packages.filter((pkg) => !VISIT_TYPES.has(pkg.package_type));
}

/** Booking without a package: one visit, and the first package that would cover it. */
export function bookingOffer(packages: PublicPackage[]): { visit: PublicPackage | null; pack: PublicPackage | null } {
  return {
    visit: packages.find((pkg) => pkg.package_type === "drop_in") ?? null,
    pack: packages.find((pkg) => !VISIT_TYPES.has(pkg.package_type) && pkg.package_type !== "pt_pack") ?? null,
  };
}

/** The sales page (mockup s5 option C): the trial first, three packages, then «Όλα». */
export function salesPageSections(packages: PublicPackage[]) {
  const trial = packages.find((pkg) => pkg.package_type === "trial") ?? null;
  const rest = packages.filter((pkg) => pkg.package_type !== "trial");
  return { trial, top: rest.slice(0, 3), more: rest.slice(3) };
}

/**
 * Booking refusals that mean «you have no package that covers this class»:
 * the member is offered to pay for the visit instead of an error.
 */
const NO_PACKAGE_CODES = new Set([
  "finance_profile_missing",
  "finance_entitlement_inactive",
  "finance_entitlement_plan_missing",
  "finance_channel_not_included",
  "finance_allowance_not_included",
  "finance_allowance_exhausted",
]);

export function needsPackage(error: unknown): boolean {
  return error instanceof ApiError && NO_PACKAGE_CODES.has(error.payload.code ?? "");
}

const PAY_ERRORS: Record<string, string> = {
  online_payments_unavailable: "errorUnavailable",
  package_not_for_sale: "errorNotForSale",
  start_now_consent_required: "errorStartNow",
  consent_required: "errorConsent",
  invoice_not_payable: "errorNothingToPay",
  withdrawal_period_over: "errorWithdrawalOver",
  withdrawal_not_available: "errorWithdrawalNotAvailable",
  already_withdrawn: "errorAlreadyWithdrawn",
  payment_method_inactive: "errorCardInactive",
};

/** The `Pay` message key for a payment refusal, or null for the app's general wording. */
export function payErrorKey(error: unknown): string | null {
  if (error instanceof Error && error.message === "unsafe_checkout_url") return "errorProviderPage";
  if (!(error instanceof ApiError)) return null;
  return PAY_ERRORS[error.payload.code ?? ""] ?? null;
}
