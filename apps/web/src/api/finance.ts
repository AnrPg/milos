import { apiRequest } from "@/api/client";
import type { PackageCatalog } from "@/components/admin/finance/packages/package-catalog";
import type { LocationScopePayload } from "@/lib/location-scope";

export type FinanceRecord = Record<string, unknown>;

export type FinanceCleanupRecord = {
  id: string;
  record_type: "invoice" | "receipt" | "payment" | "transaction";
  code: string;
  label: string;
  membership_id?: string | null;
  user_id?: string | null;
  finance_invoice_id?: string | null;
  amount_cents?: number | null;
  currency?: string | null;
  status?: string | null;
  issued_on?: string | null;
  due_on?: string | null;
  paid_on?: string | null;
  inserted_at?: string | null;
  deleted_at?: string | null;
};

/** ADR-186 §7: `locationIds` (comma-separated) narrows the summary to some branches. */
export async function fetchFinanceSummary(token: string, locationIds?: string) {
  const query = locationIds ? `?${new URLSearchParams({ location_ids: locationIds }).toString()}` : "";
  return apiRequest<FinanceRecord>(`/admin/finance/summary${query}`, { token });
}

export async function fetchFinanceCleanupRecords(
  token: string,
  params: { q?: string; limit?: string } = {},
) {
  const query = new URLSearchParams(params).toString();
  return apiRequest<{ records: FinanceCleanupRecord[] }>(
    `/admin/finance/cleanup-records${query ? `?${query}` : ""}`,
    { token },
  );
}

