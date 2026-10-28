"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useTranslations } from "next-intl";
import { localizeError } from "@/i18n/presentation";
import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  fetchAdminSettings,
  updateAdminSettings,
  type FinanceSettings,
  type GamificationSettings,
  type NotificationPushSettings,
  type SchedulingSettings,
} from "@/api/settings";
import {
  fetchFinanceCleanupRecords,
  purgeFinanceRecord,
  type FinanceCleanupRecord,
} from "@/api/finance";
import { listScaleLevels, replaceScaleLevels, type ScaleLevel } from "@/api/workouts";
import { adminLogoApi, fetchAdminBranding } from "@/api/organization-branding";
import { TenantLogoUploader } from "@/components/branding/TenantLogoUploader";
import { useSession } from "@/components/session-provider";
import { ClassTypeSettings } from "@/components/admin/ClassTypeSettings";
import { LocationSettings } from "@/components/admin/LocationSettings";
import { PublicPageLink } from "@/components/admin/public-page/PublicPageLink";
import { TrialsLink } from "@/components/admin/trials/TrialsLink";
import { CommunitySettingsLink } from "@/components/admin/community/CommunitySettings";
import { CheckInSettingsLink } from "@/components/check-in/CheckInSettings";
import { SpacesSettingsLink } from "@/components/spaces/SpacesSettings";
import { RoleAccessSettings } from "@/components/admin/RoleAccessSettings";
import { OrganizationOwnerSettings } from "@/components/admin/OrganizationOwnerSettings";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";
import { IntegerInput } from "@/components/integer-input";
import { PageHeader } from "@/components/PageHeader";
import { ClientAccessPanel } from "@/components/invites/InviteClients";
import { AdminOnboardingPanel } from "@/components/onboarding/Onboarding";
import { GymTimeZoneSetting } from "@/components/admin/GymTimeZoneSetting";
import { ProviderKindSetting } from "@/components/providers/ProviderKindSetting";
import { WodGoalsDefaultSetting } from "@/components/wod-goals/WodGoalsDefaultSetting";
import { WodAssistantSetting } from "@/components/workouts/creation/WodAssistantSetting";
import { AiScalingSettings } from "@/components/scaling/AiScalingSettings";
import { PlanCard, PlanNotice } from "@/components/solo-coach/PlanCard";
import { Dialog } from "@/components/ui/Dialog";
import { Popover } from "@/components/ui/Popover";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

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

// ADR-222: the box sets only the streak shields and when they renew; the
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

