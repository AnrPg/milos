import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

export type MyEntitlementOperation = paths["/api/org/{organization_slug}/me/entitlement"]["get"];

export type AllowanceUsage = {
  limit: number | "unlimited";
  period: "calendar_week" | "calendar_month" | "subscription_period";
  period_start: string;
  period_end: string;
  committed: number;
  extensions: number;
  remaining: number | "unlimited";
};

export type EntitlementFreeze = {
  id?: string;
  starts_on: string;
  ends_on: string;
  extension_days: number;
  reason: string | null;
  cancelled_at: string | null;
};

export type EffectiveEntitlement = {
  status: string;
  /** Why: e.g. membership_package, subscription_grace, overdue_grace, overdue_invoice. */
  source?: string | null;
  /** Last day of access during the grace slack after a subscription ended or an invoice fell overdue. */
  grace_until?: string | null;
  enforcement_mode: string;
  plan: null | {
    entitlement_version: number;
    channels: string[];
    capabilities: string[];
    terms?: Record<string, unknown>;
    time_windows?: unknown[];
  };
  /** Set while every usable subscription is paused by a freeze (ADR-097). */
  frozen_until?: string | null;
  freezes?: EntitlementFreeze[];
  stacked_subscriptions?: Record<string, unknown>[];
  /** Includes per-class-type keys such as `class_visits:<class type id>` (ADR-096). */
  allowances: Partial<Record<string, AllowanceUsage>>;
  class_type_names?: Record<string, string>;
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

export type CorporateSeat =
  paths["/api/org/{organization_slug}/me/corporate-enrollment"]["post"]["responses"][201]["content"]["application/json"]["seat"];

/**
 * Join my company's corporate plan (ADR-098). With a code the matching client
 * is used; without one the API matches my account email's domain.
 */
/** A company plan the account email qualifies for (ADR-098), or null. */
export async function fetchCorporateEnrollmentOffer(token: string) {
  const data = await apiRequest<{ offer: { company_name: string } | null }>("/me/corporate-enrollment", {
    token,
  });
  return data.offer;
}

export async function enrollCorporateSeat(token: string, code?: string | null) {
  const trimmed = code?.trim();
  return apiRequest<{ seat: CorporateSeat }>("/me/corporate-enrollment", {
    method: "POST",
    token,
    body: trimmed ? { code: trimmed } : {},
  });
}