export async function purgeFinanceRecord(
  token: string,
  recordId: string,
  body: { record_type: string; password: string; reason?: string },
) {
  return apiRequest<{ record: FinanceCleanupRecord; purged_linked_records?: Record<string, number> }>(
    `/admin/finance/cleanup-records/${recordId}/purge`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

/** ADR-186 §7: the `location_ids` query of a list on a branch-filtered page, or "". */
function branchQuery(locationIds?: string) {
  return locationIds ? `?${new URLSearchParams({ location_ids: locationIds }).toString()}` : "";
}

/** `locationIds` (the page branch filter) keeps the packages valid at one of them or everywhere. */
export async function fetchFinancePackages(token: string, locationIds?: string) {
  return apiRequest<{ packages: FinanceRecord[]; branch_filter?: LocationScopePayload }>(
    `/admin/finance/packages${branchQuery(locationIds)}`,
    { token },
  );
}

export async function fetchPackageCatalog(token: string) {
  return apiRequest<PackageCatalog>("/admin/finance/package-catalog", { token });
}

export async function fetchFinancePackage(token: string, packageId: string) {
  return apiRequest<{ package: FinanceRecord }>(`/admin/finance/packages/${packageId}`, { token });
}

export async function createFinancePackage(token: string, body: FinanceRecord) {
  return apiRequest<{ package: FinanceRecord }>("/admin/finance/packages", {
    method: "POST",
    token,
    body,
  });
}

export async function updateFinancePackage(token: string, packageId: string, body: FinanceRecord) {
  return apiRequest<{ package: FinanceRecord }>(`/admin/finance/packages/${packageId}`, {
    method: "PATCH",
    token,
    body,
  });
}

export async function retireFinancePackage(
  token: string,
  packageId: string,
  replacementPackageByRole: Record<string, string>,
) {
  return apiRequest<{ package: FinanceRecord; reassigned_count: number; affected_by_role: Record<string, number> }>(
    `/admin/finance/packages/${packageId}/retire`,
    {
      method: "PATCH",
      token,
      body: { replacement_package_by_role: replacementPackageByRole },
    },
  );
}

export type EntitlementBackfillReport = {
  dry_run: boolean;
  ready: boolean;
  counts: Record<string, number>;
  failures: Array<{ user_id: string; reason: string }>;
};

export async function backfillFinanceEntitlements(token: string, body: { dry_run: boolean; package_by_role: { member?: string; athlete?: string } }) {
  return apiRequest<EntitlementBackfillReport>("/admin/finance/entitlements/backfill", {
    method: "POST",
    token,
    body,
  });
}

export async function fetchFinanceMembers(token: string, params: Record<string, string> = {}) {
  const qs = new URLSearchParams(params).toString();
  return apiRequest<{ members: FinanceRecord[]; meta: FinanceRecord; branch_filter?: LocationScopePayload }>(
    `/admin/finance/members${qs ? `?${qs}` : ""}`,
    { token },
  );
}

export async function fetchFinanceMember(token: string, userId: string) {
  return apiRequest<{
    membership: FinanceRecord | null;
    package_subscriptions: FinanceRecord[];
    invoices: FinanceRecord[];
    payments: FinanceRecord[];
    payment_reversals: FinanceRecord[];
    promotion_redemptions: FinanceRecord[];
    credit_ledger_entries: FinanceRecord[];
    credit_balance: number;
    entitlement?: FinanceRecord;
  }>(`/admin/finance/members/${userId}`, { token });
}

export async function updateFinanceMember(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ membership: FinanceRecord }>(`/admin/finance/members/${userId}`, {
    method: "PATCH",
    token,
    body,
  });
}

/** ADR-220: staff turn a member's subscription renewal on or off. */
export async function setFinanceMemberAutoRenew(token: string, userId: string, subscriptionId: string, autoRenew: boolean) {
  return apiRequest<{ package_subscription: FinanceRecord }>(
    `/admin/finance/members/${userId}/subscriptions/${encodeURIComponent(subscriptionId)}/auto-renew`,
    { method: "PUT", token, body: { auto_renew: autoRenew } },
  );
}

/** ADR-220: staff mark a member as leaving the box (no day: when what they paid for ends). */
export async function markFinanceMemberLeft(
  token: string,
  userId: string,
  body: { leaving_on?: string | null; reason?: string | null; commitment_override_reason?: string | null },
) {
  return apiRequest<{ membership: FinanceRecord; leaving_on: string; voided_invoice_count: number; outstanding_cents: number }>(
    `/admin/finance/members/${userId}/leave`,
    { method: "POST", token, body },
  );
}

/** ADR-220: staff undo a member's leave. */
export async function undoFinanceMemberLeft(token: string, userId: string) {
  return apiRequest<{ membership: FinanceRecord }>(`/admin/finance/members/${userId}/leave`, { method: "DELETE", token });
}

export async function assignFinancePackage(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ package_subscription: FinanceRecord }>(`/admin/finance/members/${userId}/packages`, {
    method: "POST",
    token,
    body,
  });
}

export async function recordFinancePayment(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ payment: FinanceRecord }>(`/admin/finance/members/${userId}/payments`, {
    method: "POST",
    token,
    body,
  });
}

export type FinanceReceipt = {
  document_type: "receipt";
  reference: string;
  issued_on: string;
  amount_cents: number;
  currency: string;
  description: string;
  membership_package_subscription_id?: string | null;
  package_name?: string | null;
  package_code_snapshot?: string | null;
  package_family_snapshot?: string | null;
  invoice: FinanceRecord;
  payment: FinanceRecord;
};

export async function createFinanceReceipt(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ receipt: FinanceReceipt }>(`/admin/finance/members/${userId}/receipts`, {
    method: "POST",
    token,
    body,
  });
}

/**
 * ADR-222: money received at the desk and the document it left: the open
 * invoice it went against, a paid receipt or a paid invoice, as the box's
 * billing setup says. `replayed` is true when the same idempotency key was
 * already recorded, and the first answer comes back unchanged.
 */
export type ReceivedPayment = Omit<FinanceReceipt, "document_type"> & {
  document_type: "receipt" | "invoice";
  replayed: boolean;
};

