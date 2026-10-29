"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState, type ReactNode } from "react";

import { fetchAdminSettings } from "@/api/settings";
import { fetchSettingsCatalog, type CatalogSetting } from "@/api/setup";
import { useSession } from "@/components/session-provider";
import { FRESHNESS } from "@/lib/query-policy";

// CP-H1 (ADR-255, mockup s10 A): settings whose default suits most boxes live
// under «Προχωρημένα», closed by default. Settings the app or a setup recipe
// works out ("derive") are not inputs, and "remove" ones are not shown at all.
// The levels come from the API: `advanced_settings` on GET /admin/settings and
// the catalog GET /admin/setup/settings.

export const SETTINGS_CATALOG_KEY = ["admin", "setup", "settings"] as const;

export type SettingVerdict = CatalogSetting["verdict"];

export type SettingLevels = {
  /** Shown on the main screen. */
  basic: (key: string) => boolean;
  /** Under «Προχωρημένα», closed by default. */
  advanced: (key: string) => boolean;
  /** Not an input: the app or a recipe sets it, or no owner should see it. */
  hidden: (key: string) => boolean;
  /** How many settings sit under «Προχωρημένα». */
  advancedCount: number;
  ready: boolean;
};

/**
 * The catalog's verdicts as the app ships them (apps/api settings_catalog.ex),
 * used until GET /admin/setup/settings answers so the screen does not jump.
 */
export const DEFAULT_VERDICTS: Record<string, SettingVerdict> = {
  "organization.timezone": "derive",
  "organization.default_locale": "derive",
  "organization.invitation_lifetime_seconds": "remove",
  "branding.brand_name": "basic",
  "branding.logo": "basic",
  "branding.primary_color": "derive",
  "provider.kind": "derive",
  "access.role_grants": "advanced",
  "join_link.member": "basic",
  "join_link.athlete": "advanced",
  "workouts.wod_goals_visible_by_default": "advanced",
  "workouts.wod_assistant_enabled": "advanced",
  "onboarding.checklist": "derive",
  "finance.document_mode": "derive",
  "finance.package_modules": "derive",
  "finance.subscription_grace_days": "advanced",
  "finance.subscription_expiry_reminder_days": "advanced",
  "finance.payment_reminder_interval_days": "advanced",
  "finance.entitlement_enforcement_mode": "remove",
  "finance.entitlement_timezone": "derive",
  "scheduling.default_capacity": "basic",
  "scheduling.default_auto_approve": "basic",
  "scheduling.default_cancellation_cutoff_minutes": "basic",
  "scheduling.default_booking_window_days": "advanced",
  "scheduling.default_booking_timeout_minutes": "advanced",
  "gamification.leaderboard_enabled": "basic",
  "gamification.streak_shields": "advanced",
  "gamification.streak_shield_reset_day": "advanced",
  "check_in.window_before_minutes": "advanced",
  "check_in.window_after_minutes": "advanced",
  "check_in.open_gym_requires_package": "derive",
  "check_in.visitor_trial_offer": "advanced",
  "check_in.desk_override": "advanced",
  "check_in.door_rotation_seconds": "remove",
  "check_in.member_code_mode": "advanced",
  "check_in.geofence_reminder": "advanced",
  "community.member_groups": "advanced",
  "community.partners_enabled": "advanced",
  "trials.enabled": "basic",
  "trials.seats_per_class": "basic",
  "trials.bring_note": "basic",
  "trials.approval": "advanced",
  "trials.weekly_limit": "advanced",
  "trials.per_person_limit": "advanced",
  "trials.class_type_ids": "advanced",
  "trials.horizon_days": "advanced",
  "trials.first_timers_only": "advanced",
  "trials.no_show_consumes": "advanced",
  "trials.conversion_package_id": "derive",
  "ai.api_key": "advanced",
  "ai.model": "remove",
  "ai.scaling_enabled": "advanced",
  "ai.voice_enabled": "advanced",
  "referrals.active": "basic",
  "referrals.reward": "basic",
  "referrals.friend_reward": "basic",
  "referrals.qualifying_stage": "advanced",
  "referrals.attribution_days": "advanced",
  "referrals.yearly_cap": "advanced",
  "referrals.approval": "advanced",
  "class_type.name": "basic",
  "class_type.kind": "basic",
  "class_type.level": "advanced",
  "class_type.audiences": "advanced",
  "class_type.credit_cost": "advanced",
  "fiscal.identity": "basic",
  "fiscal.authority_connection": "advanced",
  "payments.account": "basic",
};

/** Pure: the levels from the catalog and the `advanced_settings` list. */
export function settingLevels(catalog: CatalogSetting[] | undefined, advancedSettings: string[] | undefined): SettingLevels {
  const verdicts = new Map<string, SettingVerdict>(
    catalog ? catalog.map((setting) => [setting.key, setting.verdict]) : Object.entries(DEFAULT_VERDICTS),
  );
  const advancedList = new Set(advancedSettings ?? []);
  const verdict = (key: string): SettingVerdict | undefined => verdicts.get(key);
  const hidden = (key: string) => verdict(key) === "derive" || verdict(key) === "remove";
  // A setting is advanced unless it is basic (ADR-255 §2).
  const basic = (key: string) => !hidden(key) && !advancedList.has(key) && verdict(key) === "basic";
  return {
    basic,
    hidden,
    advanced: (key: string) => !hidden(key) && !basic(key),
    advancedCount: [...verdicts.values()].filter((value) => value === "advanced").length,
    ready: catalog !== undefined,
  };
}

export function useSettingLevels(): SettingLevels {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const catalog = useQuery({
    queryKey: SETTINGS_CATALOG_KEY,
    queryFn: () => fetchSettingsCatalog(token!),
    enabled: Boolean(token),
    staleTime: FRESHNESS.reference,
  });
  const settings = useQuery({
    queryKey: ["admin", "settings"],
    queryFn: () => fetchAdminSettings(token!),
    enabled: Boolean(token),
  });
  return settingLevels(catalog.data?.settings, settings.data?.advanced_settings ?? catalog.data?.advanced_settings);
}

/**
 * «Προχωρημένα» inside one settings area: closed by default, one tap opens
 * it. `count` says how many settings it holds.
 */
export function AdvancedDisclosure({
  count,
  children,
  testId,
}: {
  count?: number;
  children: ReactNode;
  testId?: string;
}) {
  const t = useTranslations("AdvancedSettings");
  const [open, setOpen] = useState(false);
  const id = useId();
  return (
    <section
      className="rounded-2xl p-4"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
      data-testid={testId}
    >
      <button
        type="button"
        aria-expanded={open}
        aria-controls={id}
        onClick={() => setOpen((value) => !value)}
        className="flex w-full items-center justify-between gap-3 text-start"
      >
        <span className="min-w-0">
          <b className="block text-sm" style={{ color: "var(--text)" }}>{t("title")}</b>
          <span className="block text-xs" style={{ color: "var(--muted)" }}>
            {count ? t("hintCount", { count }) : t("hint")}
          </span>
        </span>
        <span aria-hidden="true" style={{ color: "var(--muted)" }}>{open ? "▴" : "▾"}</span>
      </button>
      {open ? (
        <div id={id} className="mt-4 space-y-4">
          {children}
        </div>
      ) : null}
    </section>
  );
}
