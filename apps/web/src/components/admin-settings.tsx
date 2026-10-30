"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useTranslations } from "next-intl";
import { localizeError } from "@/i18n/presentation";
import { Suspense, useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  fetchAdminSettings,
  updateAdminSettings,
  type FinanceSettings,
  type GamificationSettings,
  type SchedulingSettings,
} from "@/api/settings";
import {
  fetchFinanceCleanupRecords,
  purgeFinanceRecord,
  type FinanceCleanupRecord,
} from "@/api/finance";
import { listScaleLevels, replaceScaleLevels, type ScaleLevel } from "@/api/workouts";
import { newLevelCode } from "@/lib/scale-level-code";
import { adminLogoApi, fetchAdminBranding } from "@/api/organization-branding";
import { TenantLogoUploader } from "@/components/branding/TenantLogoUploader";
import { useSession } from "@/components/session-provider";
import { ClassTypeSettings } from "@/components/admin/ClassTypeSettings";
import { LocationSettings } from "@/components/admin/LocationSettings";
import { PublicPageLink } from "@/components/admin/public-page/PublicPageLink";
import { TrialsLink } from "@/components/admin/trials/TrialsLink";
import { CommunitySettingsLink } from "@/components/admin/community/CommunitySettings";
import { CheckInSettingsLink } from "@/components/check-in/CheckInSettings";
import { FiscalIdentityLink } from "@/components/fiscal/FiscalIdentityLink";
import { SpacesSettingsLink } from "@/components/spaces/SpacesSettings";
import { BoxScreensSettingsLink } from "@/components/box-screen/BoxScreensSettings";
import { RoleAccessSettings } from "@/components/admin/RoleAccessSettings";
import { OrganizationOwnerSettings } from "@/components/admin/OrganizationOwnerSettings";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";
import { IntegerInput } from "@/components/integer-input";
import { DurationLimitField } from "@/components/schedule/BookingRuleFields";
import { PageHeader } from "@/components/PageHeader";
import { ClientAccessPanel } from "@/components/invites/InviteClients";
import { AdminOnboardingPanel } from "@/components/onboarding/Onboarding";
import { GymTimeZoneSetting } from "@/components/admin/GymTimeZoneSetting";
import { ProviderKindSetting } from "@/components/providers/ProviderKindSetting";
import { WodGoalsDefaultSetting } from "@/components/wod-goals/WodGoalsDefaultSetting";
import { WodAssistantSetting } from "@/components/workouts/creation/WodAssistantSetting";
import { WorkoutTypesSetting } from "@/components/workouts/WorkoutTypesSetting";
import { AiScalingSettings } from "@/components/scaling/AiScalingSettings";
import { PlanCard, PlanNotice } from "@/components/solo-coach/PlanCard";
import { Dialog } from "@/components/ui/Dialog";
import { Popover } from "@/components/ui/Popover";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { OnlinePaymentsSettings } from "@/components/admin/payments/OnlinePaymentsSettings";
import { useSettingLevels, type SettingLevels } from "@/components/settings/AdvancedSettings";
import { AdvancedSettingsCard } from "@/components/settings/AdvancedSettingsCard";

// ADR-255 (mockup s10 A): every form below shows either its basic fields (the
// main screen) or its advanced ones (inside «Προχωρημένα»).
type Part = "basic" | "advanced";

function partShows(levels: SettingLevels, part: Part) {
  return (key: string) => (part === "basic" ? levels.basic(key) : levels.advanced(key));
}

/**
 * The basic and the advanced part of one area are two forms over the same
 * settings. When the other part saves, take the new server values but keep
 * what was typed here and not saved yet.
 */
export function mergeServerForm<F extends Record<string, unknown>>(form: F, lastServer: F | null, next: F): F {
  if (!lastServer) return next;
  const merged = { ...next };
  for (const key of Object.keys(next) as Array<keyof F>) {
    if (JSON.stringify(form[key]) !== JSON.stringify(lastServer[key])) merged[key] = form[key];
  }
  return merged;
}

// ── Shared sub-components ────────────────────────────────────────────────────

function SaveBar({
  dirty,
  pending,
  success,
  error,
  onSave,
  onReset,
}: {
  dirty: boolean;
  pending: boolean;
  success: boolean;
  error: unknown;
  onSave: () => void;
  onReset: () => void;
}) {
  const i18n = useUiTranslations();
  const msg = error instanceof Error ? localizeError(error, i18n) : null;
  return (
    <div className="flex flex-wrap items-center gap-3 pt-2">
      <button
        className="rounded-full px-5 py-3 text-sm font-semibold disabled:opacity-60"
        disabled={!dirty || pending}
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        type="button"
        onClick={onSave}
      >
        {pending ? i18n("saving56a2285") : i18n("saveefc007a")}
      </button>
      {dirty && (
        <button
          className="rounded-full px-5 py-3 text-sm font-semibold"
          style={{ background: "var(--panel-muted)", color: "var(--muted)" }}
          type="button"
          onClick={onReset}
        >
          {i18n("reset44c57ab")}
        </button>
      )}
      {msg && <ErrorNotice>{msg}</ErrorNotice>}
      {success && !dirty && <p className="text-sm" style={{ color: "var(--success)" }}>{i18n("saved9d4af69")}</p>}
    </div>
  );
}

function FieldInfo({
  active,
  label,
  onToggle,
  children,
}: {
  active: boolean;
  label: string;
  onToggle: () => void;
  children: React.ReactNode;
}) {
  const i18n = useUiTranslations();
  const buttonRef = useRef<HTMLButtonElement>(null);

  return (
    <span className="relative inline-flex shrink-0">
      <button
        ref={buttonRef}
        aria-label={label}
        aria-expanded={active}
        className="flex h-7 w-7 items-center justify-center rounded-full text-xs font-bold transition-colors"
        style={{
          background: active ? "color-mix(in srgb, var(--primary) 18%, transparent)" : "var(--panel-muted)",
          border: active ? "1px solid color-mix(in srgb, var(--primary) 40%, transparent)" : "1px solid var(--border)",
          color: active ? "var(--primary)" : "var(--dim)",
        }}
        type="button"
        onClick={(e) => { e.preventDefault(); onToggle(); }}
      >
        {i18n("i042dc45")}
      </button>
      <Popover
        anchorRef={buttonRef}
        open={active}
        onClose={onToggle}
        align="end"
        width={352}
        role="dialog"
        ariaLabel={label}
        className="rounded-2xl shadow-[var(--shadow-lg)]"
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)" }}
      >
        <div className="space-y-2 p-4 text-start text-xs normal-case leading-5 tracking-normal [&_p]:m-0" style={{ color: "var(--text-soft)" }}>
          {children}
        </div>
      </Popover>
    </span>
  );
}

