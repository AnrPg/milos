import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

export type AdminOnboardingChecklist = components["schemas"]["AdminOnboardingChecklist"];
export type OnboardingStepId = AdminOnboardingChecklist["steps"][number]["id"];
export type OnboardingAction = "complete" | "skip" | "reopen" | "dismiss" | "restore" | "tour_completed";

export function fetchAdminOnboarding(token: string) {
  return apiRequest<AdminOnboardingChecklist>("/admin/onboarding", { token });
}

export function updateAdminOnboarding(token: string, action: OnboardingAction, step?: OnboardingStepId) {
  return apiRequest<AdminOnboardingChecklist>("/admin/onboarding", {
    method: "PATCH",
    token,
    body: step ? { action, step } : { action },
  });
}

export type TourAudience = "admin" | "member" | "athlete";

/** Stores tour completion on the account so it follows the user across devices. */
export function completeProductTour(token: string, audience: TourAudience) {
  return apiRequest<{ completed_tours: string[] }>(`/me/tours/${audience}/complete`, { method: "POST", token });
}
