"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  fetchAdminSettings,
  updateAdminSettings,
  type FinanceSettings,
  type GamificationSettings,
} from "@/api/settings";
import { listScaleLevels, replaceScaleLevels, type ScaleLevel } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { THEME_UPDATED_EVENT } from "@/components/theme-provider";
import { APP_THEMES, THEME_SLUGS, normalizeThemeSlug, type ThemeSlug } from "@/lib/theme";
import { ClassTypeSettings } from "@/components/admin/ClassTypeSettings";
import { TransientHero } from "@/components/TransientHero";

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
      {msg && <p className="text-sm" style={{ color: "var(--danger)" }}>{msg}</p>}
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
  const ref = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    if (!active) return;
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) onToggle();
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [active, onToggle]);

  return (
    <span ref={ref} className="relative inline-flex shrink-0">
      <button
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
      {active && (
        <span
          className="absolute end-0 top-9 z-50 w-[min(22rem,calc(100vw-3rem))] rounded-2xl shadow-[0_20px_60px_rgba(0,0,0,0.7)]"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)" }}
        >
          <span
            className="absolute -top-[7px] end-2.5 h-3 w-3 rotate-45"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)", borderBottom: "none", borderInlineEnd: "none" }}
          />
          <span className="block space-y-2 p-4 text-start text-xs normal-case leading-5 tracking-normal [&_p]:m-0" style={{ color: "var(--text-soft)" }}>
            {children}
          </span>
        </span>
      )}
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

// ── Appearance section ───────────────────────────────────────────────────────

function AppearanceSection({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [themeSlug, setThemeSlug] = useState<ThemeSlug>("ember");
  const [initialized, setInitialized] = useState(false);

  const settingsQuery = useQuery({
    queryKey: ["admin", "settings"],
    queryFn: () => fetchAdminSettings(token),
  });

  useEffect(() => {
    if (!settingsQuery.data?.gamification) return;
    const slug = normalizeThemeSlug(settingsQuery.data.gamification.theme_slug);
    queueMicrotask(() => { setThemeSlug(slug); setInitialized(true); });
  }, [settingsQuery.data]);

  const saveMutation = useMutation({
    mutationFn: () => updateAdminSettings(token, { gamification: { theme_slug: themeSlug } }),
    onSuccess: (data) => {
      queryClient.setQueryData(["admin", "settings"], data);
      window.dispatchEvent(
        new CustomEvent(THEME_UPDATED_EVENT, { detail: { theme_slug: data.gamification.theme_slug } }),
      );
    },
  });

  const serverSlug = settingsQuery.data?.gamification
    ? normalizeThemeSlug(settingsQuery.data.gamification.theme_slug)
    : "ember";
  const dirty = initialized && themeSlug !== serverSlug;

  return (
    <div className="space-y-4">
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {THEME_SLUGS.map((slug) => {
          const theme = APP_THEMES[slug];
          const selected = themeSlug === slug;
          return (
            <button
              key={slug}
              type="button"
              className="rounded-[1.2rem] border p-4 text-start transition-colors"
              style={{
                background: selected
                  ? "color-mix(in srgb, var(--primary) 12%, var(--panel-muted))"
                  : "var(--panel-muted)",
                borderColor: selected ? "var(--primary)" : "var(--border)",
              }}
              onClick={() => setThemeSlug(slug)}
            >
              <span className="mb-3 flex gap-1.5">
                {[theme.colors.primary, theme.colors.success, theme.colors.warning, theme.colors.danger].map((color) => (
                  <span
                    key={color}
                    className="h-4 w-4 rounded-full"
                    style={{ background: color, border: "1px solid color-mix(in srgb, var(--bg) 20%, transparent)" }}
                  />
                ))}
              </span>
              <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n(theme.label)}</span>
              <span className="mt-1 block text-xs leading-5" style={{ color: "var(--muted)" }}>{i18n(theme.description)}</span>
            </button>
          );
        })}
      </div>
      <SaveBar
        dirty={dirty}
        pending={saveMutation.isPending}
        success={saveMutation.isSuccess}
        error={saveMutation.error}
        onSave={() => saveMutation.mutate()}
        onReset={() => setThemeSlug(serverSlug)}
      />
    </div>
  );
}