function CollapsibleSection({
  id,
  title,
  description,
  defaultOpen = true,
  children,
}: {
  id: string;
  title: string;
  description?: string;
  defaultOpen?: boolean;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <section id={id} className="overflow-hidden rounded-[2.4rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <button
        className="flex w-full items-center justify-between gap-4 p-8 text-start"
        type="button"
        onClick={() => setOpen((v) => !v)}
      >
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--primary)" }}>
            {title}
          </p>
          {description && (
            <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{description}</p>
          )}
        </div>
        <span className="text-xl font-light" style={{ color: "var(--dim)" }}>{open ? "−" : "+"}</span>
      </button>
      {open && (
        <div className="border-t px-8 pb-8 pt-6" style={{ borderColor: "var(--border)" }}>
          {children}
        </div>
      )}
    </section>
  );
}

// ── Branding section (ADR-121) ───────────────────────────────────────────────

function BrandingSection({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const brandingQuery = useQuery({
    queryKey: ["admin", "branding"],
    queryFn: () => fetchAdminBranding(token),
  });
  const api = useMemo(() => adminLogoApi(token), [token]);

  if (brandingQuery.isError) {
    return (
      <ErrorNotice>
        {localizeError(brandingQuery.error, i18n)}
      </ErrorNotice>
    );
  }

  if (!brandingQuery.data) {
    return <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>;
  }

  return (
    <TenantLogoUploader
      api={api}
      currentUrl={brandingQuery.data.brand_logo_url ?? null}
      uploaded={brandingQuery.data.brand_logo_uploaded}
      onChange={(branding) => {
        queryClient.setQueryData(["admin", "branding"], branding);
        // The shell header and organization selector read the logo from memberships.
        void queryClient.invalidateQueries({ queryKey: ["organization-memberships"] });
      }}
    />
  );
}

// ── Gamification section ─────────────────────────────────────────────────────

// ADR-229: the box sets only the streak shields and when they renew; the
// weekly workout goal is each person's own.
type GamificationFormState = {
  streakShields: string;
  streakShieldResetDay: string;
  leaderboardEnabled: boolean;
};

function formFromSettings(s: GamificationSettings): GamificationFormState {
  return {
    streakShields: String(s.streak_shields),
    streakShieldResetDay: s.streak_shield_reset_day ? String(s.streak_shield_reset_day) : "",
    leaderboardEnabled: s.leaderboard_enabled,
  };
}

export function GamificationSection({ token, part = "basic" }: { token: string; part?: Part }) {
  const i18n = useUiTranslations();
  const t = useTranslations("TrainingGoal");
  const show = partShows(useSettingLevels(), part);
  const queryClient = useQueryClient();
  const [form, setForm] = useState<GamificationFormState>({
    streakShields: "1",
    streakShieldResetDay: "",
    leaderboardEnabled: true,
  });
  const [initialized, setInitialized] = useState(false);
  const [activeHelp, setActiveHelp] = useState<string | null>(null);

  const settingsQuery = useQuery({
    queryKey: ["admin", "settings"],
    queryFn: () => fetchAdminSettings(token),
  });

  const lastServer = useRef<GamificationFormState | null>(null);
  useEffect(() => {
    if (!settingsQuery.data?.gamification) return;
    const next = formFromSettings(settingsQuery.data.gamification);
    queueMicrotask(() => {
      const previous = lastServer.current;
      setForm((current) => mergeServerForm(current, previous, next));
      lastServer.current = next;
      setInitialized(true);
    });
  }, [settingsQuery.data]);

  // Each part saves only the settings it shows.
  const saveMutation = useMutation({
    mutationFn: () =>
      updateAdminSettings(token, {
        gamification: {
          ...(show("gamification.streak_shields") ? { streak_shields: Number(form.streakShields) } : {}),
          ...(show("gamification.streak_shield_reset_day")
            ? { streak_shield_reset_day: form.streakShieldResetDay.trim() ? Number(form.streakShieldResetDay) : null }
            : {}),
          ...(show("gamification.leaderboard_enabled") ? { leaderboard_enabled: form.leaderboardEnabled } : {}),
        },
      }),
    onSuccess: (data) => {
      queryClient.setQueryData(["admin", "settings"], data);
    },
  });

  const serverForm = settingsQuery.data?.gamification
    ? formFromSettings(settingsQuery.data.gamification)
    : null;
  const dirty = initialized && serverForm !== null && JSON.stringify(form) !== JSON.stringify(serverForm);

  function update<K extends keyof GamificationFormState>(key: K, value: GamificationFormState[K]) {
    setForm((f) => ({ ...f, [key]: value }));
  }

  return (
    <div className="max-w-3xl space-y-4">
      {part === "basic" ? (
        <p className="rounded-[1.4rem] px-4 py-3 text-sm leading-6" style={{ background: "var(--panel-muted)", color: "var(--muted)" }} data-testid="weekly-goal-is-personal">
          {t("box.goalIsPersonal")}
        </p>
      ) : null}

      {show("gamification.streak_shields") ? (
      <label className="relative block space-y-2 rounded-[1.4rem] p-3">
        <span className="flex items-center justify-between gap-3">
          <span id="streak-shields-label" className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {t("box.shieldsLabel")}
          </span>
          <FieldInfo
            active={activeHelp === "shields"}
            label={t("box.shieldsInfo")}
            onToggle={() => setActiveHelp(activeHelp === "shields" ? null : "shields")}
          >
            <p>{t("box.shieldsHelp")}</p>
            <p>{t("box.shieldsValues")}</p>
          </FieldInfo>
        </span>
        <input
          className="w-full rounded-2xl border px-4 py-3 text-sm"
          inputMode="numeric"
          max={5}
          min={0}
          type="number"
          aria-labelledby="streak-shields-label"
          aria-describedby="streak-shields-hint"
          style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
          value={form.streakShields}
          onChange={(e) => update("streakShields", e.target.value)}
        />
        <span id="streak-shields-hint" className="block text-xs leading-5" style={{ color: "var(--dim)" }}>
          {t("box.shieldsHint")}
        </span>
      </label>
      ) : null}

      {show("gamification.streak_shield_reset_day") ? (
      <label className="relative block space-y-2 rounded-[1.4rem] p-3">
        <span className="flex items-center justify-between gap-3">
          <span id="streak-shield-renewal-label" className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {i18n("streakShieldResetDayd22b9ea")}
          </span>
          <FieldInfo
            active={activeHelp === "shield"}
            label={i18n("streakShieldResetDayInfo10555c2")}
            onToggle={() => setActiveHelp(activeHelp === "shield" ? null : "shield")}
          >
            <p>{t("box.renewalHelp")}</p>
          </FieldInfo>
        </span>
        <input
          className="w-full rounded-2xl border px-4 py-3 text-sm"
          inputMode="numeric"
          max={28}
          min={1}
          placeholder={i18n("useSignupRelativeMonthlyReseta55c3a9")}
          style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
          type="number"
          value={form.streakShieldResetDay}
          aria-labelledby="streak-shield-renewal-label"
          aria-describedby="streak-shield-renewal-hint"
          onChange={(e) => update("streakShieldResetDay", e.target.value)}
        />
        <span id="streak-shield-renewal-hint" className="block text-xs leading-5" style={{ color: "var(--dim)" }}>
          {form.streakShieldResetDay.trim() ? t("box.renewalOnDay", { day: form.streakShieldResetDay.trim() }) : t("box.renewalOnSignup")}
        </span>
      </label>
      ) : null}

      {show("gamification.leaderboard_enabled") ? (
      <label
        className="relative flex items-start gap-3 rounded-[1.6rem] border px-4 py-4"
        style={{ background: "var(--panel-muted)", borderColor: "var(--border)" }}
      >
        <input
          checked={form.leaderboardEnabled}
          className="mt-1 h-4 w-4"
          type="checkbox"
          onChange={(e) => update("leaderboardEnabled", e.target.checked)}
        />
        <span>
          <span className="flex items-center justify-between gap-3">
            <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
              {i18n("enableLeaderboardGloballyc5e326f")}
            </span>
            <FieldInfo
              active={activeHelp === "leaderboard"}
              label={i18n("enableLeaderboardGloballyInfo62095ee")}
              onToggle={() => setActiveHelp(activeHelp === "leaderboard" ? null : "leaderboard")}
            >
              <p>{i18n("masterSwitchForLeaderboardVisibilityWhenDisabledMemberd58f09d")}</p>
            </FieldInfo>
          </span>
          <span className="mt-1 block text-sm leading-6" style={{ color: "var(--muted)" }}>
            {i18n("whenDisabledMemberAndAthleteOptInHas1370e13")}
          </span>
        </span>
      </label>
      ) : null}

      <SaveBar
        dirty={dirty}
        pending={saveMutation.isPending}
        success={saveMutation.isSuccess}
        error={saveMutation.error}
        onSave={() => saveMutation.mutate()}
        onReset={() => serverForm && setForm(serverForm)}
      />
    </div>
  );
}

// ── Level Taxonomy section ───────────────────────────────────────────────────

function isDraftLevel(level: ScaleLevel) {
  return !level.id || level.id.startsWith("draft-");
}

// A saved level keeps its code: WOD text (`[scale: rx]`) and workout history
// point at it. A new level's code is derived from its name on save.
function levelCodes(levels: ScaleLevel[]) {
  const taken = levels.filter((level) => !isDraftLevel(level)).map((level) => level.slug);
  return levels.map((level, index) => {
    if (!isDraftLevel(level)) return level.slug;
    const code = newLevelCode(level.label, taken, index + 1);
    taken.push(code);
    return code;
  });
}

export function LevelTaxonomySection({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [levels, setLevels] = useState<ScaleLevel[]>([]);
  const [initialized, setInitialized] = useState(false);

  const levelsQuery = useQuery({
    queryKey: ["admin", "scale-levels"],
    queryFn: () => listScaleLevels(token),
  });

  useEffect(() => {
    if (!levelsQuery.data) return;
    const data = levelsQuery.data;
    queueMicrotask(() => { setLevels(data); setInitialized(true); });
  }, [levelsQuery.data]);

  const codes = levelCodes(levels);

  const saveMutation = useMutation({
    mutationFn: () =>
      replaceScaleLevels(token, {
        scale_levels: levels.map((l, i) => ({ slug: codes[i], label: l.label.trim(), sort_order: i + 1 })),
      }),
    onSuccess: (updated) => {
      setLevels(updated);
      queryClient.setQueryData(["admin", "scale-levels"], updated);
    },
  });

  const serverLevels = levelsQuery.data ?? [];
  const dirty = initialized && JSON.stringify(levels) !== JSON.stringify(serverLevels);
  const missingName = levels.some((level) => level.label.trim() === "");

  return (
    <div className="space-y-4">
      <p className="max-w-3xl text-sm leading-6" style={{ color: "var(--muted)" }}>
        {i18n("lvlHelpIntro")}
      </p>

      {levelsQuery.isLoading && (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
      )}

      <ol className="space-y-3" data-testid="level-taxonomy-list">
        {levels.map((level, index) => (
          <li
            key={level.id ?? level.slug ?? index}
            className="grid gap-3 rounded-[1.4rem] p-4 md:grid-cols-[2rem_1fr_auto] md:items-start"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <span className="pt-3 text-sm font-semibold tabular-nums" style={{ color: "var(--dim)" }}>{index + 1}</span>
            <label className="block space-y-1.5">
              <input
                aria-label={i18n("lvlNameLabel")}
                className="w-full rounded-2xl px-4 py-3 text-sm outline-none"
                placeholder={i18n("lvlNamePlaceholder")}
                style={{ background: "var(--bg)", border: `1px solid ${level.label.trim() === "" && !isDraftLevel(level) ? "var(--danger)" : "var(--border)"}`, color: "var(--text)" }}
                value={level.label}
                onChange={(e) =>
                  setLevels((cur) =>
                    cur.map((item, i) => (i === index ? { ...item, label: e.target.value } : item)),
                  )
                }
              />
              <span className="block text-xs leading-5" style={{ color: "var(--dim)" }}>
                {i18n("lvlCodeLine")}{" "}
                <code className="rounded px-1.5 py-0.5 font-mono" style={{ background: "var(--bg)", color: "var(--text)" }} data-testid="level-code">
                  {codes[index]}
                </code>
                {" · "}
                {isDraftLevel(level) ? i18n("lvlCodeNew") : i18n("lvlCodeFixed")}
              </span>
            </label>
            <button
              className="rounded-full px-4 py-2 text-sm transition-colors disabled:opacity-50"
              disabled={levels.length === 1}
              style={{ background: "var(--panel)", color: "var(--muted)" }}
              type="button"
              onClick={() =>
                setLevels((cur) => (cur.length === 1 ? cur : cur.filter((_, i) => i !== index)))
              }
            >
              {i18n("removee963907")}
            </button>
          </li>
        ))}
      </ol>

      <button
        className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
        style={{ background: "var(--panel-muted)", color: "var(--muted)" }}
        type="button"
        onClick={() =>
          setLevels((cur) => [
            ...cur,
            { id: `draft-${cur.length + 1}`, slug: "", label: "", sort_order: cur.length + 1, is_active: true },
          ])
        }
      >
        {i18n("addLeveld2d215f")}
      </button>

      <ul className="max-w-3xl list-disc space-y-1 pl-5 text-xs leading-5" style={{ color: "var(--dim)" }}>
        <li>{i18n("lvlHelpOrder")}</li>
        <li>{i18n("lvlHelpCode")}</li>
        <li>{i18n("lvlHelpRemove")}</li>
      </ul>

      {missingName ? <p className="text-sm" style={{ color: "var(--danger)" }}>{i18n("lvlNameRequired")}</p> : null}

      <SaveBar
        dirty={dirty && !missingName}
        pending={saveMutation.isPending}
        success={saveMutation.isSuccess}
        error={saveMutation.error}
        onSave={() => saveMutation.mutate()}
        onReset={() => setLevels(serverLevels)}
      />
    </div>
  );
}

// ── Main hub ─────────────────────────────────────────────────────────────────

// ── Finance section ──────────────────────────────────────────────────────────

function financeFormFromSettings(s: FinanceSettings) {
  return {
    paymentReminderIntervalDays: String(s.payment_reminder_interval_days),
    expiryReminderDays: String(s.subscription_expiry_reminder_days ?? 5),
    graceDays: String(s.subscription_grace_days ?? 3),
    documentMode: s.document_mode,
    packageModules: [...(s.package_modules ?? DEFAULT_PACKAGE_MODULES)].sort(),
  };
}

// ADR-096: services the gym offers; the package wizard only shows enabled ones.
const DEFAULT_PACKAGE_MODULES = ["group_classes", "online_coaching"];
const AVAILABLE_PACKAGE_MODULES = ["group_classes", "online_coaching", "open_gym", "events", "personal_training", "digital_content", "corporate_clients"] as const;

function DaysField({
  id,
  label,
  help,
  min,
  value,
  onChange,
}: {
  id: string;
  label: string;
  help: string;
  min: number;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <div className="space-y-1.5">
      <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }} htmlFor={id}>
        {label}
      </label>
      <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>
        {help}
      </p>
      <input
        id={id}
        type="number"
        min={min}
        max={60}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="w-28 rounded-xl px-4 py-2.5 text-sm outline-none"
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
      />
    </div>
  );
}

