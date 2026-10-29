// Member › paying online (ADR-246/247/248/260): buying a subscription
// package, paying an open invoice, saved cards and autopay, withdrawal within
// 14 days, and the box's public sales page. Every call names its box, since a
// person can be a member of several and the return page has no box in its URL.
import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

type Json<Op extends keyof operations> = operations[Op] extends {
  responses: { 200: { content: { "application/json": infer T } } };
}
  ? T
  : never;

type Body<Op extends keyof operations> = operations[Op] extends {
  requestBody: { content: { "application/json": infer T } };
}
  ? T
  : never;

export type PublicPackages = Json<"PaleeWeb.PublicBoxController.packages">;
export type PublicPackage = PublicPackages["packages"][number];
export type PackageTerms = Json<"PaleeWeb.MyPaymentsController.package_terms">;
export type InvoiceTerms = Json<"PaleeWeb.MyPaymentsController.terms">;
export type OnlinePayment = Json<"PaleeWeb.MyPaymentsController.show">["payment"];
export type SavedCard = Json<"PaleeWeb.MyPaymentsController.methods">["payment_methods"][number];
export type Withdrawal = Json<"PaleeWeb.MyPaymentsController.withdraw">;
export type BuyPackageBody = Body<"PaleeWeb.MyPaymentsController.buy_package">;
export type PayInvoiceBody = Body<"PaleeWeb.MyPaymentsController.pay">;
export type PaymentReturnBody = Body<"PaleeWeb.MyPaymentsController.returned">;
export type SandboxOutcome = Body<"PaleeWeb.MyPaymentsController.sandbox_complete">["outcome"];

/** The languages the API writes its consent texts in. */
export type TermsLanguage = "el" | "en";

export function termsLanguage(locale: string): TermsLanguage {
  return locale.toLowerCase().startsWith("el") ? "el" : "en";
}

const org = (slug: string, path: string) => `/org/${encodeURIComponent(slug)}${path}`;
const id = (value: string) => encodeURIComponent(value);

export const publicPackagesKey = (slug: string) => ["public", "box", slug, "packages"] as const;

/** The packages a published box sells online, with whether it takes online payments now. */
export function fetchPublicPackages(slug: string) {
  return apiRequest<PublicPackages>(`/public/boxes/${id(slug)}/packages`, { scope: "account" });
}

export const packageTermsKey = (slug: string, packageId: string, language: TermsLanguage, slotId: string | null) =>
  ["me", "payments", slug, "package-terms", packageId, language, slotId ?? "none"] as const;

/** What buying one package costs and the texts the member agrees to, in their language. */
export function fetchPackageTerms(
  token: string,
  slug: string,
  packageId: string,
  language: TermsLanguage,
  bookSlotId?: string | null,
) {
  const query = new URLSearchParams({ language });
  if (bookSlotId) query.set("book_slot_id", bookSlotId);
  return apiRequest<PackageTerms>(org(slug, `/me/packages/${id(packageId)}/purchase-terms?${query}`), { token });
}

/** Opens the provider's checkout for a package (and books `book_slot_id` once paid). */
export function buyPackage(token: string, slug: string, packageId: string, body: BuyPackageBody) {
  return apiRequest<{ payment: OnlinePayment }>(org(slug, `/me/packages/${id(packageId)}/buy`), {
    token,
    method: "POST",
    body,
  });
}

export const invoiceTermsKey = (slug: string, invoiceId: string, language: TermsLanguage) =>
  ["me", "payments", slug, "invoice-terms", invoiceId, language] as const;

/** What paying an open invoice online costs, and the text to agree to when saving the card. */
export function fetchInvoiceTerms(token: string, slug: string, invoiceId: string, language: TermsLanguage) {
  return apiRequest<InvoiceTerms>(org(slug, `/me/invoices/${id(invoiceId)}/payment-terms?language=${language}`), { token });
}

/** Opens the provider's checkout for an open invoice. */
export function payInvoice(token: string, slug: string, invoiceId: string, body: PayInvoiceBody) {
  return apiRequest<{ payment: OnlinePayment }>(org(slug, `/me/invoices/${id(invoiceId)}/pay`), {
    token,
    method: "POST",
    body,
  });
}

/** Back from the provider's page: the API asks the provider about the payment now. */
export function returnFromCheckout(token: string, slug: string, body: PaymentReturnBody) {
  return apiRequest<{ payment: OnlinePayment }>(org(slug, "/me/payments/return"), { token, method: "POST", body });
}

export const paymentKey = (slug: string, paymentId: string) => ["me", "payments", slug, "payment", paymentId] as const;

export function fetchPayment(token: string, slug: string, paymentId: string) {
  return apiRequest<{ payment: OnlinePayment }>(org(slug, `/me/payments/${id(paymentId)}`), { token });
}

/** Dev and test only: finishes a sandbox checkout as the provider's page would. */
export function completeSandboxCheckout(token: string, slug: string, providerRef: string, outcome: SandboxOutcome, declineCard: boolean) {
  return apiRequest<{ payment: OnlinePayment }>(org(slug, "/me/payments/sandbox/complete"), {
    token,
    method: "POST",
    body: { provider_ref: providerRef, outcome, decline_card: declineCard },
  });
}

/** Withdraws from a package bought online within 14 days: the unused part comes back. */
export function withdrawPurchase(token: string, slug: string, paymentId: string) {
  return apiRequest<Withdrawal>(org(slug, `/me/payments/${id(paymentId)}/withdraw`), { token, method: "POST" });
}

export const savedCardsKey = (slug: string) => ["me", "payments", slug, "cards"] as const;

export function fetchSavedCards(token: string, slug: string) {
  return apiRequest<{ payment_methods: SavedCard[] }>(org(slug, "/me/payment-methods"), { token });
}

/** The member's permission ends: the card is never charged again. */
export function removeSavedCard(token: string, slug: string, cardId: string) {
  return apiRequest<{ payment_method: SavedCard }>(org(slug, `/me/payment-methods/${id(cardId)}`), {
    token,
    method: "DELETE",
  });
}

/** Pays due invoices automatically with this card (one card at a time). */
export function setCardAutopay(token: string, slug: string, cardId: string, autopay: boolean) {
  return apiRequest<{ payment_method: SavedCard }>(org(slug, `/me/payment-methods/${id(cardId)}/autopay`), {
    token,
    method: "PUT",
    body: { autopay },
  });
}

/** A fresh key per attempt: a retried request after a timeout opens the same checkout. */
export function newIdempotencyKey() {
  return `pay-${crypto.randomUUID()}`;
}
