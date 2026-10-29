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
export type AuthorityConnectionResponse = Json<"PaleeWeb.AdminFiscalReportingController.connection">;

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

export function fetchAuthorityConnection(token: string) {
  return apiRequest<AuthorityConnectionResponse>("/admin/fiscal/authority-connection", { token });
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

/** Issues a credit note: every line when `lines` is left out (ADR-241). */
export function issueCreditNote(token: string, id: string, idempotencyKey: string, lines?: CreditLine[]) {
  return apiRequest<{ document: FiscalDocument }>(`/admin/fiscal/documents/${id}/credit-notes`, {
    token,
    method: "POST",
    body: { idempotency_key: idempotencyKey, ...(lines ? { lines } : {}) },
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
