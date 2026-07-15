import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

export type MyEntitlementOperation = paths["/api/me/entitlement"]["get"];

export type AllowanceUsage = {
  limit: number | "unlimited";
  period: "calendar_week" | "calendar_month" | "subscription_period";
  period_start: string;
  period_end: string;
  committed: number;
  extensions: number;
  remaining: number | "unlimited";
};

export type EffectiveEntitlement = {
  status: string;
  enforcement_mode: string;
  plan: null | {
    entitlement_version: number;
    channels: string[];
    capabilities: string[];
  };
  allowances: Partial<Record<"class_visits" | "coaching_touchpoints", AllowanceUsage>>;
  usage_entries: Array<{
    id: string;
    allowance_key: string;
    event_type: string;
    quantity_delta: number;
    parent_entry_id: string | null;
    reason: string | null;
    period_start: string;
    period_end: string;
    inserted_at: string;
  }>;
};

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

export async function fetchMyEntitlement(token: string) {
  return apiRequest<{ entitlement: EffectiveEntitlement | null }>("/me/entitlement", { token });
}

export async function getMyInvoiceDownloadUrl(token: string, invoiceId: string) {
  return apiRequest<{ download_url: string; file_name: string }>(
    `/me/invoices/${invoiceId}/download-url`,
    { token },
  );
}
