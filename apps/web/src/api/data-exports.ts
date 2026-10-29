import { ApiError, apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

type ExportList =
  paths["/api/me/data-exports"]["get"]["responses"]["200"]["content"]["application/json"];

/** ADR-267: one "Download my data" request and, once ready, its file. */
export type DataExport = ExportList["exports"][number];

/** The person's requests, newest first; a ready file carries a fresh short-lived link. */
export async function fetchDataExports(token: string): Promise<DataExport[]> {
  const response = await apiRequest<ExportList>("/me/data-exports", { token, scope: "account" });
  return response.exports;
}

/** Asks for a new copy of the person's data; the file is built in the background. */
export async function requestDataExport(token: string): Promise<DataExport> {
  const response = await apiRequest<{ export: DataExport }>("/me/data-exports", {
    method: "POST",
    token,
    scope: "account",
  });
  return response.export;
}

/** Why a request was refused: one is being prepared, or the daily limit (with when to ask again). */
export type DataExportRefusal = { kind: "in_progress" } | { kind: "rate_limited"; retryAt: string | null };

export function dataExportRefusal(error: unknown): DataExportRefusal | null {
  if (!(error instanceof ApiError)) return null;
  if (error.payload.code === "export_in_progress") return { kind: "in_progress" };
  if (error.status === 429) {
    const retryAt = (error.payload as Record<string, unknown>).retry_at;
    return { kind: "rate_limited", retryAt: typeof retryAt === "string" ? retryAt : null };
  }
  return null;
}

/** The newest request is what Settings shows. */
export function latestDataExport(exports: DataExport[] | undefined): DataExport | null {
  if (!exports || exports.length === 0) return null;
  return [...exports].sort((a, b) => b.requested_at.localeCompare(a.requested_at))[0] ?? null;
}
