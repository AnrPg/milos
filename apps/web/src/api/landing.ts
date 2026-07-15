import { apiRequest } from "@/api/client";
import type { WorkoutExecution } from "@/api/executions";

export type BadgeRecord = {
  id: string;
  badge_key: string;
  label: string;
  earned_at: string;
};

export type LastProgressEvent = {
  total_points: number;
  events: Array<{ points: number; label: string }>;
};

export type ChallengeRecord = {
  id: string;
  title: string;
  description: string | null;
  badge_key: string;
  badge_label: string;
  criteria_type: string;
  target: number;
  progress: number;
  completed: boolean;
  completed_at: string | null;
  starts_at: string;
  ends_at: string;
  has_rules: boolean;
  increment_per_completion: number | null;
  completions_remaining: number;
  is_opted_in: boolean;
  last_progress_event: LastProgressEvent | null;
};

export type LeaderboardEntry = {
  rank: number;
  user_id: string;
  nickname: string;
  workouts_this_week: number;
  prs_this_month: number;
};

export type CoachNoteRecord = {
  id: string;
  admin_id: string;
  athlete_id: string;
  body: string;
  inserted_at: string;
};

export type TrainingQuote = {
  body: string;
  author: string | null;
};

export type AdminMetrics = {
  member_count: number;
  total_outstanding_cents: number;
  pending_referral_approvals: number;
  classes_today: number;
};

export type LandingPayload = {
  role?: string;
  quote?: TrainingQuote | null;
  admin_metrics?: AdminMetrics;
  gamification: {
    settings: {
      weekly_workout_target: number;
      streak_shield_reset_day: number | null;
      leaderboard_enabled: boolean;
    };
    stats: {
      current_streak: number;
      longest_streak: number;
      total_workouts: number;
      total_prs: number;
      current_streak_shields: number;
      consistency_score: number;
      motivation_score: number;
      perseverance_score: number;
      advancement_count: number;
      last_workout_at: string | null;
    };
    preferences: {
      off_days: number[];
    } | null;
    badges: BadgeRecord[];
    active_challenges: ChallengeRecord[];
    leaderboard: {
      visible: boolean;
      opted_in: boolean;
      weekly: LeaderboardEntry[];
      monthly: LeaderboardEntry[];
    };
  };
  coach_notes: CoachNoteRecord[];
  membership: null | {
    package_name?: string | null;
    package_code?: string | null;
    expiration_date?: string | null;
    last_paid?: string | null;
    amount?: number | null;
    currency?: string | null;
    notes?: string | null;
    entitlement_status?: string | null;
    entitlement_source?: string | null;
  };
  recent_executions: WorkoutExecution[];
};

export async function fetchLandingPayload(token: string) {
  return apiRequest<LandingPayload>("/landing", { token });
}

export async function updateLeaderboardOptIn(token: string, optedIn: boolean) {
  return apiRequest<{
    opted_in: boolean;
    visible: boolean;
    weekly: LeaderboardEntry[];
    monthly: LeaderboardEntry[];
  }>("/landing/leaderboard-opt-in", {
    method: "POST",
    token,
    body: { opted_in: optedIn },
  });
}