export function FinanceSection({ token, part = "basic" }: { token: string; part?: Part }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const show = partShows(useSettingLevels(), part);
  const [form, setForm] = useState({
    paymentReminderIntervalDays: "7",
    expiryReminderDays: "5",
    graceDays: "3",
    documentMode: "invoice" as "invoice" | "receipt",
    packageModules: DEFAULT_PACKAGE_MODULES,
  });
  const [initialized, setInitialized] = useState(false);

  const settingsQuery = useQuery({
    queryKey: ["admin", "settings"],
    queryFn: () => fetchAdminSettings(token),
  });

  useEffect(() => {
    if (!settingsQuery.data?.finance) return;
    const next = financeFormFromSettings(settingsQuery.data.finance);
    queueMicrotask(() => { setForm(next); setInitialized(true); });
  }, [settingsQuery.data]);

  const saveMutation = useMutation({
    mutationFn: () =>
      updateAdminSettings(token, {
        gamification: {},
        finance: {
          payment_reminder_interval_days: Number(form.paymentReminderIntervalDays),
          subscription_expiry_reminder_days: Number(form.expiryReminderDays),
          subscription_grace_days: Number(form.graceDays),
          document_mode: form.documentMode,
          package_modules: form.packageModules,
        },
      }),
    onSuccess: async (data) => {
      queryClient.setQueryData(["admin", "settings"], data);
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "package-catalog"] });
    },
  });

  const serverModules = [...(settingsQuery.data?.finance?.package_modules ?? DEFAULT_PACKAGE_MODULES)].sort().join(",");
  const serverDays = settingsQuery.data?.finance
    ? String(settingsQuery.data.finance.payment_reminder_interval_days)
    : "7";
  const serverMode = settingsQuery.data?.finance?.document_mode ?? "invoice";
  const serverForm = settingsQuery.data?.finance ? financeFormFromSettings(settingsQuery.data.finance) : null;
  const dirty =
    initialized &&
    (form.paymentReminderIntervalDays !== serverDays ||
      form.documentMode !== serverMode ||
      form.expiryReminderDays !== (serverForm?.expiryReminderDays ?? "5") ||
      form.graceDays !== (serverForm?.graceDays ?? "3") ||
      form.packageModules.join(",") !== serverModules);

  const anyField = ["finance.payment_reminder_interval_days", "finance.subscription_expiry_reminder_days", "finance.subscription_grace_days", "finance.document_mode", "finance.package_modules"].some(show);

  return (
    <div className="space-y-5">
      {show("finance.payment_reminder_interval_days") ? (
      <div className="space-y-1.5">
        <label
          className="block text-xs font-semibold uppercase tracking-[0.18em]"
          style={{ color: "var(--muted)" }}
          htmlFor="reminder-interval"
        >
          {i18n("reminderIntervalDaysee3ba34")}
        </label>
        <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>
          {i18n("howOftenInDaysAMemberWithAn710fa76")}
        </p>
        <input
          id="reminder-interval"
          type="number"
          min={1}
          max={365}
          value={form.paymentReminderIntervalDays}
          onChange={(e) => setForm((current) => ({ ...current, paymentReminderIntervalDays: e.target.value }))}
          className="w-28 rounded-xl px-4 py-2.5 text-sm outline-none"
          style={{
            background: "var(--panel-muted)",
            border: "1px solid var(--border)",
            color: "var(--text)",
          }}
        />
      </div>
      ) : null}
      {show("finance.subscription_expiry_reminder_days") ? (
      <DaysField
        id="expiry-reminder-days"
        label={i18n("subscriptionExpiryReminderDays")}
        help={i18n("subscriptionExpiryReminderDaysHelp")}
        min={0}
        value={form.expiryReminderDays}
        onChange={(value) => setForm((current) => ({ ...current, expiryReminderDays: value }))}
      />
      ) : null}
      {show("finance.subscription_grace_days") ? (
      <DaysField
        id="grace-days"
        label={i18n("subscriptionGraceDays")}
        help={i18n("subscriptionGraceDaysHelp")}
        min={0}
        value={form.graceDays}
        onChange={(value) => setForm((current) => ({ ...current, graceDays: value }))}
      />
      ) : null}
      {show("finance.document_mode") ? (
      <fieldset className="space-y-3">
        <legend className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
          {i18n("featureFinanceDocumentWorkflow")}
        </legend>
        <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>
          {i18n("featureFinanceDocumentDescription")}
        </p>
        <div className="grid gap-3 sm:grid-cols-2">
          {(["receipt", "invoice"] as const).map((mode) => (
            <label
              key={mode}
              className="flex cursor-pointer items-start gap-3 rounded-2xl p-4"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
            >
              <input
                checked={form.documentMode === mode}
                name="finance-document-mode"
                type="radio"
                value={mode}
                onChange={() => setForm((current) => ({ ...current, documentMode: mode }))}
              />
              <span>
                <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {mode === "receipt" ? i18n("featurePlainReceipts") : i18n("featureInvoices")}
                </span>
                <span className="mt-1 block text-xs leading-5" style={{ color: "var(--dim)" }}>
                  {mode === "receipt"
                    ? i18n("featureReceiptWorkflowDescription")
                    : i18n("featureInvoiceWorkflowDescription")}
                </span>
              </span>
            </label>
          ))}
        </div>
      </fieldset>
      ) : null}
      {show("finance.package_modules") ? (
      <fieldset className="space-y-3">
        <legend className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
          {i18n("pkgModulesTitle")}
        </legend>
        <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{i18n("pkgModulesDescription")}</p>
        <div className="grid gap-3 sm:grid-cols-2">
          {AVAILABLE_PACKAGE_MODULES.map((module) => {
            const checked = form.packageModules.includes(module);
            return (
              <label
                key={module}
                className="flex cursor-pointer items-start gap-3 rounded-2xl p-4"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
              >
                <input
                  type="checkbox"
                  checked={checked}
                  disabled={checked && form.packageModules.length === 1}
                  onChange={() =>
                    setForm((current) => ({
                      ...current,
                      packageModules: (checked
                        ? current.packageModules.filter((item) => item !== module)
                        : [...current.packageModules, module]
                      ).sort(),
                    }))
                  }
                />
                <span>
                  <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n(`pkgModule_${module}`)}</span>
                  <span className="mt-1 block text-xs leading-5" style={{ color: "var(--dim)" }}>{i18n(`pkgModule_${module}Hint`)}</span>
                </span>
              </label>
            );
          })}
        </div>
      </fieldset>
      ) : null}
      {anyField ? (
      <SaveBar
        dirty={dirty}
        pending={saveMutation.isPending}
        success={saveMutation.isSuccess}
        error={saveMutation.error}
        onSave={() => saveMutation.mutate()}
        onReset={() => setForm(serverForm ?? { paymentReminderIntervalDays: serverDays, expiryReminderDays: "5", graceDays: "3", documentMode: serverMode, packageModules: serverModules.split(",") })}
      />
      ) : null}

      {part === "basic" ? <FinanceCleanupSection token={token} /> : null}
    </div>
  );
}

