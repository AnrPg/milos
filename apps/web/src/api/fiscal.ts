import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

// ADR-240–245: the business's billing details, its fiscal documents, credit
// notes, the audit archive, document files and accounting exports.

type Json<Op extends keyof operations, Code extends number = 200> = operations[Op]["responses"] extends Record<
  Code,
  { content: { "application/json": infer Body } }
>
  ? Body
  : never;

export type IdentityStatus = Json<"PaleeWeb.AdminFiscalController.identity">;
export type BusinessIdentity = NonNullable<IdentityStatus["identity"]>;
export type CountryProfile = NonNullable<IdentityStatus["profile"]>;
export type IdentityChanges = NonNullable<
  operations["PaleeWeb.AdminFiscalController.save_identity"]["requestBody"]
>["content"]["application/json"];
export type CountriesResponse = Json<"PaleeWeb.AdminFiscalController.countries">;

// ADR-273: the «Συνδέσεις» card, «Δοκιμή σύνδεσης» and the vendor console.
export type ConnectionsOverview = Json<"PaleeWeb.AdminFiscalConnectionsController.index">;
export type ConnectionKind = ConnectionsOverview["kinds"][number];
export type ConnectionResult = Json<"PaleeWeb.AdminFiscalConnectionsController.check">;
export type ConnectionCheck = NonNullable<ConnectionResult["check"]>;
export type AuthorityConnection = NonNullable<ConnectionsOverview["connections"]["mydata"]>;
export type RegistryConnection = NonNullable<ConnectionsOverview["connections"]["registry"]>;
export type TillConnection = NonNullable<ConnectionsOverview["connections"]["tse"]>;
export type PeppolConnection = NonNullable<ConnectionsOverview["connections"]["peppol"]>;
export type FiscalConnection = AuthorityConnection | RegistryConnection | TillConnection | PeppolConnection;
export type ConnectionsManager = ConnectionsOverview["managed_by"];

/** Where each connection is saved by the box's own staff. */
const SAVE_PATHS: Record<ConnectionKind, string> = {
  mydata: "/admin/fiscal/authority-connection",
  registry: "/admin/fiscal/registry-connection",
  tse: "/admin/fiscal/till-connections/tse",
  rksv: "/admin/fiscal/till-connections/rksv",
  sign_fr: "/admin/fiscal/till-connections/sign_fr",
  peppol: "/admin/fiscal/peppol-connection",
};

export function fetchFiscalConnections(token: string) {
  return apiRequest<ConnectionsOverview>("/admin/fiscal/connections", { token });
}

/** Saves one connection; it is then checked right away (`check`). Secrets are sent only when typed. */
export function saveFiscalConnection(token: string, kind: ConnectionKind, body: Record<string, unknown>) {
  return apiRequest<ConnectionResult>(SAVE_PATHS[kind], { token, method: "PUT", body });
}

/** «Δοκιμή σύνδεσης». */
export function checkFiscalConnection(token: string, kind: ConnectionKind) {
  return apiRequest<ConnectionResult>(`/admin/fiscal/connections/${kind}/check`, { token, method: "POST" });
}

export function fetchPlatformFiscalConnections(token: string, organizationId: string) {
  return apiRequest<ConnectionsOverview>(`/platform/organizations/${organizationId}/fiscal-connections`, { token });
}

export function setPlatformConnectionsManager(token: string, organizationId: string, managedBy: ConnectionsManager) {
  return apiRequest<ConnectionsOverview>(`/platform/organizations/${organizationId}/fiscal-connections/managed-by`, {
    token,
    method: "PUT",
    body: { managed_by: managedBy },
  });
}

export function savePlatformFiscalConnection(token: string, organizationId: string, kind: ConnectionKind, body: Record<string, unknown>) {
  return apiRequest<ConnectionResult>(`/platform/organizations/${organizationId}/fiscal-connections/${kind}`, {
    token,
    method: "PUT",
    body,
  });
}

export function checkPlatformFiscalConnection(token: string, organizationId: string, kind: ConnectionKind) {
  return apiRequest<ConnectionResult>(`/platform/organizations/${organizationId}/fiscal-connections/${kind}/check`, {
    token,
    method: "POST",
  });
}

export type DocumentPage = Json<"PaleeWeb.AdminFiscalController.documents">;
export type FiscalDocument = DocumentPage["documents"][number];
export type FiscalDocumentDetail = Json<"PaleeWeb.AdminFiscalController.document">["document"];
export type FiscalDocumentLine = NonNullable<FiscalDocument["lines"]>[number];
export type Transmission = NonNullable<FiscalDocument["transmission"]>;
export type DocumentKind = FiscalDocument["kind"];
export type Closing = Json<"PaleeWeb.AdminFiscalController.closings">["closings"][number];
export type JournalVerification = Json<"PaleeWeb.AdminFiscalController.verify_journal">["verification"];
export type ExportFormats = Json<"PaleeWeb.AdminFiscalTaxController.export_formats">;
export type ExportFormat = ExportFormats["formats"][number];
export type ExportSetting = ExportFormats["settings"][number];
export type CreditLine = { position: number; quantity: number };
type CreditNoteRequest = NonNullable<
  operations["PaleeWeb.AdminFiscalController.credit"]["requestBody"]
>["content"]["application/json"];

/** The languages a document can be rendered in (ADR-245). */
export const DOCUMENT_LANGUAGES = ["el", "en", "de", "fr", "it", "nl", "es"] as const;
export type DocumentLanguage = (typeof DOCUMENT_LANGUAGES)[number];

