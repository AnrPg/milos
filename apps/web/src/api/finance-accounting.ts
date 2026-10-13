import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

// ADR-126: refund receipts, payment-provider reconciliation and accounting exports.
type Schemas = components["schemas"];

export type RefundReceipt = Schemas["FinanceRefundReceipt"];
export type RefundReceiptDetail = Schemas["FinanceRefundReceiptDetail"];
export type ReconciliationRecord = Schemas["FinanceReconciliationRecord"];
export type ReconciliationCandidates = Schemas["FinanceReconciliationCandidates"];
export type ReconciliationCandidate = ReconciliationCandidates["candidates"][number];
export type ReconciliationLineRequest = Schemas["FinanceReconciliationLineRequest"];
export type AccountingExport = Schemas["FinanceAccountingExport"];
export type AccountingExportDownload = Schemas["FinanceAccountingExportDownload"];

export type RefundReceiptFilters = { q?: string; from?: string; to?: string; user_id?: string };

function query(params: Record<string, string | undefined>) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value) search.set(key, value);
  }
  const text = search.toString();
  return text ? `?${text}` : "";
}

export function listRefundReceipts(token: string, filters: RefundReceiptFilters = {}) {
  return apiRequest<Schemas["FinanceRefundReceiptCollection"]>(
    `/admin/finance/refund-receipts${query(filters)}`,
    { token },
  );
}

export function fetchRefundReceiptDocument(token: string, id: string, locale?: string) {
  return apiRequest<string>(`/admin/finance/refund-receipts/${id}/document${query({ locale })}`, {
    token,
    responseType: "text",
  });
}

export function listMyRefundReceipts(token: string) {
  return apiRequest<Schemas["FinanceRefundReceiptCollection"]>("/me/refund-receipts", { token });
}

export function fetchMyRefundReceiptDocument(token: string, id: string, locale?: string) {
  return apiRequest<string>(`/me/refund-receipts/${id}/document${query({ locale })}`, {
    token,
    responseType: "text",
  });
}

export function listReconciliationRecords(token: string, status?: string) {
  return apiRequest<Schemas["FinanceReconciliationRecordCollection"]>(
    `/admin/finance/reconciliation-records${query({ status })}`,
    { token },
  );
}

export function recordReconciliationLine(token: string, body: ReconciliationLineRequest) {
  return apiRequest<Schemas["FinanceReconciliationRecordResponse"]>(
    "/admin/finance/reconciliation-records",
    { token, method: "POST", body },
  );
}

export function fetchReconciliationCandidates(token: string, id: string) {
  return apiRequest<ReconciliationCandidates>(
    `/admin/finance/reconciliation-records/${id}/candidates`,
    { token },
  );
}

export function matchReconciliationRecord(
  token: string,
  id: string,
  body: Schemas["FinanceReconciliationMatchRequest"],
) {
  return apiRequest<Schemas["FinanceReconciliationRecordResponse"]>(
    `/admin/finance/reconciliation-records/${id}/match`,
    { token, method: "POST", body },
  );
}

export function unmatchReconciliationRecord(token: string, id: string) {
  return apiRequest<Schemas["FinanceReconciliationRecordResponse"]>(
    `/admin/finance/reconciliation-records/${id}/unmatch`,
    { token, method: "POST", body: {} },
  );
}

export function listAccountingExports(token: string) {
  return apiRequest<Schemas["FinanceAccountingExportCollection"]>(
    "/admin/finance/accounting-exports",
    { token },
  );
}

export function requestAccountingExport(token: string, body: Schemas["FinanceAccountingExportRequest"]) {
  return apiRequest<Schemas["FinanceAccountingExportResponse"]>("/admin/finance/accounting-exports", {
    token,
    method: "POST",
    body,
  });
}

export function fetchAccountingExportDownload(token: string, id: string) {
  return apiRequest<AccountingExportDownload>(`/admin/finance/accounting-exports/${id}/download`, {
    token,
  });
}
