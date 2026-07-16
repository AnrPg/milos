import { apiRequest } from "@/api/client";

export type FinanceRecord = Record<string, unknown>;

export async function fetchFinanceSummary(token: string) {
  return apiRequest<FinanceRecord>("/admin/finance/summary", { token });
}

export async function fetchFinancePackages(token: string) {
  return apiRequest<{ packages: FinanceRecord[] }>("/admin/finance/packages", { token });
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
  return apiRequest<{ members: FinanceRecord[]; meta: FinanceRecord }>(
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

export async function fetchPromotionCampaigns(token: string) {
  return apiRequest<{ promotion_campaigns: FinanceRecord[] }>("/admin/finance/promotions", { token });
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

export async function fetchReferralEvents(token: string) {
  return apiRequest<{ referral_events: FinanceRecord[] }>("/admin/finance/referrals", { token });
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

export async function fetchReferralRewards(token: string) {
  return apiRequest<{ referral_rewards: FinanceRecord[] }>("/admin/finance/referral-rewards", { token });
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