// ── Gamification section ─────────────────────────────────────────────────────

type GamificationFormState = {
  weeklyWorkoutTarget: string;
  streakShieldResetDay: string;
  leaderboardEnabled: boolean;
};

function formFromSettings(s: GamificationSettings): GamificationFormState {
  return {
    weeklyWorkoutTarget: String(s.weekly_workout_target),
    streakShieldResetDay: s.streak_shield_reset_day ? String(s.streak_shield_reset_day) : "",
    leaderboardEnabled: s.leaderboard_enabled,
  };
}

function GamificationSection({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [form, setForm] = useState<GamificationFormState>({
    weeklyWorkoutTarget: "2",
    streakShieldResetDay: "",
    leaderboardEnabled: true,
  });
  const [initialized, setInitialized] = useState(false);
  const [activeHelp, setActiveHelp] = useState<string | null>(null);

  const settingsQuery = useQuery({
    queryKey: ["admin", "settings"],
    queryFn: () => fetchAdminSettings(token),
  });

  useEffect(() => {
    if (!settingsQuery.data?.gamification) return;
    const next = formFromSettings(settingsQuery.data.gamification);
    queueMicrotask(() => { setForm(next); setInitialized(true); });
  }, [settingsQuery.data]);

  const saveMutation = useMutation({
    mutationFn: () =>
      updateAdminSettings(token, {
        gamification: {
          weekly_workout_target: Number(form.weeklyWorkoutTarget),
          streak_shield_reset_day: form.streakShieldResetDay.trim() ? Number(form.streakShieldResetDay) : null,
          leaderboard_enabled: form.leaderboardEnabled,
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
      <label className="relative block space-y-2 rounded-[1.4rem] p-3">
        <span className="flex items-center justify-between gap-3">
          <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {i18n("weeklyWorkoutTarget8106ea7")}
          </span>
          <FieldInfo
            active={activeHelp === "weekly"}
            label={i18n("weeklyWorkoutTargetInfo19b03c8")}
            onToggle={() => setActiveHelp(activeHelp === "weekly" ? null : "weekly")}
          >
            <p>{i18n("howManyCompletedWorkoutsAUserNeedsPere99943b")}</p>
            <p>{i18n("validValuesInteger1Default281502ef")}</p>
          </FieldInfo>
        </span>
        <input
          className="w-full rounded-2xl border px-4 py-3 text-sm"
          inputMode="numeric"
          min={1}
          type="number"
          style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
          value={form.weeklyWorkoutTarget}
          onChange={(e) => update("weeklyWorkoutTarget", e.target.value)}
        />
      </label>

      <label className="relative block space-y-2 rounded-[1.4rem] p-3">
        <span className="flex items-center justify-between gap-3">
          <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {i18n("streakShieldResetDayd22b9ea")}
          </span>
          <FieldInfo
            active={activeHelp === "shield"}
            label={i18n("streakShieldResetDayInfo10555c2")}
            onToggle={() => setActiveHelp(activeHelp === "shield" ? null : "shield")}
          >
            <p>{i18n("dayOfMonthWhenEachUserGetsTheir605b967")}</p>
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
          onChange={(e) => update("streakShieldResetDay", e.target.value)}
        />
      </label>

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

function LevelTaxonomySection({ token }: { token: string }) {
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

  const saveMutation = useMutation({
    mutationFn: () =>
      replaceScaleLevels(token, {
        scale_levels: levels.map((l, i) => ({ slug: l.slug, label: l.label, sort_order: i + 1 })),
      }),
    onSuccess: (updated) => {
      setLevels(updated);
      queryClient.setQueryData(["admin", "scale-levels"], updated);
    },
  });

  const serverLevels = levelsQuery.data ?? [];
  const dirty = initialized && JSON.stringify(levels) !== JSON.stringify(serverLevels);

  return (
    <div className="space-y-4">
      {levelsQuery.isLoading && (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
      )}

      <div className="space-y-3">
        {levels.map((level, index) => (
          <div
            key={level.id ?? level.slug ?? index}
            className="grid gap-3 rounded-[1.4rem] p-4 md:grid-cols-[0.8fr_1fr_auto]"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <input
              className="rounded-2xl px-4 py-3 text-sm outline-none"
              placeholder={i18n("slug6300777")}
              style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={level.slug}
              onChange={(e) =>
                setLevels((cur) =>
                  cur.map((item, i) => (i === index ? { ...item, slug: e.target.value } : item)),
                )
              }
            />
            <input
              className="rounded-2xl px-4 py-3 text-sm outline-none"
              placeholder={i18n("displayLabeld747868")}
              style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={level.label}
              onChange={(e) =>
                setLevels((cur) =>
                  cur.map((item, i) => (i === index ? { ...item, label: e.target.value } : item)),
                )
              }
            />
            <button
              className="rounded-full px-4 py-2 text-sm transition-colors"
              style={{ background: "var(--panel)", color: "var(--muted)" }}
              type="button"
              onClick={() =>
                setLevels((cur) => (cur.length === 1 ? cur : cur.filter((_, i) => i !== index)))
              }
            >
              {i18n("removee963907")}
            </button>
          </div>
        ))}
      </div>

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

      <SaveBar
        dirty={dirty}
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
  return { paymentReminderIntervalDays: String(s.payment_reminder_interval_days) };
}

function FinanceSection({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [form, setForm] = useState({ paymentReminderIntervalDays: "7" });
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
        },
      }),
    onSuccess: (data) => {
      queryClient.setQueryData(["admin", "settings"], data);
    },
  });

  const serverDays = settingsQuery.data?.finance
    ? String(settingsQuery.data.finance.payment_reminder_interval_days)
    : "7";
  const dirty = initialized && form.paymentReminderIntervalDays !== serverDays;

  return (
    <div className="space-y-5">
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
          onChange={(e) => setForm({ paymentReminderIntervalDays: e.target.value })}
          className="w-28 rounded-xl px-4 py-2.5 text-sm outline-none"
          style={{
            background: "var(--panel-muted)",
            border: "1px solid var(--border)",
            color: "var(--text)",
          }}
        />
      </div>
      <SaveBar
        dirty={dirty}
        pending={saveMutation.isPending}
        success={saveMutation.isSuccess}
        error={saveMutation.error}
        onSave={() => saveMutation.mutate()}
        onReset={() => setForm({ paymentReminderIntervalDays: serverDays })}
      />
    </div>
  );
}

export function AdminSettingsHub() {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token;

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-5xl space-y-6">

        <TransientHero label={i18n("applicationSettingsIntroduction8f2e9b7")} timeoutMs={3000}>
        <section className="rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>
            {i18n("appConfigurationse0effaa")}
          </p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight md:text-4xl" style={{ color: "var(--text)" }}>
            {i18n("appConfigurations1e15749")}
          </h1>
          <p className="mt-2 max-w-3xl text-sm leading-6" style={{ color: "var(--muted)" }}>
            {i18n("globalSettingsForAppearanceEngagementRulesAndWorkout915168c")}
          </p>
        </section>
        </TransientHero>

        {token ? (
          <>
            <CollapsibleSection
              id="appearance"
              title={i18n("appearance41def7a")}
              description={i18n("appColourPalette9dc5de5")}
            >
              <AppearanceSection token={token} />
            </CollapsibleSection>

            <CollapsibleSection
              id="gamification"
              title={i18n("gamificatione32e404")}
              description={i18n("streaksStreakShieldsLeaderboardaa8cd0c")}
            >
              <GamificationSection token={token} />
            </CollapsibleSection>

            <CollapsibleSection
              id="finance"
              title={i18n("finance1b48d3f")}
              description={i18n("paymentReminders64c6e44")}
            >
              <FinanceSection token={token} />
            </CollapsibleSection>

            <CollapsibleSection
              id="class-types"
              title={i18n("classTypes9704233")}
              description={i18n("scheduleClassificationAndFiltersc6f2df8")}
            >
              <ClassTypeSettings token={token} />
            </CollapsibleSection>

            <CollapsibleSection
              id="level-taxonomy"
              title={i18n("levelTaxonomyd6fdd60")}
              description={i18n("globalWorkoutLevelDefinitionsInheritedByAllWorkoutsd5fbba7")}
            >
              <LevelTaxonomySection token={token} />
            </CollapsibleSection>
          </>
        ) : (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
        )}

      </div>
    </main>
  );
}
