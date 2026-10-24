import { apiRequest } from "@/api/client";
import type { JournalComment, JournalCommentInput } from "@/api/journal-comments";

export type GamificationPreferences = {
  id?: string;
  user_id?: string;
  off_days: number[];
  /** ADR-196: my PRs in the Feed's celebrations; off until I opt in. */
  pr_celebrations?: boolean;
  /** ADR-196: my name in challenge rankings; on unless I opt out. */
  challenge_rankings?: boolean;
};

export type PRUnit = "mins_secs" | "reps" | "sets" | "kcals" | "m" | "kg";

export type PRSupportingMetricKey =
  | "reps"
  | "sets"
  | "load_kg"
  | "duration_seconds"
  | "distance_m"
  | "calories"
  | "rounds"
  | "variation";

export type PRSupportingMetrics = Partial<{
  reps: number;
  sets: number;
  load_kg: number;
  duration_seconds: number;
  distance_m: number;
  calories: number;
  rounds: number;
  variation: string;
}>;

export type PRRecord = {
  id: string;
  user_id: string;
  /** ADR-129 provenance: the gym the PR was set in, or null for a personal PR. */
  organization_id?: string | null;
  name: string;
  current_score: number;
  unit: PRUnit;
  higher_is_better: boolean;
  beaten_on: string;
  supporting_metrics: PRSupportingMetrics;
  /** Σχόλια on the PR (ADR-140 §1); absent where the reader may not see them. */
  comments?: JournalComment[];
  /** ADR-196: whether the people who follow me see this PR on my profile. */
  profile_audience?: PRProfileAudience;
  inserted_at: string;
  updated_at: string;
};

export type PRProfileAudience = "private" | "followers";

/** A PR as it shows on someone's profile (ADR-196). */
export type ProfilePR = Pick<
  PRRecord,
  "id" | "organization_id" | "name" | "current_score" | "unit" | "higher_is_better" | "beaten_on" | "supporting_metrics"
>;

export type PRHistoryEntry = {
  id: string;
  pr_record_id: string;
  score: number;
  beaten_on: string;
  supporting_metrics: PRSupportingMetrics;
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
    supporting_metrics?: PRSupportingMetrics;
    /** Σχόλια written with the PR, saved in the same transaction. */
    comments?: JournalCommentInput[];
    /** ADR-129: the gym the PR was set in; omit or null for a personal PR. */
    organization_slug?: string | null;
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
    supporting_metrics: PRSupportingMetrics;
    comments: JournalCommentInput[];
  }>,
): Promise<PRRecord> {
  const data = await apiRequest<{ pr: PRRecord }>(`/prs/${id}`, {
    method: "PATCH",
    token,
    body: params,
  });
  return data.pr;
}

export async function editPR(
  token: string,
  id: string,
  params: Partial<{
    name: string;
    current_score: number;
    unit: PRUnit;
    higher_is_better: boolean;
    beaten_on: string;
    supporting_metrics: PRSupportingMetrics;
    comments: JournalCommentInput[];
  }>,
): Promise<PRRecord> {
  const data = await apiRequest<{ pr: PRRecord }>(`/prs/${id}/edit`, {
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

/** Show one PR on my profile to the people who follow me, or keep it private (ADR-196). */
export async function setPRProfileAudience(token: string, id: string, audience: PRProfileAudience): Promise<PRRecord> {
  const data = await apiRequest<{ pr: PRRecord }>(`/prs/${id}/profile-audience`, {
    method: "PUT",
    token,
    body: { audience },
  });
  return data.pr;
}

/** The PRs a person shows on their profile, as I, a follower, see them (ADR-196). */
export async function fetchProfilePRs(token: string, userId: string): Promise<ProfilePR[]> {
  const data = await apiRequest<{ prs: ProfilePR[] }>(`/prs/profile/${userId}`, { token });
  return data.prs;
}
