import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

// ADR-254: importing clients from another system's CSV file.
type Json<Op extends keyof operations, Status extends number> = operations[Op]["responses"] extends Record<
  Status,
  { content: { "application/json": infer Body } }
>
  ? Body
  : never;

export type ImportCatalog = Json<"PaleeWeb.AdminImportController.catalog", 200>;
export type PeopleImport = Json<"PaleeWeb.AdminImportController.show", 200>["import"];
export type ImportRowsPage = Json<"PaleeWeb.AdminImportController.rows", 200>;
export type ImportRow = ImportRowsPage["rows"][number];
export type ImportInvitations = Json<"PaleeWeb.AdminImportController.invitations", 200>;
export type ImportMappingEntry = PeopleImport["mapping"][number];
export type ImportField = NonNullable<ImportMappingEntry["field"]>;
export type ImportSource = PeopleImport["source"];
export type ImportDateOrder = PeopleImport["date_order"];
export type ImportRowStatus = ImportRow["status"];
export type ImportOutcome = NonNullable<ImportRow["outcome"]>;

export type ImportPreviewBody = {
  mapping?: ImportMappingEntry[];
  date_order?: ImportDateOrder;
};

export type ImportRowFilters = {
  status?: ImportRowStatus;
  outcome?: ImportOutcome;
  after_row?: number;
  limit?: number;
};

const BASE = "/admin/imports";

export function fetchImportCatalog(token: string) {
  return apiRequest<ImportCatalog>(`${BASE}/catalog`, { token });
}

export async function listImports(token: string) {
  const body = await apiRequest<{ imports: PeopleImport[] }>(BASE, { token });
  return body.imports;
}

export async function uploadImport(token: string, file: File, source?: ImportSource | null) {
  const form = new FormData();
  form.append("file", file, file.name);
  if (source) form.append("source", source);
  const body = await apiRequest<{ import: PeopleImport }>(BASE, { token, method: "POST", body: form });
  return body.import;
}

export async function fetchImport(token: string, id: string) {
  const body = await apiRequest<{ import: PeopleImport }>(`${BASE}/${id}`, { token });
  return body.import;
}

export function fetchImportRows(token: string, id: string, filters: ImportRowFilters = {}) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(filters)) {
    if (value !== undefined && value !== null) search.set(key, String(value));
  }
  const query = search.toString();
  return apiRequest<ImportRowsPage>(`${BASE}/${id}/rows${query ? `?${query}` : ""}`, { token });
}

export async function previewImport(token: string, id: string, body: ImportPreviewBody = {}) {
  const response = await apiRequest<{ import: PeopleImport }>(`${BASE}/${id}/preview`, {
    token,
    method: "POST",
    body,
  });
  return response.import;
}

export async function applyImport(token: string, id: string) {
  const body = await apiRequest<{ import: PeopleImport }>(`${BASE}/${id}/apply`, { token, method: "POST" });
  return body.import;
}

export function sendImportInvitations(token: string, id: string) {
  return apiRequest<ImportInvitations>(`${BASE}/${id}/invitations`, { token, method: "POST", body: {} });
}

export async function undoImport(token: string, id: string) {
  const body = await apiRequest<{ import: PeopleImport }>(`${BASE}/${id}/undo`, { token, method: "POST" });
  return body.import;
}

export function deleteImport(token: string, id: string) {
  return apiRequest<void>(`${BASE}/${id}`, { token, method: "DELETE" });
}