function FinanceCleanupSection({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const [selected, setSelected] = useState<FinanceCleanupRecord | null>(null);
  const [password, setPassword] = useState("");
  const [reason, setReason] = useState("");

  const recordsQuery = useQuery({
    queryKey: ["admin", "finance", "cleanup-records", search],
    queryFn: () => fetchFinanceCleanupRecords(token, { q: search, limit: "50" }),
    enabled: open,
  });

  const purgeMutation = useMutation({
    mutationFn: () => {
      if (!selected) throw new Error("finance_cleanup_record_missing");

      return purgeFinanceRecord(token, selected.id, {
        record_type: selected.record_type,
        password,
        reason: reason.trim() || i18n("featureFinanceCleanupDefaultReason"),
      });
    },
    onSuccess: () => {
      setSelected(null);
      setPassword("");
      setReason("");
      void queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
      void queryClient.invalidateQueries({ queryKey: ["admin", "finance", "cleanup-records"] });
    },
  });

  const records = recordsQuery.data?.records ?? [];
  const canPurge = Boolean(selected && password.trim() && !purgeMutation.isPending);
  const errorMessage = purgeMutation.error instanceof Error ? localizeError(purgeMutation.error, i18n) : null;

  return (
    <div
      className="rounded-[1.4rem] border p-4"
      style={{ background: "var(--panel-muted)", borderColor: "var(--border)" }}
    >
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {i18n("featureFinanceCleanupTitle")}
          </p>
          <p className="mt-1 text-xs leading-5" style={{ color: "var(--dim)" }}>
            {i18n("featureFinanceCleanupDescription")}
          </p>
        </div>
        <button
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
          type="button"
          onClick={() => setOpen(true)}
        >
          {i18n("featureFinanceCleanupOpen")}
        </button>
      </div>

      {open ? (
        <Dialog
          onClose={() => setOpen(false)}
          title={i18n("featureFinanceCleanupModalTitle")}
          description={<span className="block max-w-2xl text-xs leading-5" style={{ color: "var(--dim)" }}>{i18n("featureFinanceCleanupModalDescription")}</span>}
          closeLabel={i18n("featureFinanceCleanupClose")}
          size="5xl"
          variant="center"
        >
            <div className="grid gap-4 lg:grid-cols-[1.35fr_0.85fr]">
              <div className="space-y-3">
                <input
                  className="w-full rounded-2xl border px-4 py-3 text-sm outline-none"
                  placeholder={i18n("featureFinanceCleanupSearchPlaceholder")}
                  style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                />
                <div className="space-y-2">
                  {recordsQuery.isLoading ? (
                    <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
                  ) : records.length === 0 ? (
                    <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("featureFinanceCleanupEmpty")}</p>
                  ) : (
                    records.map((record) => {
                      const active = selected?.id === record.id;
                      return (
                        <button
                          key={`${record.record_type}-${record.id}`}
                          className="w-full rounded-2xl border p-4 text-start transition-colors"
                          style={{
                            background: active
                              ? "color-mix(in srgb, var(--danger) 10%, var(--panel-muted))"
                              : "var(--panel-muted)",
                            borderColor: active ? "var(--danger)" : "var(--border)",
                          }}
                          type="button"
                          onClick={() => {
                            setSelected(record);
                            purgeMutation.reset();
                          }}
                        >
                          <span className="flex flex-wrap items-center justify-between gap-3">
                            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                              {record.code || record.label}
                            </span>
                            <span className="rounded-full px-2.5 py-1 text-[0.68rem] font-semibold uppercase tracking-[0.16em]" style={{ background: "var(--bg)", color: "var(--dim)" }}>
                              {record.record_type}
                            </span>
                          </span>
                          <span className="mt-2 block text-xs leading-5" style={{ color: "var(--dim)" }}>
                            {formatCleanupAmount(record)} · {record.status ?? i18n("featureFinanceCleanupUnknown")} · {record.issued_on ?? record.paid_on ?? record.inserted_at ?? ""}
                          </span>
                        </button>
                      );
                    })
                  )}
                </div>
              </div>

              <div className="space-y-4 rounded-2xl border p-4" style={{ background: "var(--panel-muted)", borderColor: "var(--border)" }}>
                <div>
                  <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {selected ? selected.code || selected.label : i18n("featureFinanceCleanupNoSelection")}
                  </p>
                  <p className="mt-1 text-xs leading-5" style={{ color: "var(--dim)" }}>
                    {i18n("featureFinanceCleanupImpact")}
                  </p>
                </div>
                <label className="block space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {i18n("featureFinanceCleanupReason")}
                  </span>
                  <textarea
                    className="min-h-24 w-full rounded-2xl border px-4 py-3 text-sm outline-none"
                    style={{ background: "var(--bg)", borderColor: "var(--border)", color: "var(--text)" }}
                    value={reason}
                    onChange={(event) => setReason(event.target.value)}
                  />
                </label>
                <label className="block space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {i18n("featureFinanceCleanupPassword")}
                  </span>
                  <input
                    className="w-full rounded-2xl border px-4 py-3 text-sm outline-none"
                    style={{ background: "var(--bg)", borderColor: "var(--border)", color: "var(--text)" }}
                    type="password"
                    value={password}
                    onChange={(event) => setPassword(event.target.value)}
                  />
                </label>
                {errorMessage ? <ErrorNotice>{errorMessage}</ErrorNotice> : null}
                {purgeMutation.isSuccess ? (
                  <p className="text-sm" style={{ color: "var(--success)" }}>{i18n("featureFinanceCleanupSuccess")}</p>
                ) : null}
                <button
                  className="w-full rounded-full px-4 py-3 text-sm font-semibold disabled:opacity-50"
                  disabled={!canPurge}
                  style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
                  type="button"
                  onClick={() => purgeMutation.mutate()}
                >
                  {purgeMutation.isPending ? i18n("featureFinanceCleanupPending") : i18n("featureFinanceCleanupSubmit")}
                </button>
              </div>
            </div>
        </Dialog>
      ) : null}
    </div>
  );
}

