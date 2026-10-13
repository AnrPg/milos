import { apiRequest } from "@/api/client";
import type { ThemeSlug } from "@/lib/theme";

export type GamificationSettings = {
  id?: string | null;
  weekly_workout_target: number;
  streak_shield_reset_day: number | null;
  leaderboard_enabled: boolean;
  theme_slug: ThemeSlug;
  inserted_at?: string | null;
  updated_at?: string | null;
};

export type FinanceSettings = {
  id?: string | null;
  payment_reminder_interval_days: number;
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

export type AdminSettingsPayload = {
  gamification: GamificationSettings;
  finance: FinanceSettings;
  notifications: NotificationPushSettings;
  scheduling: SchedulingSettings;
};

export type GamificationUpdate = Partial<
  Pick<GamificationSettings, "weekly_workout_target" | "streak_shield_reset_day" | "leaderboard_enabled" | "theme_slug">
>;

export type FinanceUpdate = Partial<Pick<FinanceSettings, "payment_reminder_interval_days" | "document_mode" | "package_modules">>;

export type NotificationPushUpdate = Partial<{
  vapid_public_key: string | null;
  vapid_private_key: string | null;
  vapid_subject: string | null;
}>;

export type AdminSettingsUpdate = {
  gamification?: GamificationUpdate;
  finance?: FinanceUpdate;
  notifications?: NotificationPushUpdate;
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
