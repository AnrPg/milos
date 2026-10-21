import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * The platform's plans (ADR-170): the public catalog, the plan card a gym's
 * or coach's owner sees, the vendors' console and the self-serve coach
 * practice.
 */
export type PlatformPlan = components["schemas"]["PlatformPlan"];
export type PlanLimits = components["schemas"]["PlatformPlanLimits"];
export type OrganizationPlan = components["schemas"]["OrganizationPlan"];
export type PlanUsage = OrganizationPlan["usage"][number];
export type OrganizationSubscription = components["schemas"]["OrganizationPlatformSubscription"];
export type SubscriptionStatus = OrganizationSubscription["stored_status"];
export type CoachPractice = components["schemas"]["CoachPractice"];

export type PlanInput = Partial<Omit<PlatformPlan, "limits">> & { limits?: PlanLimits };

export type PlanAssignment = {
  plan_code: string;
  status: SubscriptionStatus;
  trial_ends_at?: string | null;
  price_override_cents?: number | null;
  notes?: string | null;
};

export const ADMIN_PLAN_KEY = ["admin", "plan"] as const;
export const PLATFORM_PLANS_KEY = ["platform", "plans"] as const;
export const PLATFORM_SUBSCRIPTIONS_KEY = ["platform", "subscriptions"] as const;

export function fetchPublicPlans(audience?: "gym" | "coach") {
  const query = audience ? `?audience=${audience}` : "";
  return apiRequest<{ plans: PlatformPlan[] }>(`/public/platform-plans${query}`, { scope: "account" });
}

export function fetchAdminPlan(token: string) {
  return apiRequest<OrganizationPlan>("/admin/plan", { token });
}

export function startCoachPractice(
  token: string,
  body: { name: string; team_name?: string | null; timezone?: string | null; default_locale?: string | null },
) {
  return apiRequest<CoachPractice>("/coach-practices", { method: "POST", token, scope: "account", body });
}

export function fetchPlatformPlans(token: string) {
  return apiRequest<{ plans: PlatformPlan[] }>("/platform/plans", { token, scope: "account" });
}

export function createPlatformPlan(token: string, body: PlanInput) {
  return apiRequest<PlatformPlan>("/platform/plans", { method: "POST", token, scope: "account", body });
}

export function updatePlatformPlan(token: string, code: string, body: PlanInput) {
  return apiRequest<PlatformPlan>(`/platform/plans/${encodeURIComponent(code)}`, {
    method: "PATCH",
    token,
    scope: "account",
    body,
  });
}

export function fetchPlatformSubscriptions(token: string) {
  return apiRequest<{ subscriptions: OrganizationSubscription[] }>("/platform/subscriptions", {
    token,
    scope: "account",
  });
}

export function assignPlatformPlan(token: string, organizationId: string, body: PlanAssignment) {
  return apiRequest<OrganizationSubscription>(`/platform/organizations/${organizationId}/plan`, {
    method: "PUT",
    token,
    scope: "account",
    body,
  });
}
