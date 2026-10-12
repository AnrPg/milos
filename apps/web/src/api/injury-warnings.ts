import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

// ADR-114 injury-aware workout safety warnings. Informational only: none of
// these calls gate an assignment, booking or execution.

export type AthleteInjuryWarnings = components["schemas"]["AthleteInjuryWarnings"];
export type ClassSlotInjuryWarnings = components["schemas"]["ClassSlotInjuryWarnings"];
export type MyWorkoutInjuryWarnings = components["schemas"]["MyWorkoutInjuryWarnings"];
export type AthleteInjuryWarningsRequest = components["schemas"]["AthleteInjuryWarningsRequest"];
export type MyInjuryWarningsAcknowledgement = components["schemas"]["MyInjuryWarningsAcknowledgement"];
export type InjuryWarning = MyWorkoutInjuryWarnings["warnings"][number];
export type InjuryWarningLevel = MyWorkoutInjuryWarnings["level"];
export type AthleteInjuryWarningEntry = AthleteInjuryWarnings["athletes"][number];
export type StaffInjuryWarningSurface = NonNullable<AthleteInjuryWarningsRequest["surface"]>;
export type SelfInjuryWarningSurface = NonNullable<MyInjuryWarningsAcknowledgement["surface"]>;

export async function evaluateAthleteInjuryWarnings(token: string, body: AthleteInjuryWarningsRequest) {
  return apiRequest<AthleteInjuryWarnings>("/admin/wellbeing/injury-warnings", {
    method: "POST",
    token,
    body,
  });
}

export async function acknowledgeAthleteInjuryWarnings(token: string, body: AthleteInjuryWarningsRequest) {
  return apiRequest<components["schemas"]["AthleteInjuryWarningsAcknowledged"]>(
    "/admin/wellbeing/injury-warnings/acknowledge",
    { method: "POST", token, body },
  );
}

export async function fetchSlotInjuryWarnings(token: string, slotId: string) {
  return apiRequest<ClassSlotInjuryWarnings>(`/admin/schedule/slots/${slotId}/injury-warnings`, { token });
}

export async function fetchMyWorkoutInjuryWarnings(
  token: string,
  workoutId: string,
  options: MyInjuryWarningsAcknowledgement = {},
) {
  const params = new URLSearchParams();
  if (options.surface) params.set("surface", options.surface);
  if (options.source_context_id) params.set("source_context_id", options.source_context_id);
  const suffix = params.toString() ? `?${params.toString()}` : "";

  return apiRequest<MyWorkoutInjuryWarnings>(`/me/workouts/${workoutId}/injury-warnings${suffix}`, { token });
}

export async function acknowledgeMyInjuryWarnings(
  token: string,
  workoutId: string,
  body: MyInjuryWarningsAcknowledgement = {},
) {
  return apiRequest<components["schemas"]["MyInjuryWarningsAcknowledged"]>(
    `/me/workouts/${workoutId}/injury-warnings/acknowledge`,
    { method: "POST", token, body },
  );
}