function GamificationSection({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const t = useTranslations("TrainingGoal");
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

  useEffect(() => {
    if (!settingsQuery.data?.gamification) return;
    const next = formFromSettings(settingsQuery.data.gamification);
    queueMicrotask(() => { setForm(next); setInitialized(true); });
  }, [settingsQuery.data]);

  const saveMutation = useMutation({
    mutationFn: () =>
      updateAdminSettings(token, {
        gamification: {
          streak_shields: Number(form.streakShields),
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
      <p className="rounded-[1.4rem] px-4 py-3 text-sm leading-6" style={{ background: "var(--panel-muted)", color: "var(--muted)" }} data-testid="weekly-goal-is-personal">
        {t("box.goalIsPersonal")}
      </p>

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

function FinanceSection({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
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
          onChange={(e) => setForm((current) => ({ ...current, paymentReminderIntervalDays: e.target.value }))}
          className="w-28 rounded-xl px-4 py-2.5 text-sm outline-none"
          style={{
            background: "var(--panel-muted)",
            border: "1px solid var(--border)",
            color: "var(--text)",
          }}
        />
      </div>
      <DaysField
        id="expiry-reminder-days"
        label={i18n("subscriptionExpiryReminderDays")}
        help={i18n("subscriptionExpiryReminderDaysHelp")}
        min={0}
        value={form.expiryReminderDays}
        onChange={(value) => setForm((current) => ({ ...current, expiryReminderDays: value }))}
      />
      <DaysField
        id="grace-days"
        label={i18n("subscriptionGraceDays")}
        help={i18n("subscriptionGraceDaysHelp")}
        min={0}
        value={form.graceDays}
        onChange={(value) => setForm((current) => ({ ...current, graceDays: value }))}
      />
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
      <SaveBar
        dirty={dirty}
        pending={saveMutation.isPending}
        success={saveMutation.isSuccess}
        error={saveMutation.error}
        onSave={() => saveMutation.mutate()}
        onReset={() => setForm(serverForm ?? { paymentReminderIntervalDays: serverDays, expiryReminderDays: "5", graceDays: "3", documentMode: serverMode, packageModules: serverModules.split(",") })}
      />

      <FinanceCleanupSection token={token} />
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

// A number setting where null means "no limit" (ADR-097 booking window and cancellation cutoff).
function OptionalLimitField({
  label,
  hint,
  value,
  min,
  max,
  fallback,
  onChange,
}: {
  label: string;
  hint: string;
  value: number | null;
  min: number;
  max: number;
  fallback: number;
  onChange: (value: number | null) => void;
}) {
  const i18n = useUiTranslations();
  return (
    <div className="text-sm font-semibold">
      <span>{label}</span>
      <div className="mt-2 flex items-center gap-3">
        <IntegerInput aria-label={label} disabled={value === null} min={min} max={max} emptyValue={min} className="w-28 rounded-xl px-4 py-3 disabled:opacity-40" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }} value={value} onValueChange={(next) => onChange(next ?? min)} />
        <label className="flex items-center gap-2 text-sm font-normal" style={{ color: "var(--muted)" }}>
          <input type="checkbox" checked={value === null} onChange={(event) => onChange(event.target.checked ? null : fallback)} />
          {i18n("admNoLimit")}
        </label>
      </div>
      <p className="mt-1 text-xs font-normal" style={{ color: "var(--dim)" }}>{hint}</p>
    </div>
  );
}

type SchedulingForm = {
  capacity: number;
  timeout: number;
  autoApprove: boolean;
  windowDays: number | null;
  cutoffHours: number | null;
};

function schedulingFormFromSettings(value: SchedulingSettings): SchedulingForm {
  return {
    capacity: value.default_capacity,
    timeout: value.default_booking_timeout_minutes,
    autoApprove: value.default_auto_approve,
    windowDays: value.default_booking_window_days ?? null,
    cutoffHours: value.default_cancellation_cutoff_hours ?? null,
  };
}

function SchedulingDefaultsSection({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const settingsQuery = useQuery({ queryKey: ["admin", "settings"], queryFn: () => fetchAdminSettings(token) });
  const [form, setForm] = useState<SchedulingForm>({ capacity: 12, timeout: 60, autoApprove: false, windowDays: null, cutoffHours: null });

  useEffect(() => {
    const value = settingsQuery.data?.scheduling;
    if (value) {
      queueMicrotask(() => setForm(schedulingFormFromSettings(value)));
    }
  }, [settingsQuery.data?.scheduling]);

  const save = useMutation({
    mutationFn: () => updateAdminSettings(token, { scheduling: {
      default_capacity: form.capacity,
      default_booking_timeout_minutes: form.timeout,
      default_auto_approve: form.autoApprove,
      default_booking_window_days: form.windowDays,
      default_cancellation_cutoff_hours: form.cutoffHours,
    } }),
    onSuccess: (data) => queryClient.setQueryData(["admin", "settings"], data),
  });
  const current: SchedulingSettings | undefined = settingsQuery.data?.scheduling;
  const saved = current ? schedulingFormFromSettings(current) : null;
  const dirty = Boolean(saved) && (Object.keys(form) as Array<keyof SchedulingForm>).some((key) => form[key] !== saved![key]);

  return <div className="grid max-w-3xl gap-4 sm:grid-cols-2">
    <label className="text-sm font-semibold">{i18n("featureDefaultClassCapacity")}<IntegerInput min={1} max={500} emptyValue={1} className="mt-2 w-full rounded-xl px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }} value={form.capacity} onValueChange={(capacity) => setForm({ ...form, capacity: capacity ?? 1 })} /></label>
    <label className="text-sm font-semibold">{i18n("featureDefaultBookingTimeout")}<IntegerInput min={1} max={10080} emptyValue={1} className="mt-2 w-full rounded-xl px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }} value={form.timeout} onValueChange={(timeout) => setForm({ ...form, timeout: timeout ?? 1 })} /></label>
    <OptionalLimitField label={i18n("admBookingWindowDays")} hint={i18n("admBookingWindowHint")} value={form.windowDays} min={1} max={365} fallback={14} onChange={(windowDays) => setForm({ ...form, windowDays })} />
    <OptionalLimitField label={i18n("admCancellationCutoffHours")} hint={i18n("admCancellationCutoffHint")} value={form.cutoffHours} min={0} max={168} fallback={12} onChange={(cutoffHours) => setForm({ ...form, cutoffHours })} />
    <label className="flex items-center gap-3 text-sm font-semibold"><input type="checkbox" checked={form.autoApprove} onChange={(event) => setForm({ ...form, autoApprove: event.target.checked })} />{i18n("featureAutoApproveClassBookings")}</label>
    <div className="sm:col-span-2"><SaveBar dirty={dirty} pending={save.isPending} success={save.isSuccess} error={save.error} onSave={() => save.mutate()} onReset={() => saved && setForm(saved)} /></div>
  </div>;
}

// ── Notifications section ────────────────────────────────────────────────────

type NotificationPushFormState = {
  publicKey: string;
  privateKey: string;
  subject: string;
  clearPrivateKey: boolean;
};

function notificationPushFormFromSettings(s: NotificationPushSettings): NotificationPushFormState {
  return {
    publicKey: s.vapid_public_key ?? "",
    privateKey: "",
    subject: s.vapid_subject ?? "",
    clearPrivateKey: false,
  };
}

function bytesToBase64Url(bytes: ArrayBuffer) {
  const raw = String.fromCharCode(...new Uint8Array(bytes));
  return window.btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function generateVapidKeyPair() {
  const pair = await window.crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: String.fromCharCode(80, 45, 50, 53, 54) },
    true,
    ["deriveBits"],
  );

  const publicKey = await window.crypto.subtle.exportKey("raw", pair.publicKey);
  const privateKey = await window.crypto.subtle.exportKey("jwk", pair.privateKey);

  if (typeof privateKey.d !== "string") {
    throw new Error("vapid_key_export_failed");
  }

  return {
    publicKey: bytesToBase64Url(publicKey),
    privateKey: privateKey.d,
  };
}

function NotificationsSection({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [form, setForm] = useState<NotificationPushFormState>({
    publicKey: "",
    privateKey: "",
    subject: "",
    clearPrivateKey: false,
  });
  const [initialized, setInitialized] = useState(false);
  const [generateError, setGenerateError] = useState<string | null>(null);

  const settingsQuery = useQuery({
    queryKey: ["admin", "settings"],
    queryFn: () => fetchAdminSettings(token),
  });

  useEffect(() => {
    if (!settingsQuery.data?.notifications) return;
    const next = notificationPushFormFromSettings(settingsQuery.data.notifications);
    queueMicrotask(() => { setForm(next); setInitialized(true); });
  }, [settingsQuery.data]);

  const saveMutation = useMutation({
    mutationFn: () => {
      const privateKey = form.privateKey.trim();
      const payload: {
        vapid_public_key: string | null;
        vapid_subject: string | null;
        vapid_private_key?: string | null;
      } = {
        vapid_public_key: form.publicKey.trim() || null,
        vapid_subject: form.subject.trim() || null,
      };

      if (privateKey || form.clearPrivateKey) {
        payload.vapid_private_key = privateKey || null;
      }

      return updateAdminSettings(token, {
        notifications: payload,
      });
    },
    onSuccess: (data) => {
      queryClient.setQueryData(["admin", "settings"], data);
      setForm(notificationPushFormFromSettings(data.notifications));
    },
  });

  const serverForm = settingsQuery.data?.notifications
    ? notificationPushFormFromSettings(settingsQuery.data.notifications)
    : null;
  const dirty =
    initialized &&
    serverForm !== null &&
    (form.publicKey !== serverForm.publicKey ||
      form.subject !== serverForm.subject ||
      form.privateKey.trim() !== "" ||
      form.clearPrivateKey);
  const configured = Boolean(settingsQuery.data?.notifications.enabled);
  const privateKeyConfigured = Boolean(settingsQuery.data?.notifications.vapid_private_key_configured);

  async function handleGenerate() {
    setGenerateError(null);

    try {
      const keyPair = await generateVapidKeyPair();
      setForm((current) => ({
        ...current,
        publicKey: keyPair.publicKey,
        privateKey: keyPair.privateKey,
        clearPrivateKey: false,
      }));
    } catch {
      setGenerateError(i18n("browserCouldNotGeneratePushKeys6c91b0a"));
    }
  }

  return (
    <div className="max-w-3xl space-y-5">
      <div
        className="rounded-[1.4rem] p-4 text-sm"
        style={{
          background: configured
            ? "color-mix(in srgb, var(--success) 10%, var(--panel-muted))"
            : "var(--panel-muted)",
          border: "1px solid var(--border)",
          color: configured ? "var(--success)" : "var(--muted)",
        }}
      >
        {configured ? i18n("browserAlertsAreAvailableForUserOptIn9f7f20d") : i18n("browserAlertsAreNotAvailableYetc3c13bb")}
      </div>

      <div className="flex flex-wrap gap-3">
        <button
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          type="button"
          onClick={() => void handleGenerate()}
        >
          {i18n("generateBrowserAlertKeys3f8d1bf")}
        </button>
        {privateKeyConfigured ? (
          <button
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--panel-muted)", color: "var(--muted)" }}
            type="button"
            onClick={() => setForm((current) => ({ ...current, publicKey: "", privateKey: "", subject: "", clearPrivateKey: true }))}
          >
            {i18n("turnOffBrowserAlerts17b2048")}
          </button>
        ) : null}
      </div>
      {generateError ? <ErrorNotice>{generateError}</ErrorNotice> : null}

      <label className="block space-y-2">
        <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {i18n("contactForBrowserAlertsfc50ab0")}
        </span>
        <input
          className="w-full rounded-2xl border px-4 py-3 text-sm"
          style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
          value={form.subject}
          onChange={(e) => setForm((current) => ({ ...current, subject: e.target.value, clearPrivateKey: false }))}
        />
      </label>

      <label className="block space-y-2">
        <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {i18n("publicBrowserAlertKeyacbc22f")}
        </span>
        <textarea
          className="min-h-24 w-full rounded-2xl border px-4 py-3 font-mono text-xs"
          spellCheck={false}
          style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
          value={form.publicKey}
          onChange={(e) => setForm((current) => ({ ...current, publicKey: e.target.value, clearPrivateKey: false }))}
        />
      </label>

      <label className="block space-y-2">
        <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {privateKeyConfigured ? i18n("replacePrivateBrowserAlertKey2d09431") : i18n("privateBrowserAlertKey09f05b1")}
        </span>
        <textarea
          className="min-h-24 w-full rounded-2xl border px-4 py-3 font-mono text-xs"
          placeholder={privateKeyConfigured ? i18n("leaveBlankToKeepCurrentKeyea85d22") : ""}
          spellCheck={false}
          style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
          value={form.privateKey}
          onChange={(e) => setForm((current) => ({ ...current, privateKey: e.target.value, clearPrivateKey: false }))}
        />
      </label>

      <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>
        {i18n("adminsManageTheSharedBrowserAlertServiceHerec33b6e5")}
      </p>

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

function ProviderKindSection({ token }: { token: string }) {
  const t = useTranslations("Providers");
  return (
    <CollapsibleSection id="provider-kind" title={t("kindSetting.title")} description={t("kindSetting.description")}>
      <ProviderKindSetting token={token} />
    </CollapsibleSection>
  );
}

function AiAssistantSection({ token }: { token: string }) {
  const t = useTranslations("Scaling");
  return (
    <CollapsibleSection id="ai-assistant" title={t("settings.title")} description={t("settings.description")} defaultOpen={false}>
      {/* ADR-180: the WOD assistant runs on the platform's credits, so it needs no key of the gym's. */}
      <div className="mb-5 border-b pb-5" style={{ borderColor: "var(--border)" }}>
        <WodAssistantSetting token={token} />
      </div>
      <AiScalingSettings token={token} />
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

function WorkoutDefaultsSection({ token }: { token: string }) {
  const t = useTranslations("WodGoals");
  return (
    <CollapsibleSection id="workout-defaults" title={t("settings.sectionTitle")} description={t("settings.sectionDescription")}>
      <WodGoalsDefaultSetting token={token} />
    </CollapsibleSection>
  );
}

export function AdminSettingsHub() {
  const i18n = useUiTranslations();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token;
  const { membership, selectedOrganizationSlug } = useSelectedMembershipRole();

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

            {/* ADR-176: the zone every gym-local rule reads. */}
            <CollapsibleSection
              id="time-zone"
              title={i18n("gymTimeZoneTitle")}
              description={i18n("gymTimeZoneDescription")}
            >
              <GymTimeZoneSetting token={token} />
            </CollapsibleSection>

            <CollapsibleSection
              id="branding"
              title={i18n("brandingSectionTitle")}
              description={i18n("brandingSectionDescription")}
            >
              <BrandingSection token={token} />
            </CollapsibleSection>

            <ProviderKindSection token={token} />

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
              id="notifications"
              title={i18n("notificationseee2ef2")}
              description={i18n("browserAlertsAndInAppInboxDeliveryc83f515")}
            >
              <NotificationsSection token={token} />
            </CollapsibleSection>

            <CollapsibleSection
              id="class-types"
              title={i18n("classTypes9704233")}
              description={i18n("scheduleClassificationAndFiltersc6f2df8")}
            >
              <ClassTypeSettings token={token} />
            </CollapsibleSection>

            <CollapsibleSection id="public-page" title={i18n("admPublicPageTitle")} description={i18n("admPublicPageDescription")}>
              <PublicPageLink />
              <div className="mt-3">
                <TrialsLink />
              </div>
              <div className="mt-3">
                <CommunitySettingsLink />
              </div>
              <div className="mt-3">
                <CheckInSettingsLink />
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
            </CollapsibleSection>

            <CollapsibleSection
              id="class-defaults"
              title={i18n("featureClassCreationDefaults")}
              description={i18n("featureClassDefaultsDescription")}
            >
              <SchedulingDefaultsSection token={token} />
            </CollapsibleSection>

            {can(membership, "grant_staff_roles") ? (
              <CollapsibleSection
                id="role-access"
                title={i18n("roleAccessTitle")}
                description={i18n("roleAccessDescription")}
                defaultOpen={false}
              >
                <RoleAccessSettings token={token} />
              </CollapsibleSection>
            ) : null}

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

            <WorkoutDefaultsSection token={token} />

            {can(membership, "manage_settings") ? <AiAssistantSection token={token} /> : null}

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