export async function receiveFinancePayment(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ received: ReceivedPayment }>(`/admin/finance/members/${userId}/payments/receive`, {
    method: "POST",
    token,
    body,
  });
}

export async function createFinanceInvoice(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ invoice: FinanceRecord }>(`/admin/finance/members/${userId}/invoices`, {
    method: "POST",
    token,
    body,
  });
}

export async function generateRenewalInvoice(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ invoice: FinanceRecord }>(`/admin/finance/members/${userId}/invoices/renewal`, {
    method: "POST",
    token,
    body,
  });
}

export async function getInvoiceUploadUrl(
  token: string,
  invoiceId: string,
  fileName: string,
  contentType: string,
) {
  return apiRequest<{ upload_url: string; file_key: string; content_type: string }>(
    `/admin/finance/invoices/${invoiceId}/upload-url`,
    { method: "POST", token, body: { file_name: fileName, content_type: contentType } },
  );
}

export async function getInvoiceDownloadUrl(token: string, invoiceId: string) {
  return apiRequest<{ download_url: string; file_name: string }>(
    `/admin/finance/invoices/${invoiceId}/download-url`,
    { token },
  );
}

export async function updateFinanceInvoice(
  token: string,
  invoiceId: string,
  body: { due_date?: string; notes?: string },
) {
  return apiRequest<{ invoice: FinanceRecord }>(`/admin/finance/invoices/${invoiceId}`, {
    method: "PATCH",
    token,
    body,
  });
}

export async function issueFinanceInvoice(token: string, invoiceId: string, body: FinanceRecord = {}) {
  return apiRequest<{ invoice: FinanceRecord }>(`/admin/finance/invoices/${invoiceId}/issue`, {
    method: "PATCH",
    token,
    body,
  });
}

export async function voidFinanceInvoice(token: string, invoiceId: string, body: FinanceRecord = {}) {
  return apiRequest<{ invoice: FinanceRecord }>(`/admin/finance/invoices/${invoiceId}/void`, {
    method: "PATCH",
    token,
    body,
  });
}

export async function createManualCredit(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ credit_ledger_entry: FinanceRecord }>(`/admin/finance/members/${userId}/credits`, {
    method: "POST",
    token,
    body,
  });
}