function formatCleanupAmount(record: FinanceCleanupRecord) {
  const cents = typeof record.amount_cents === "number" ? record.amount_cents : 0;
  const currency = record.currency || "EUR";
  return new Intl.NumberFormat("el-GR", { style: "currency", currency }).format(cents / 100);
}

// A number setting where null means "no limit" (ADR-097 booking window).
function OptionalLimitField({
  label,
  hint,
  unit,
  noLimitLabel,
  value,
  min,
  max,
  fallback,
  onChange,
  testId,
}: {
  label: string;
  hint: string;
  unit: string;
  noLimitLabel: string;
  value: number | null;
  min: number;
  max: number;
  fallback: number;
  onChange: (value: number | null) => void;
  testId?: string;
}) {
  return (
    <div className="text-sm font-semibold" data-testid={testId}>
      <span>{label}</span>
      <div className="mt-2 flex flex-wrap items-center gap-3">
        <label className="flex items-center gap-2 text-sm font-normal" style={{ color: "var(--muted)" }}>
          <IntegerInput aria-label={label} data-testid={testId ? `${testId}-value` : undefined} disabled={value === null} min={min} max={max} emptyValue={min} className="w-24 rounded-xl px-3 py-3 disabled:opacity-40" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }} value={value} onValueChange={(next) => onChange(next ?? min)} />
          {unit}
        </label>
        <label className="flex items-center gap-2 text-sm font-normal" style={{ color: "var(--muted)" }}>
          <input type="checkbox" data-testid={testId ? `${testId}-no-limit` : undefined} checked={value === null} onChange={(event) => onChange(event.target.checked ? null : fallback)} />
          {noLimitLabel}
        </label>
      </div>
      <p className="mt-1 text-xs font-normal" style={{ color: "var(--dim)" }}>{hint}</p>
    </div>
  );
}

