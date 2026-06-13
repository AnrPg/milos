import { apiRequest } from "@/api/client";

export type ChallengeRule = {
  condition:
    | "workout_type"
    | "scale_level"
    | "pr_beaten"
    | "weekly_consistency"
    | "rare_workout_type"
    | "team_workout_streak";
  type?: string;
  slug?: string;
  threshold?: number;
  threshold_pct?: number;
  min_count?: number;
  points: number;
  label?: string;
};

export type AdminChallengeRecord = {
  id: string;
  title: string;
  description: string | null;
  criteria_type: string;
  criteria_value: Record<string, unknown>;
  badge_key: string;
  badge_label: string;
  starts_at: string;
  ends_at: string;
  progress_summary: {
    participants: number;
    completed: number;
    average_progress: number;
    completion_rate: number;
    target: number;
  };
};

export type ChallengeParticipantRecord = {
  user_id: string;
  nickname: string | null;
  role: string | null;
  progress: number;
  target: number;
  completion_ratio: number;
  completed_at: string | null;
  updated_at: string;
  completions_done: number | null;
  completions_remaining: number | null;
};

export type SaveChallengePayload = {
  title: string;
  description?: string | null;
  criteria_type: "workout_count" | "workout_type_count" | "pr_count" | "custom";
  criteria_value: Record<string, unknown>;
  badge_key: string;
  badge_label: string;
  starts_at: string;
  ends_at: string;
};

export type AdminChallengeDetailResponse = {
  challenge: AdminChallengeRecord;
  participants: ChallengeParticipantRecord[];
};

export type ChallengeLeaderboardEntry = {
  user_id: string;
  nickname: string | null;
  progress: number;
  target: number;
  completed_at: string | null;
  rank: number;
};

export type ChallengeLeaderboardResponse = {
  challenge_id: string;
  participants: ChallengeLeaderboardEntry[];
  my_rank: number | null;
  my_progress: number | null;
};

export async function fetchAdminChallenges(token: string) {
  return apiRequest<{ challenges: AdminChallengeRecord[] }>("/admin/challenges", { token });
}

export async function fetchAdminChallenge(token: string, id: string) {
  return apiRequest<AdminChallengeDetailResponse>(`/admin/challenges/${id}`, { token });
}

export async function createAdminChallenge(token: string, payload: SaveChallengePayload) {
  return apiRequest<{ challenge: AdminChallengeRecord }>("/admin/challenges", {
    method: "POST",
    token,
    body: payload,
  });
}

export async function updateAdminChallenge(
  token: string,
  id: string,
  payload: SaveChallengePayload,
) {
  return apiRequest<{ challenge: AdminChallengeRecord }>(`/admin/challenges/${id}`, {
    method: "PATCH",
    token,
    body: payload,
  });
}

export async function fetchChallengeLeaderboard(token: string, id: string) {
  return apiRequest<ChallengeLeaderboardResponse>(`/challenges/${id}/leaderboard`, { token });
}

export async function optInChallenge(token: string, id: string) {
  return apiRequest<{ opted_in: boolean }>(`/challenges/${id}/opt_in`, {
    method: "POST",
    token,
  });
}

export async function optOutChallenge(token: string, id: string) {
  return apiRequest<{ opted_in: boolean }>(`/challenges/${id}/opt_in`, {
    method: "DELETE",
    token,
  });
}
