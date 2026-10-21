import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

// ADR-098 payment models: corporate clients (seats, invoices) and shared
// memberships (beneficiaries).

type Json<T> = T extends { content: { "application/json": infer Body } } ? Body : never;
type Op = operations;

type ClientsResponse = Json<Op["PaleeWeb.PaymentModelsController.clients"]["responses"][200]>;
type ClientResponse = Json<Op["PaleeWeb.PaymentModelsController.update_client"]["responses"][200]>;
type SeatsResponse = Json<Op["PaleeWeb.PaymentModelsController.seats"]["responses"][200]>;
type SeatResponse = Json<Op["PaleeWeb.PaymentModelsController.end_seat"]["responses"][200]>;
type InvoicesResponse = Json<Op["PaleeWeb.PaymentModelsController.invoices"]["responses"][200]>;
type InvoiceResponse = Json<Op["PaleeWeb.PaymentModelsController.invoice_status"]["responses"][200]>;
type InvoiceDocumentResponse = Json<Op["PaleeWeb.PaymentModelsController.invoice"]["responses"][200]>;
type BeneficiariesResponse = Json<Op["PaleeWeb.PaymentModelsController.beneficiaries"]["responses"][200]>;
type BeneficiaryResponse = Json<Op["PaleeWeb.PaymentModelsController.remove_beneficiary"]["responses"][200]>;

export type CorporateClient = ClientsResponse["clients"][number];
export type CorporateClientCreate = NonNullable<
  Op["PaleeWeb.PaymentModelsController.create_client"]["requestBody"]
>["content"]["application/json"];
export type CorporateClientUpdate = NonNullable<
  Op["PaleeWeb.PaymentModelsController.update_client"]["requestBody"]
>["content"]["application/json"];
export type CorporateSeat = SeatsResponse["seats"][number];
export type CorporateInvoice = InvoicesResponse["invoices"][number];
export type CorporatePayment = CorporateInvoice["payments"][number];
export type CorporatePaymentMethod = CorporatePayment["payment_method"];
export type CorporatePaymentInput = NonNullable<
  Op["PaleeWeb.PaymentModelsController.record_payment"]["requestBody"]
>["content"]["application/json"];
export type CorporateInvoiceDocument = InvoiceDocumentResponse["invoice"];
export type SubscriptionBeneficiary = BeneficiariesResponse["beneficiaries"][number];

const CLIENTS = "/admin/finance/corporate-clients";

export async function fetchCorporateClients(token: string) {
  const response = await apiRequest<ClientsResponse>(CLIENTS, { token });
  return response.clients;
}

export async function createCorporateClient(token: string, body: CorporateClientCreate) {
  const response = await apiRequest<ClientResponse>(CLIENTS, { method: "POST", token, body });
  return response.client;
}

export async function updateCorporateClient(token: string, id: string, body: CorporateClientUpdate) {
  const response = await apiRequest<ClientResponse>(`${CLIENTS}/${id}`, { method: "PATCH", token, body });
  return response.client;
}

export async function fetchCorporateSeats(token: string, clientId: string) {
  const response = await apiRequest<SeatsResponse>(`${CLIENTS}/${clientId}/seats`, { token });
  return response.seats;
}

export async function addCorporateSeat(token: string, clientId: string, userId: string) {
  const response = await apiRequest<SeatResponse>(`${CLIENTS}/${clientId}/seats`, {
    method: "POST",
    token,
    body: { user_id: userId },
  });
  return response.seat;
}

export async function endCorporateSeat(token: string, clientId: string, subscriptionId: string) {
  const response = await apiRequest<SeatResponse>(`${CLIENTS}/${clientId}/seats/${subscriptionId}/end`, {
    method: "POST",
    token,
  });
  return response.seat;
}

export async function fetchCorporateInvoices(token: string, clientId: string) {
  const response = await apiRequest<InvoicesResponse>(`${CLIENTS}/${clientId}/invoices`, { token });
  return response.invoices;
}

/** Generates the invoice for the billing period that contains `on` (default today). */
export async function generateCorporateInvoice(token: string, clientId: string, on?: string) {
  const response = await apiRequest<InvoiceResponse>(`${CLIENTS}/${clientId}/invoices`, {
    method: "POST",
    token,
    body: on ? { on } : {},
  });
  return response.invoice;
}

const INVOICES = "/admin/finance/corporate-invoices";

/** Voids an invoice; the API refuses while payments stand. */
export async function voidCorporateInvoice(token: string, invoiceId: string) {
  const response = await apiRequest<InvoiceResponse>(`${INVOICES}/${invoiceId}/status`, {
    method: "POST",
    token,
    body: { status: "void" },
  });
  return response.invoice;
}

/** The invoice with its client and issuer, for the PDF. */
export async function fetchCorporateInvoiceDocument(token: string, invoiceId: string) {
  const response = await apiRequest<InvoiceDocumentResponse>(`${INVOICES}/${invoiceId}`, { token });
  return response.invoice;
}

export async function recordCorporatePayment(token: string, invoiceId: string, body: CorporatePaymentInput) {
  const response = await apiRequest<InvoiceResponse>(`${INVOICES}/${invoiceId}/payments`, {
    method: "POST",
    token,
    body,
  });
  return response.invoice;
}

export async function reverseCorporatePayment(token: string, invoiceId: string, paymentId: string, reason?: string) {
  const response = await apiRequest<InvoiceResponse>(`${INVOICES}/${invoiceId}/payments/${paymentId}/reverse`, {
    method: "POST",
    token,
    body: reason ? { reason } : {},
  });
  return response.invoice;
}

/** Emails the invoice (or an overdue reminder) to the client's billing contact. */
export async function sendCorporateInvoice(token: string, invoiceId: string) {
  const response = await apiRequest<InvoiceResponse>(`${INVOICES}/${invoiceId}/send`, { method: "POST", token });
  return response.invoice;
}

export async function fetchSubscriptionBeneficiaries(token: string, subscriptionId: string) {
  const response = await apiRequest<BeneficiariesResponse>(
    `/admin/finance/subscriptions/${subscriptionId}/beneficiaries`,
    { token },
  );
  return response.beneficiaries;
}

export async function addSubscriptionBeneficiary(
  token: string,
  subscriptionId: string,
  body: { user_id: string; is_minor?: boolean },
) {
  const response = await apiRequest<BeneficiaryResponse>(
    `/admin/finance/subscriptions/${subscriptionId}/beneficiaries`,
    { method: "POST", token, body },
  );
  return response.beneficiary;
}

export async function removeSubscriptionBeneficiary(token: string, subscriptionId: string, beneficiaryId: string) {
  const response = await apiRequest<BeneficiaryResponse>(
    `/admin/finance/subscriptions/${subscriptionId}/beneficiaries/${beneficiaryId}/remove`,
    { method: "POST", token },
  );
  return response.beneficiary;
}