type SchedulingForm = {
  capacity: number;
  /** ADR-226: null = a request waits for approval until the class starts. */
  timeout: number | null;
  autoApprove: boolean;
  windowDays: number | null;
  /** ADR-226: minutes before the class; null = cancelling is always free. */
  cutoffMinutes: number | null;
};

function schedulingFormFromSettings(value: SchedulingSettings): SchedulingForm {
  return {
    capacity: value.default_capacity,
    timeout: value.default_booking_timeout_minutes ?? null,
    autoApprove: value.default_auto_approve,
    windowDays: value.default_booking_window_days ?? null,
    cutoffMinutes: value.default_cancellation_cutoff_minutes ?? null,
  };
}

export function SchedulingDefaultsSection({ token, part = "basic" }: { token: string; part?: Part }) {
  const rules = useTranslations("BookingRules");
  const show = partShows(useSettingLevels(), part);
  const queryClient = useQueryClient();
  const settingsQuery = useQuery({ queryKey: ["admin", "settings"], queryFn: () => fetchAdminSettings(token) });
  const [form, setForm] = useState<SchedulingForm>({ capacity: 12, timeout: 60, autoApprove: false, windowDays: null, cutoffMinutes: null });

  const lastServer = useRef<SchedulingForm | null>(null);
  useEffect(() => {
    const value = settingsQuery.data?.scheduling;
    if (value) {
      const next = schedulingFormFromSettings(value);
      queueMicrotask(() => {
        const previous = lastServer.current;
        setForm((current) => mergeServerForm(current, previous, next));
        lastServer.current = next;
      });
    }
  }, [settingsQuery.data?.scheduling]);

  // Each part saves only the settings it shows.
  const save = useMutation({
    mutationFn: () => updateAdminSettings(token, { scheduling: {
      ...(show("scheduling.default_capacity") ? { default_capacity: form.capacity } : {}),
      ...(show("scheduling.default_booking_timeout_minutes") ? { default_booking_timeout_minutes: form.timeout } : {}),
      ...(show("scheduling.default_auto_approve") ? { default_auto_approve: form.autoApprove } : {}),
      ...(show("scheduling.default_booking_window_days") ? { default_booking_window_days: form.windowDays } : {}),
      ...(show("scheduling.default_cancellation_cutoff_minutes") ? { default_cancellation_cutoff_minutes: form.cutoffMinutes } : {}),
    } }),
    onSuccess: (data) => queryClient.setQueryData(["admin", "settings"], data),
  });
  const current: SchedulingSettings | undefined = settingsQuery.data?.scheduling;
  const saved = current ? schedulingFormFromSettings(current) : null;
  const dirty = Boolean(saved) && (Object.keys(form) as Array<keyof SchedulingForm>).some((key) => form[key] !== saved![key]);

  // ADR-226: every rule says what it does, for whom, and what "no limit" means.
  // The approval wait means nothing while bookings are confirmed automatically (audit §C).
  const showTimeout = show("scheduling.default_booking_timeout_minutes") && !form.autoApprove;
  return <div className="grid max-w-3xl gap-5 sm:grid-cols-2" data-testid={part === "basic" ? "class-booking-defaults" : "class-booking-defaults-advanced"}>
    {show("scheduling.default_capacity") ? <div className="text-sm font-semibold">
      <label htmlFor="class-default-capacity">{rules("capacityLabel")}</label>
      <IntegerInput id="class-default-capacity" data-testid="class-default-capacity" min={1} max={500} emptyValue={1} className="mt-2 w-full rounded-xl px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }} value={form.capacity} onValueChange={(capacity) => setForm({ ...form, capacity: capacity ?? 1 })} />
      <p className="mt-1 text-xs font-normal" style={{ color: "var(--dim)" }}>{rules("capacityHelp")}</p>
    </div> : null}
    {show("scheduling.default_auto_approve") ? <div className="text-sm font-semibold">
      <label className="flex items-center gap-3"><input type="checkbox" data-testid="class-default-auto-approve" checked={form.autoApprove} onChange={(event) => setForm({ ...form, autoApprove: event.target.checked })} />{rules("autoApproveLabel")}</label>
      <p className="mt-1 text-xs font-normal" style={{ color: "var(--dim)" }}>{rules("autoApproveHelp")}</p>
    </div> : null}
    {showTimeout ? <DurationLimitField testId="class-default-approval-wait" label={rules("approvalWaitLabel")} help={rules("approvalWaitHelp")} noLimitLabel={rules("approvalWaitNoLimit")} value={form.timeout} min={1} max={10080} fallback={60} onChange={(timeout) => setForm({ ...form, timeout })} /> : null}
    {show("scheduling.default_booking_window_days") ? <OptionalLimitField testId="class-default-booking-window" label={rules("bookingWindowLabel")} hint={rules("bookingWindowHelp")} unit={rules("days")} noLimitLabel={rules("noLimit")} value={form.windowDays} min={1} max={365} fallback={14} onChange={(windowDays) => setForm({ ...form, windowDays })} /> : null}
    {show("scheduling.default_cancellation_cutoff_minutes") ? <DurationLimitField testId="class-default-late-cancellation" label={rules("lateCancellationLabel")} help={rules("lateCancellationHelp")} noLimitLabel={rules("noLimit")} value={form.cutoffMinutes} min={0} max={10080} fallback={720} onChange={(cutoffMinutes) => setForm({ ...form, cutoffMinutes })} /> : null}
    <div className="sm:col-span-2"><SaveBar dirty={dirty} pending={save.isPending} success={save.isSuccess} error={save.error} onSave={() => save.mutate()} onReset={() => saved && setForm(saved)} /></div>
  </div>;
}

