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