export async function applyCreditToPayment(token: string, userId: string, paymentId: string, body: FinanceRecord) {
  return apiRequest<{ credit_ledger_entry: FinanceRecord }>(
    `/admin/finance/members/${userId}/payments/${paymentId}/credits`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

export async function applyCreditToInvoice(token: string, userId: string, invoiceId: string, body: FinanceRecord) {
  return apiRequest<{ credit_ledger_entry: FinanceRecord }>(
    `/admin/finance/members/${userId}/invoices/${invoiceId}/credits`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

export async function reverseFinancePayment(token: string, userId: string, paymentId: string, body: FinanceRecord) {
  return apiRequest<{ payment_reversal: FinanceRecord }>(
    `/admin/finance/members/${userId}/payments/${paymentId}/reversals`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

export async function reverseCreditLedgerEntry(token: string, userId: string, entryId: string, body: FinanceRecord) {
  return apiRequest<{ credit_ledger_entry: FinanceRecord }>(
    `/admin/finance/members/${userId}/credits/${entryId}/reversals`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

export async function fetchFinanceQueues(token: string, params: Record<string, string> = {}) {
  const query = new URLSearchParams(params).toString();
  return apiRequest<{ queues: Record<string, FinanceRecord[]> }>(
    `/admin/finance/queues${query ? `?${query}` : ""}`,
    { token },
  );
}

/** `locationIds` (the page branch filter) keeps the promotions valid at one of them or everywhere. */
export async function fetchPromotionCampaigns(token: string, locationIds?: string) {
  return apiRequest<{ promotion_campaigns: FinanceRecord[]; branch_filter?: LocationScopePayload }>(
    `/admin/finance/promotions${branchQuery(locationIds)}`,
    { token },
  );
}

export async function createPromotionCampaign(token: string, body: FinanceRecord) {
  return apiRequest<{ promotion_campaign: FinanceRecord }>("/admin/finance/promotions", {
    method: "POST",
    token,
    body,
  });
}

export async function fetchPromotionCodes(token: string, campaignId: string) {
  return apiRequest<{ promotion_codes: FinanceRecord[] }>(`/admin/finance/promotions/${campaignId}/codes`, {
    token,
  });
}

export async function createPromotionCode(token: string, campaignId: string, body: FinanceRecord) {
  return apiRequest<{ promotion_code: FinanceRecord }>(`/admin/finance/promotions/${campaignId}/codes`, {
    method: "POST",
    token,
    body,
  });
}

export async function redeemPromotion(token: string, userId: string, body: FinanceRecord) {
  return apiRequest<{ promotion_redemption: FinanceRecord }>(
    `/admin/finance/members/${userId}/promotion-redemptions`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

/** `locationIds` (the page branch filter) keeps the referrals of people at home there. */
export async function fetchReferralEvents(token: string, locationIds?: string) {
  return apiRequest<{ referral_events: FinanceRecord[]; branch_filter?: LocationScopePayload }>(
    `/admin/finance/referrals${branchQuery(locationIds)}`,
    { token },
  );
}

export async function createReferralEvent(token: string, body: FinanceRecord) {
  return apiRequest<{ referral_event: FinanceRecord }>("/admin/finance/referrals", {
    method: "POST",
    token,
    body,
  });
}

export async function fetchReferralPrograms(token: string) {
  return apiRequest<{ referral_programs: FinanceRecord[] }>("/admin/finance/referral-programs", { token });
}

export async function createReferralProgram(token: string, body: FinanceRecord) {
  return apiRequest<{ referral_program: FinanceRecord }>("/admin/finance/referral-programs", {
    method: "POST",
    token,
    body,
  });
}

export async function updateReferralProgram(token: string, referralProgramId: string, body: FinanceRecord) {
  return apiRequest<{ referral_program: FinanceRecord }>(
    `/admin/finance/referral-programs/${referralProgramId}`,
    {
      method: "PATCH",
      token,
      body,
    },
  );
}

export async function updateReferralEventStatus(token: string, referralEventId: string, status: string) {
  return apiRequest<{ referral_event: FinanceRecord }>(`/admin/finance/referrals/${referralEventId}/status`, {
    method: "PATCH",
    token,
    body: { status },
  });
}

/** `locationIds` (the page branch filter) keeps the rewards of recipients at home there. */
export async function fetchReferralRewards(token: string, locationIds?: string) {
  return apiRequest<{ referral_rewards: FinanceRecord[]; branch_filter?: LocationScopePayload }>(
    `/admin/finance/referral-rewards${branchQuery(locationIds)}`,
    { token },
  );
}

export async function createReferralReward(token: string, referralEventId: string, body: FinanceRecord) {
  return apiRequest<{ referral_reward: FinanceRecord }>(
    `/admin/finance/referrals/${referralEventId}/rewards`,
    {
      method: "POST",
      token,
      body,
    },
  );
}

export async function updateReferralRewardStatus(token: string, referralRewardId: string, status: string) {
  return apiRequest<{ referral_reward: FinanceRecord }>(
    `/admin/finance/referral-rewards/${referralRewardId}/status`,
    {
      method: "PATCH",
      token,
      body: { status },
    },
  );
}

export async function fetchAdminSearch(
  token: string,
  query = "",
  role = "all",
  filters: Record<string, string> = {},
) {
  const params = new URLSearchParams({ q: query, role, ...filters });
  return apiRequest<{ users: FinanceRecord[]; meta?: Record<string, unknown> }>(`/admin/search?${params.toString()}`, {
    token,
  });
}