function ProviderKindSection({ token }: { token: string }) {
  const t = useTranslations("Providers");
  return (
    <CollapsibleSection id="provider-kind" title={t("kindSetting.title")} description={t("kindSetting.description")}>
      <ProviderKindSetting token={token} />
    </CollapsibleSection>
  );
}

// ADR-275: the workout kinds the gym's WOD editors offer.
function WorkoutTypesSection({ token }: { token: string }) {
  const t = useTranslations("WorkoutTypes");
  return (
    <CollapsibleSection id="workout-types" title={t("setting.title")} description={t("setting.description")} defaultOpen={false}>
      <WorkoutTypesSetting token={token} />
    </CollapsibleSection>
  );
}

// ADR-170: the organization's Palee plan (owners and admins).
function PlanSection({ token }: { token: string }) {
  const t = useTranslations("SoloCoach");
  return (
    <CollapsibleSection id="plan" title={t("plan.title")} description={t("plan.description")} defaultOpen={false}>
      <PlanCard token={token} />
    </CollapsibleSection>
  );
}


export function AdminSettingsHub() {
  const i18n = useUiTranslations();
  const paymentsT = useTranslations("OnlinePayments");
  const adv = useTranslations("AdvancedSettings");
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token;
  const { membership, selectedOrganizationSlug } = useSelectedMembershipRole();
  const levels = useSettingLevels();
  const settingsQuery = useQuery({
    queryKey: ["admin", "settings"],
    queryFn: () => fetchAdminSettings(token!),
    enabled: Boolean(token),
  });

  // ADR-186: a branch manager edits their own branches, not the business.
  if (membership && !can(membership, "manage_settings") && can(membership, "manage_locations")) {
    return (
      <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
        <div className="mx-auto max-w-5xl space-y-6">
          <PageHeader title={i18n("appConfigurationse0effaa")} />
          {token ? (
            <CollapsibleSection id="locations" title={i18n("admLocationsTitle")} description={i18n("admLocationsDescription")}>
              <LocationSettings token={token} />
              <div className="mt-3">
                <SpacesSettingsLink />
              </div>
              <div className="mt-3">
                <BoxScreensSettingsLink />
              </div>
            </CollapsibleSection>
          ) : (
            <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
          )}
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-5xl space-y-6">

        <PageHeader title={i18n("appConfigurationse0effaa")} />
        <AdminOnboardingPanel />
        <ClientAccessPanel />
        {token ? <PlanNotice token={token} /> : null}

        {token ? (
          <>
            <PlanSection token={token} />

            {/* ADR-176: the zone every gym-local rule reads. Derived (ADR-255): asked only until it is confirmed. */}
            {settingsQuery.data?.time_zone && !settingsQuery.data.time_zone.confirmed ? (
              <CollapsibleSection
                id="time-zone"
                title={i18n("gymTimeZoneTitle")}
                description={i18n("gymTimeZoneDescription")}
              >
                <GymTimeZoneSetting token={token} />
              </CollapsibleSection>
            ) : null}

            <CollapsibleSection
              id="branding"
              title={i18n("brandingSectionTitle")}
              description={i18n("brandingSectionDescription")}
            >
              <BrandingSection token={token} />
            </CollapsibleSection>

            {levels.basic("provider.kind") ? <ProviderKindSection token={token} /> : null}

            {levels.basic("gamification.leaderboard_enabled") ? (
              <CollapsibleSection
                id="gamification"
                title={i18n("gamificatione32e404")}
                description={i18n("streaksStreakShieldsLeaderboardaa8cd0c")}
              >
                <GamificationSection token={token} />
              </CollapsibleSection>
            ) : null}

            {/* Mockup s3 B (ADR-246/260/261): the provider sends the owner back to ?tab=payments. */}
            {can(membership, "manage_billing") ? (
              <CollapsibleSection id="payments" title={paymentsT("sectionTitle")} description={paymentsT("sectionDescription")}>
                <Suspense>
                  <OnlinePaymentsSettings token={token} />
                </Suspense>
              </CollapsibleSection>
            ) : null}

            <CollapsibleSection
              id="finance"
              title={i18n("finance1b48d3f")}
              description={i18n("paymentReminders64c6e44")}
            >
              {/* Mockup s1 (ADR-240): the business's billing details. */}
              <div className="mb-3">
                <FiscalIdentityLink />
              </div>
              <FinanceSection token={token} />
            </CollapsibleSection>

            <CollapsibleSection
              id="class-types"
              title={i18n("classTypes9704233")}
              description={i18n("scheduleClassificationAndFiltersc6f2df8")}
            >
              <ClassTypeSettings token={token} />
            </CollapsibleSection>

            <WorkoutTypesSection token={token} />

            {/* Every box, one branch or many: Οθόνες box used to live only under Παραρτήματα, which a single-branch owner never opens. */}
            <CollapsibleSection id="on-site" title={i18n("admOnSiteTitle")} description={i18n("admOnSiteDescription")}>
              <BoxScreensSettingsLink />
              <div className="mt-3">
                <CheckInSettingsLink />
              </div>
            </CollapsibleSection>

            <CollapsibleSection id="public-page" title={i18n("admPublicPageTitle")} description={i18n("admPublicPageDescription")}>
              <PublicPageLink />
              <div className="mt-3">
                <TrialsLink />
              </div>
            </CollapsibleSection>

            <CollapsibleSection
              id="locations"
              title={i18n("admLocationsTitle")}
              description={i18n("admLocationsDescription")}
              defaultOpen={false}
            >
              <LocationSettings token={token} />
              <div className="mt-3">
                <SpacesSettingsLink />
              </div>
              <div className="mt-3">
                <BoxScreensSettingsLink />
              </div>
            </CollapsibleSection>

            <CollapsibleSection
              id="class-defaults"
              title={i18n("featureClassCreationDefaults")}
              description={i18n("featureClassDefaultsDescription")}
            >
              <SchedulingDefaultsSection token={token} />
            </CollapsibleSection>

            {can(membership, "manage_organization_lifecycle") ? (
              <CollapsibleSection
                id="organization"
                title={i18n("orgSettingsTitle")}
                description={i18n("orgSettingsDescription")}
                defaultOpen={false}
              >
                <OrganizationOwnerSettings token={token} slug={selectedOrganizationSlug} currentUserId={currentUser?.id} />
              </CollapsibleSection>
            ) : null}

            <AdvancedSettingsCard
              count={levels.advancedCount}
              groups={[
                {
                  id: "bookings",
                  title: adv("groups.bookings"),
                  keywords: [adv("keywords.bookings"), i18n("featureClassCreationDefaults")],
                  content: (
                    <>
                      <SchedulingDefaultsSection token={token} part="advanced" />
                      <CheckInSettingsLink />
                    </>
                  ),
                },
                {
                  id: "payments",
                  title: adv("groups.payments"),
                  keywords: [adv("keywords.payments"), i18n("subscriptionGraceDays"), i18n("subscriptionExpiryReminderDays"), i18n("reminderIntervalDaysee3ba34")],
                  content: <FinanceSection token={token} part="advanced" />,
                },
                {
                  id: "motivation",
                  title: adv("groups.motivation"),
                  keywords: [adv("keywords.motivation"), i18n("streakShieldResetDayd22b9ea"), i18n("levelTaxonomyd6fdd60")],
                  content: (
                    <>
                      <GamificationSection token={token} part="advanced" />
                      <div id="level-taxonomy">
                        <p className="mb-2 text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("levelTaxonomyd6fdd60")}</p>
                        <LevelTaxonomySection token={token} />
                      </div>
                    </>
                  ),
                },
                {
                  id: "training",
                  title: adv("groups.training"),
                  keywords: [adv("keywords.training")],
                  content: (
                    <>
                      <WodGoalsDefaultSetting token={token} />
                      {can(membership, "manage_settings") ? (
                        <>
                          <WodAssistantSetting token={token} />
                          <AiScalingSettings token={token} />
                        </>
                      ) : null}
                    </>
                  ),
                },
                {
                  id: "community",
                  title: adv("groups.community"),
                  keywords: [adv("keywords.community")],
                  content: <CommunitySettingsLink />,
                },
                {
                  id: "on-site",
                  title: adv("groups.onSite"),
                  keywords: [adv("keywords.onSite"), i18n("admOnSiteDescription")],
                  content: <BoxScreensSettingsLink />,
                },
                ...(can(membership, "grant_staff_roles")
                  ? [
                      {
                        id: "role-access",
                        title: i18n("roleAccessTitle"),
                        keywords: [adv("keywords.access"), i18n("roleAccessDescription")],
                        content: <RoleAccessSettings token={token} />,
                      },
                    ]
                  : []),
              ]}
            />
          </>
        ) : (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
        )}

      </div>
    </main>
  );
}
