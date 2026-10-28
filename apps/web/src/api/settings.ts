import { apiRequest } from "@/api/client";

export type GamificationSettings = {
  id?: string | null;
  /** ADR-222: streak shields each member gets at every renewal (0–5, 0 = off). */
  streak_shields: number;
  /** Day of the month the shields renew; null = each member's sign-up day. */
  streak_shield_reset_day: number | null;
  leaderboard_enabled: boolean;
  inserted_at?: string | null;
  updated_at?: string | null;
};

export type FinanceSettings = {
  id?: string | null;
  payment_reminder_interval_days: number;
  /** Days before a subscription ends to remind the client (0 = off). */
  subscription_expiry_reminder_days: number;
  /** Slack days after a subscription ends / invoice falls overdue before access is lost. */
  subscription_grace_days: number;
  document_mode: "invoice" | "receipt";
  package_modules?: string[];
  inserted_at?: string | null;
  updated_at?: string | null;
};

export type NotificationPushSettings = {
  id?: string | null;
  enabled: boolean;
  vapid_public_key: string | null;
  vapid_private_key_configured: boolean;
  vapid_subject: string | null;
  inserted_at?: string | null;
  updated_at?: string | null;
};

export type SchedulingSettings = {
  id?: string | null;
  default_capacity: number;
  default_auto_approve: boolean;
  default_booking_timeout_minutes: number;
  /** How many days ahead members may book; null means no limit. Packages can override it. */
  default_booking_window_days?: number | null;
  /** Hours before a class after which cancelling still uses the visit; null means no cutoff. */
  default_cancellation_cutoff_hours?: number | null;
  inserted_at?: string | null;
  updated_at?: string | null;
};

/** ADR-162: how members see the organization; only the owner edits it. */
export type ProviderKind = "gym" | "coach";
export type ProviderSettings = { kind: ProviderKind; editable: boolean };

/**
 * ADR-176: the gym's time zone. `source` is "confirmed" (an admin set it),
 * "inferred" (guessed from a staff device) or null (unknown, default zone).
 */
export type TimeZoneStatus = {
  timezone: string;
  source: "confirmed" | "inferred" | null;
  confirmed: boolean;
};

export type AdminSettingsPayload = {
  /** ADR-176: the gym's time zone. */
  time_zone?: TimeZoneStatus;
  gamification: GamificationSettings;
  finance: FinanceSettings;
  notifications: NotificationPushSettings;
  scheduling: SchedulingSettings;
  provider?: ProviderSettings;
  /** ADR-163: workout-authoring defaults. */
  workouts?: WorkoutAuthoringSettings;
};

export type WorkoutAuthoringSettings = {
  /** Starting value of «Εμφάνιση στόχων στα μέλη» on a workout without goals of its own. */
  wod_goals_visible_by_default: boolean;
  /** ADR-180: whether coaches may use the WOD assistant (on by default). */
  wod_assistant_enabled: boolean;
};

export type GamificationUpdate = Partial<
  Pick<GamificationSettings, "streak_shields" | "streak_shield_reset_day" | "leaderboard_enabled">
>;

export type FinanceUpdate = Partial<Pick<FinanceSettings, "payment_reminder_interval_days" | "subscription_expiry_reminder_days" | "subscription_grace_days" | "document_mode" | "package_modules">>;

export type NotificationPushUpdate = Partial<{
  vapid_public_key: string | null;
  vapid_private_key: string | null;
  vapid_subject: string | null;
}>;

export type AdminSettingsUpdate = {
  provider?: { kind: ProviderKind };
  gamification?: GamificationUpdate;
  finance?: FinanceUpdate;
  notifications?: NotificationPushUpdate;
  workouts?: Partial<WorkoutAuthoringSettings>;
  scheduling?: Partial<
    Pick<
      SchedulingSettings,
      | "default_capacity"
      | "default_auto_approve"
      | "default_booking_timeout_minutes"
      | "default_booking_window_days"
      | "default_cancellation_cutoff_hours"
    >
  >;
};

export async function fetchAdminSettings(token: string) {
  return apiRequest<AdminSettingsPayload>("/admin/settings", { token });
}

export async function updateAdminSettings(token: string, payload: AdminSettingsUpdate) {
  return apiRequest<AdminSettingsPayload>("/admin/settings", {
    method: "PATCH",
    token,
    body: payload,
  });
}

/** ADR-176: confirm the gym's zone, or report this device's zone as a guess. */
export async function updateTimeZone(
  token: string,
  payload: { timezone: string | null; source: "confirmed" | "inferred" },
) {
  const response = await apiRequest<{ time_zone: TimeZoneStatus }>("/admin/settings/time-zone", {
    method: "PUT",
    token,
    body: payload,
  });
  return response.time_zone;
}
