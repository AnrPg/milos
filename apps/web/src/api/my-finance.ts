import { apiRequest } from "@/api/client";

export type FinanceMembership = Record<string, unknown>;
export type FinancePackageSubscription = Record<string, unknown>;
export type FinanceInvoice = Record<string, unknown>;
export type FinancePayment = Record<string, unknown>;
export type FinanceCreditEntry = Record<string, unknown>;
export type FinancePromoRedemption = Record<string, unknown>;
export type FinancePackage = Record<string, unknown>;

export interface MyFinanceData {
  membership: FinanceMembership | null;
  active_package_subscription: FinancePackageSubscription | null;
  invoices: FinanceInvoice[];
  payments: FinancePayment[];
  credit_balance: number;
  total_outstanding_balance_cents: number;
  referral_credits: FinanceCreditEntry[];
  promotion_redemptions: FinancePromoRedemption[];
  available_packages: FinancePackage[];
}

export async function fetchMyFinance(token: string) {
  return apiRequest<MyFinanceData>("/me/finance", { token });
}

export async function getMyInvoiceDownloadUrl(token: string, invoiceId: string) {
  return apiRequest<{ download_url: string; file_name: string }>(
    `/me/invoices/${invoiceId}/download-url`,
    { token },
  );
}
