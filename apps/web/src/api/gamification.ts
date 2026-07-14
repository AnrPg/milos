import { apiRequest } from "@/api/client";

export type GamificationPreferences = {
  id?: string;
  user_id?: string;
  off_days: number[];
};

export type PRUnit = "mins_secs" | "reps" | "sets" | "kcals" | "m" | "kg";

export type PRRecord = {
  id: string;
  user_id: string;
  name: string;
  current_score: number;
  unit: PRUnit;
  higher_is_better: boolean;
  beaten_on: string;
  inserted_at: string;
  updated_at: string;
};

export type PRHistoryEntry = {
  id: string;
  pr_record_id: string;
  score: number;
  beaten_on: string;
  inserted_at: string;
};

export async function fetchGamificationPreferences(
  token: string,
): Promise<GamificationPreferences> {
  const data = await apiRequest<{ preferences: GamificationPreferences }>(
    "/gamification/preferences",
    { token },
  );
  return data.preferences;
}

export async function updateGamificationPreferences(
  token: string,
  params: Partial<GamificationPreferences>,
): Promise<GamificationPreferences> {
  const data = await apiRequest<{ preferences: GamificationPreferences }>(
    "/gamification/preferences",
    { method: "PUT", token, body: params },
  );
  return data.preferences;
}

export async function listPRs(token: string, query?: string): Promise<PRRecord[]> {
  const path = query
    ? `/prs?q=${encodeURIComponent(query)}`
    : "/prs";
  const data = await apiRequest<{ prs: PRRecord[] }>(path, { token });
  return data.prs;
}

export async function createPR(
  token: string,
  params: {
    name: string;
    current_score: number;
    unit: PRUnit;
    higher_is_better?: boolean;
    beaten_on: string;
  },
): Promise<PRRecord> {
  const data = await apiRequest<{ pr: PRRecord }>("/prs", {
    method: "POST",
    token,
    body: params,
  });
  return data.pr;
}

export async function updatePR(
  token: string,
  id: string,
  params: Partial<{
    name: string;
    current_score: number;
    unit: PRUnit;
    higher_is_better: boolean;
    beaten_on: string;
  }>,
): Promise<PRRecord> {
  const data = await apiRequest<{ pr: PRRecord }>(`/prs/${id}`, {
    method: "PATCH",
    token,
    body: params,
  });
  return data.pr;
}

export async function deletePR(token: string, id: string): Promise<void> {
  await apiRequest<void>(`/prs/${id}`, { method: "DELETE", token });
}

export async function getPRHistory(token: string, id: string): Promise<PRHistoryEntry[]> {
  const data = await apiRequest<{ history: PRHistoryEntry[] }>(`/prs/${id}/history`, { token });
  return data.history;
}

export async function sharePR(token: string, id: string): Promise<{ message: string }> {
  return apiRequest<{ message: string }>(`/prs/${id}/share`, {
    method: "POST",
    token,
  });
}
