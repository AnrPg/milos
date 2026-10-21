import { apiRequest } from "@/api/client";
import type { components, operations } from "@/api/generated/schema";

// ADR-175: voice logging. A recording becomes a draft training-log entry;
// nothing is saved until the member confirms the log form.

type Json<T> = T extends { content: { "application/json": infer Body } } ? Body : never;

type AvailabilityResponse = Json<operations["PaleeWeb.MyVoiceLogController.show"]["responses"][200]>;
export type VoiceDraftResponse = Json<operations["PaleeWeb.MyVoiceLogController.create"]["responses"][200]>;
export type VoiceAvailability = AvailabilityResponse["voice"];
export type VoiceDraft = components["schemas"]["VoiceLogDraft"];
export type VoiceDraftRequest = components["schemas"]["VoiceLogDraftRequest"];

export const VOICE_AVAILABILITY_KEY = ["training-log", "voice"] as const;

const BASE = "/me/training-log/voice";

export async function fetchVoiceAvailability(token: string): Promise<VoiceAvailability | null> {
  const response = await apiRequest<AvailabilityResponse>(BASE, { token });
  return response?.voice ?? null;
}

export async function createVoiceDraft(token: string, body: VoiceDraftRequest): Promise<VoiceDraftResponse> {
  return apiRequest<VoiceDraftResponse>(`${BASE}/drafts`, { method: "POST", token, body });
}