function query(params: Record<string, string | number | undefined | null>) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== "") search.set(key, String(value));
  }
  const text = search.toString();
  return text ? `?${text}` : "";
}

export function fetchFiscalCountries(token: string) {
  return apiRequest<CountriesResponse>("/admin/fiscal/countries", { token });
}

export function fetchFiscalIdentity(token: string) {
  return apiRequest<IdentityStatus>("/admin/fiscal/identity", { token });
}

export function saveFiscalIdentity(token: string, changes: IdentityChanges) {
  return apiRequest<IdentityStatus>("/admin/fiscal/identity", { token, method: "PUT", body: changes });
}

export type DocumentFilters = {
  kind?: DocumentKind;
  from?: string;
  to?: string;
  number?: string;
  limit?: number;
  offset?: number;
};

export function listFiscalDocuments(token: string, filters: DocumentFilters = {}) {
  return apiRequest<DocumentPage>(`/admin/fiscal/documents${query(filters)}`, { token });
}

export function fetchFiscalDocument(token: string, id: string) {
  return apiRequest<{ document: FiscalDocumentDetail }>(`/admin/fiscal/documents/${id}`, { token });
}

export type CreditReason = NonNullable<CreditNoteRequest["reason"]>;
export const CREDIT_REASONS: readonly CreditReason[] = ["product_return", "billing_error", "subscription_cancelled", "other"];
export type CreditResult = Json<"PaleeWeb.AdminFiscalController.credit", 201>;
export type RefundOption = NonNullable<FiscalDocumentDetail["refund_option"]>;

/**
 * Issues a credit note with its reason: every line when `lines` is left out
 * (ADR-241, ADR-265). With `refund` the money goes back to the card the
 * document was paid with and that refund issues the note.
 */
export function issueCreditNote(
  token: string,
  id: string,
  request: { idempotencyKey: string; reason: CreditReason; lines?: CreditLine[]; refund?: boolean },
) {
  return apiRequest<CreditResult>(`/admin/fiscal/documents/${id}/credit-notes`, {
    token,
    method: "POST",
    body: {
      idempotency_key: request.idempotencyKey,
      reason: request.reason,
      ...(request.lines ? { lines: request.lines } : {}),
      ...(request.refund ? { refund: true } : {}),
    },
  });
}

export type DocumentEmail = Json<"PaleeWeb.AdminFiscalTaxController.email_document", 202>["email"];

/** «Αποστολή με email» (ADR-265): the PDF to `to`, or to the buyer printed on it. */
export function emailFiscalDocument(token: string, id: string, idempotencyKey: string, to?: string) {
  return apiRequest<{ email: DocumentEmail }>(`/admin/fiscal/documents/${id}/email`, {
    token,
    method: "POST",
    body: { idempotency_key: idempotencyKey, ...(to ? { to } : {}) },
  });
}

export type RegistryBusiness = Json<"PaleeWeb.AdminFiscalRegistryController.lookup">["business"];

/** «Συμπλήρωση από το ΑΦΜ» (ADR-265): a Greek business from AADE's registry. */
export function lookupRegistryBusiness(token: string, taxId: string) {
  return apiRequest<{ business: RegistryBusiness }>(`/admin/fiscal/registry/businesses/${encodeURIComponent(taxId)}`, {
    token,
  });
}

export function retryTransmission(token: string, id: string) {
  return apiRequest<{ transmission: Transmission }>(`/admin/fiscal/documents/${id}/transmission/retry`, {
    token,
    method: "POST",
  });
}

export function fetchDocumentPdf(token: string, id: string, language?: DocumentLanguage) {
  return apiRequest<Blob>(`/admin/fiscal/documents/${id}/pdf${query({ language })}`, { token, responseType: "blob" });
}

export function fetchDocumentHtml(token: string, id: string, language?: DocumentLanguage) {
  return apiRequest<string>(`/admin/fiscal/documents/${id}/html${query({ language })}`, {
    token,
    responseType: "text",
  });
}

export function listClosings(token: string, filters: { kind?: Closing["period_kind"]; from?: string; to?: string; limit?: number } = {}) {
  return apiRequest<{ closings: Closing[] }>(`/admin/fiscal/closings${query(filters)}`, { token });
}

export function verifyJournal(token: string) {
  return apiRequest<{ verification: JournalVerification }>("/admin/fiscal/journal/verification", { token });
}

export function fetchAuditArchive(token: string, from: string, to: string) {
  return apiRequest<Blob>(`/admin/fiscal/archive${query({ from, to })}`, { token, responseType: "blob" });
}

export function fetchExportFormats(token: string) {
  return apiRequest<ExportFormats>("/admin/fiscal/exports/formats", { token });
}

export function saveExportSettings(token: string, format: string, options: Record<string, unknown>) {
  return apiRequest<{ setting: ExportSetting }>(`/admin/fiscal/exports/settings/${encodeURIComponent(format)}`, {
    token,
    method: "PUT",
    body: { options },
  });
}

export function fetchAccountingExport(token: string, format: string, from: string, to: string) {
  return apiRequest<Blob>(`/admin/fiscal/exports/${encodeURIComponent(format)}${query({ from, to })}`, {
    token,
    responseType: "blob",
  });
}

/** Hands the viewer a file to save. */
export function saveBlob(blob: Blob, fileName: string) {
  const url = URL.createObjectURL(blob);
  const anchor = window.document.createElement("a");
  anchor.href = url;
  anchor.download = fileName;
  anchor.click();
  URL.revokeObjectURL(url);
}
