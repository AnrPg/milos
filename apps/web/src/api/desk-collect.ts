import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

/*
 * «Είσπραξη» on the staff phone (ADR-249, ADR-264, ADR-272): who pays, what
 * they can pay, the Tap to Pay payment and its result, the receipt (QR for a
 * walk-in, email), guests of the box and the tips summary. Calls go through
 * the selected gym (`/org/:slug/admin/payments/...`).
 */

type Json<Op extends keyof operations, Code extends number = 200> = operations[Op]["responses"] extends Record<
  Code,
  { content: { "application/json": infer Body } }
>
  ? Body
  : never;

type Body<Op extends keyof operations> =
  NonNullable<operations[Op]["requestBody"]> extends { content: { "application/json": infer Payload } } ? Payload : never;

export type TerminalAvailability = Json<"PaleeWeb.AdminTerminalPaymentsController.availability">;
export type TerminalPayment = Json<"PaleeWeb.AdminTerminalPaymentsController.show">["payment"];
export type TerminalReceipt = NonNullable<TerminalPayment["document"]>;
export type TerminalStart = Body<"PaleeWeb.AdminTerminalPaymentsController.create">;
export type DeskPerson = Json<"PaleeWeb.AdminDeskBuyersController.people">["people"][number];
export type DeskOptions = Json<"PaleeWeb.AdminDeskBuyersController.options">["options"];
export type GuestResult = Json<"PaleeWeb.AdminDeskBuyersController.make_guest", 201>;
export type TipsSummary = Json<"PaleeWeb.AdminTipsController.index">;
export type ReceiptEmail = Json<"PaleeWeb.AdminTerminalPaymentsController.receipt_email", 202>["email"];

/** Why Tap to Pay cannot run, from the API or (no_app) from the phone. */
export type UnavailableReason = NonNullable<TerminalAvailability["reason"]> | "no_app";

export function fetchTerminalAvailability(token: string) {
  return apiRequest<TerminalAvailability>("/admin/payments/terminal/availability", { token });
}

export function fetchDeskPeople(token: string, query: string) {
  const q = query.trim();
  return apiRequest<{ people: DeskPerson[] }>(
    `/admin/payments/desk/people${q ? `?q=${encodeURIComponent(q)}` : ""}`,
    { token },
  );
}

export function fetchDeskOptions(token: string, userId: string | null) {
  return apiRequest<{ options: DeskOptions }>(
    `/admin/payments/desk/options${userId ? `?user_id=${encodeURIComponent(userId)}` : ""}`,
    { token },
  );
}

export function makeGuest(token: string, body: { user_id: string } | { name: string; email: string }) {
  return apiRequest<GuestResult>("/admin/payments/desk/guests", { token, method: "POST", body });
}

export function startTerminalPayment(token: string, body: TerminalStart) {
  return apiRequest<{ payment: TerminalPayment }>("/admin/payments/terminal", { token, method: "POST", body });
}

export function postTerminalResult(
  token: string,
  body: { reference: string; status: string; transaction_id: string | null; message: string | null },
) {
  return apiRequest<{ payment: TerminalPayment }>("/admin/payments/terminal/result", {
    token,
    method: "POST",
    body,
  });
}

export function fetchTerminalPayment(token: string, id: string) {
  return apiRequest<{ payment: TerminalPayment }>(`/admin/payments/terminal/${id}`, { token });
}

export function cancelTerminalPayment(token: string, id: string) {
  return apiRequest<{ payment: TerminalPayment }>(`/admin/payments/terminal/${id}/cancel`, {
    token,
    method: "POST",
  });
}

export function emailTerminalReceipt(token: string, id: string, idempotencyKey: string, to?: string) {
  return apiRequest<{ email: ReceiptEmail }>(`/admin/payments/terminal/${id}/receipt-email`, {
    token,
    method: "POST",
    body: { idempotency_key: idempotencyKey, ...(to ? { to } : {}) },
  });
}

export function fetchTipsSummary(token: string, range: { from?: string; to?: string } = {}) {
  const params = new URLSearchParams();
  if (range.from) params.set("from", range.from);
  if (range.to) params.set("to", range.to);
  const query = params.toString();
  return apiRequest<TipsSummary>(`/admin/payments/tips${query ? `?${query}` : ""}`, { token });
}

/** ADR-272: the boxes the signed-in person is only a guest of (account scope). */
export function fetchGuestBoxes(token: string) {
  return apiRequest<{ boxes: { id: string; name: string; slug: string }[] }>("/memberships/guest-boxes", {
    token,
    scope: "account",
  });
}
