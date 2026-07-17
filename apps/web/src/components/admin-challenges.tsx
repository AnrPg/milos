"use client";







import {useUiTranslations} from "@/i18n/ui";
import { localizeError, semanticLabel } from "@/i18n/presentation";
import {useUiLocale} from "@/i18n/use-ui-locale";
import { useMemo, useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";

import {
  createAdminChallenge,
  fetchAdminChallenge,
  fetchAdminChallenges,
  updateAdminChallenge,
  type AdminChallengeRecord,
  type SaveChallengePayload,
} from "@/api/challenges";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";
import { SemanticLabel } from "@/components/semantic-label";
import { addLocalDays, formatLocalDate } from "@/lib/local-date";
import { HelpTooltip } from "@/components/HelpTooltip";

type CriteriaType = SaveChallengePayload["criteria_type"];

type RuleCondition =
  | "workout_type"
  | "scale_level"
  | "pr_beaten"
  | "weekly_consistency"
  | "rare_workout_type"
  | "team_workout_streak";

type RuleFormRow = {
  id: string;
  condition: RuleCondition;
  type: string;
  slug: string;
  threshold: string;
  threshold_pct: string;
  min_count: string;
  points: string;
  label: string;
};

function defaultRuleRow(): RuleFormRow {
  return {
    id: Math.random().toString(36).slice(2),
    condition: "pr_beaten",
    type: "crossfit",
    slug: "rx",
    threshold: "50",
    threshold_pct: "10",
    min_count: "2",
    points: "1",
    label: "",
  };
}

type ChallengeFormState = {
  title: string;
  description: string;
  criteriaType: CriteriaType;
  targetCount: string;
  typeFilter: string;
  incrementPerCompletion: string;
  incrementLabel: string;
  rules: RuleFormRow[];
  badgeLabel: string;
  startsAt: string;
  endsAt: string;
};

const TRAINING_TYPES = ["crossfit", "strength", "gymnastics", "aerobics", "flexibility", "recovery"] as const;

function slugify(value: string) {
  return value
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function emptyForm(): ChallengeFormState {
  return {
    title: "",
    description: "",
    criteriaType: "workout_count",
    targetCount: "2",
    typeFilter: "crossfit",
    incrementPerCompletion: "1",
    incrementLabel: "",
    rules: [],
    badgeLabel: "",
    startsAt: formatLocalDate(new Date()),
    endsAt: formatLocalDate(addLocalDays(new Date(), 7)),
  };
}

function challengeStatus(challenge: Pick<AdminChallengeRecord, "starts_at" | "ends_at">) {
  const today = formatLocalDate(new Date());

  if (challenge.starts_at > today) return "upcoming";
  if (challenge.ends_at < today) return "ended";
  return "active";
}

function payloadFromForm(form: ChallengeFormState): SaveChallengePayload {
  const count = Number(form.targetCount || 0);

  let criteria_value: Record<string, unknown>;
  if (form.criteriaType === "workout_type_count") {
    criteria_value = { count, type_filter: form.typeFilter };
  } else if (form.criteriaType === "custom") {
    if (form.rules.length > 0) {
      criteria_value = {
        count,
        rules: form.rules.map((r) => {
          const base: Record<string, unknown> = {
            condition: r.condition,
            points: Number(r.points || 1),
          };
          if (r.label.trim()) base.label = r.label.trim();
          if (r.condition === "workout_type") base.type = r.type;
          if (r.condition === "scale_level") base.slug = r.slug;
          if (r.condition === "weekly_consistency") base.threshold = Number(r.threshold);
          if (r.condition === "rare_workout_type") base.threshold_pct = Number(r.threshold_pct);
          if (r.condition === "team_workout_streak") base.min_count = Number(r.min_count);
          return base;
        }),
      };
    } else {
      criteria_value = {
        count,
        increment_per_completion: Number(form.incrementPerCompletion || 1),
        ...(form.incrementLabel.trim() ? { increment_label: form.incrementLabel.trim() } : {}),
      };
    }
  } else {
    criteria_value = { count };
  }

  return {
    title: form.title.trim(),
    description: form.description.trim() || null,
    criteria_type: form.criteriaType,
    criteria_value,
    badge_key: `challenge_${slugify(form.badgeLabel || form.title)}`,
    badge_label: (form.badgeLabel || form.title).trim(),
    starts_at: form.startsAt,
    ends_at: form.endsAt,
  };
}

function hydrateForm(challenge: AdminChallengeRecord): ChallengeFormState {
  const cv = challenge.criteria_value;
  const rawRules = cv.rules as Array<Record<string, unknown>> | undefined;

  const rules: RuleFormRow[] = (rawRules ?? []).map((r) => ({
    id: Math.random().toString(36).slice(2),
    condition: (r.condition as RuleCondition) || "pr_beaten",
    type: String(r.type ?? "crossfit"),
    slug: String(r.slug ?? "rx"),
    threshold: String(r.threshold ?? "50"),
    threshold_pct: String(r.threshold_pct ?? "10"),
    min_count: String(r.min_count ?? "2"),
    points: String(r.points ?? "1"),
    label: String(r.label ?? ""),
  }));

  return {
    title: challenge.title,
    description: challenge.description ?? "",
    criteriaType: challenge.criteria_type as CriteriaType,
    targetCount: String(cv.count ?? 0),
    typeFilter: String(cv.type_filter ?? "crossfit"),
    incrementPerCompletion: String(cv.increment_per_completion ?? 1),
    incrementLabel: String(cv.increment_label ?? ""),
    rules,
    badgeLabel: challenge.badge_label,
    startsAt: challenge.starts_at,
    endsAt: challenge.ends_at,
  };
}

function RuleRowEditor({
  row,
  onChange,
  onRemove,
}: {
  row: RuleFormRow;
  onChange: (updated: RuleFormRow) => void;
  onRemove: () => void;
}) {
  const i18n = useUiTranslations();
  const CONDITION_LABELS: Record<RuleCondition, string> = {
    workout_type: i18n("workoutType34a530c"),
    scale_level: i18n("scaleLeveld3d3921"),
    pr_beaten: i18n("prBeaten0fa47b8"),
    weekly_consistency: i18n("weeklyConsistency251cdee"),
    rare_workout_type: i18n("rareWorkoutType3d74d5c"),
    team_workout_streak: i18n("teamWorkoutStreak7c8340a"),
  };
  const inputStyle = {
    background: "var(--panel-muted)",
    borderColor: "var(--border)",
    color: "var(--text)",
  };

  return (
    <div
      className="rounded-[1.2rem] p-3 space-y-2"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <div className="flex flex-wrap items-center gap-2">
        <select
          className="rounded-xl border px-3 py-2 text-xs flex-1"
          style={inputStyle}
          value={row.condition}
          onChange={(e) => onChange({ ...row, condition: e.target.value as RuleCondition })}
        >
          {(Object.keys(CONDITION_LABELS) as RuleCondition[]).map((c) => (
            <option key={c} value={c}>
              {CONDITION_LABELS[c]}
            </option>
          ))}
        </select>

        {row.condition === "workout_type" && (
          <select
            className="rounded-xl border px-3 py-2 text-xs"
            style={inputStyle}
            value={row.type}
            onChange={(e) => onChange({ ...row, type: e.target.value })}
          >
            {TRAINING_TYPES.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
        )}

        {row.condition === "scale_level" && (
          <input
            className="rounded-xl border px-3 py-2 text-xs w-24"
            style={inputStyle}
            placeholder={i18n("slug6300777")}
            value={row.slug}
            onChange={(e) => onChange({ ...row, slug: e.target.value })}
          />
        )}

        {row.condition === "weekly_consistency" && (
          <label className="flex items-center gap-1 text-xs" style={{ color: "var(--muted)" }}>
            ≥
            <input
              className="rounded-xl border px-2 py-2 text-xs w-16"
              style={inputStyle}
              type="number"
              min={1}
              max={100}
              value={row.threshold}
              onChange={(e) => onChange({ ...row, threshold: e.target.value })}
            />
            %
          </label>
        )}

        {row.condition === "rare_workout_type" && (
          <label className="flex items-center gap-1 text-xs" style={{ color: "var(--muted)" }}>
            &lt;
            <input
              className="rounded-xl border px-2 py-2 text-xs w-16"
              style={inputStyle}
              type="number"
              min={1}
              max={100}
              value={row.threshold_pct}
              onChange={(e) => onChange({ ...row, threshold_pct: e.target.value })}
            />
            %
          </label>
        )}

        {row.condition === "team_workout_streak" && (
          <label className="flex items-center gap-1 text-xs" style={{ color: "var(--muted)" }}>
            ≥
            <input
              className="rounded-xl border px-2 py-2 text-xs w-16"
              style={inputStyle}
              type="number"
              min={1}
              value={row.min_count}
              onChange={(e) => onChange({ ...row, min_count: e.target.value })}
            />
            {i18n("workouts974125d")}
          </label>
        )}

        <label className="flex items-center gap-1 text-xs ms-auto" style={{ color: "var(--muted)" }}>
          {i18n("pts9ba094e")}
          <input
            className="rounded-xl border px-2 py-2 text-xs w-16"
            style={inputStyle}
            type="number"
            min={1}
            step={1}
            value={row.points}
            onChange={(e) => onChange({ ...row, points: e.target.value })}
          />
        </label>

        <button
          type="button"
          className="rounded-xl px-2 py-1 text-xs"
          style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary-strong)" }}
          onClick={onRemove}
        >
          ×
        </button>
      </div>

      <input
        className="w-full rounded-xl border px-3 py-2 text-xs"
        style={{ ...inputStyle, color: "var(--muted)" }}
        placeholder={i18n("labelEGForBeatingAPrce71028")}
        value={row.label}
        onChange={(e) => onChange({ ...row, label: e.target.value })}
      />
    </div>
  );
}

function metricCard(label: string, value: string | number, insight?: string) {
  return (
    <div className="rounded-[1.3rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <div className="flex items-center gap-2">
        <p className="text-[11px] uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {label}
        </p>
        {insight ? <HelpTooltip label={label}>{insight}</HelpTooltip> : null}
      </div>
      <p className="mt-2 text-xl font-semibold" style={{ color: "var(--text)" }}>
        {value}
      </p>
    </div>
  );
}

export function AdminChallenges() {
  function criteriaSummary(challenge: Pick<AdminChallengeRecord, "criteria_type" | "criteria_value">) {
    const cv = challenge.criteria_value;
    const count = typeof cv.count === "number" ? cv.count : Number(cv.count ?? 0);
  
    switch (challenge.criteria_type) {
      case "workout_type_count":
        return i18n("value0Value1Workouts1b9ac0e", {value0: count, value1: semanticLabel(cv.type_filter ?? "targeted", i18n)});
      case "pr_count":
        return i18n("value0Prs11cc809", {value0: count});
      case "custom": {
        const rules = cv.rules as Array<Record<string, unknown>> | undefined;
        if (rules && rules.length > 0) {
          const maxPts = rules.reduce((sum, r) => sum + Number(r.points ?? 0), 0);
          return i18n("reachValue0PtsUpToValue1PtsPerb59c651", {value0: count, value1: maxPts});
        }
        const inc = Number(cv.increment_per_completion ?? 1);
        return i18n("reachValue0PtsValue1PerCompletion80a4cb2", {value0: count, value1: inc});
      }
      default:
        return i18n("value0Workoutse047dc5", {value0: count});
    }
  }

  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const { tokens } = useSession();
  const [selectedChallengeId, setSelectedChallengeId] = useState<string | null>(null);
  const [form, setForm] = useState<ChallengeFormState>(() => emptyForm());

  const challengesQuery = useQuery({
    queryKey: ["admin", "challenges"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => {
      if (!tokens?.access_token) throw new Error(i18n("authenticationRequired9e44e0b"));
      return fetchAdminChallenges(tokens.access_token);
    },
  });

  const detailQuery = useQuery({
    queryKey: ["admin", "challenges", selectedChallengeId],
    enabled: Boolean(tokens?.access_token && selectedChallengeId),
    queryFn: async () => {
      if (!tokens?.access_token || !selectedChallengeId) throw new Error(i18n("challengeSelectionRequired13ef24b"));
      return fetchAdminChallenge(tokens.access_token, selectedChallengeId);
    },
  });

  const saveMutation = useMutation({
    mutationFn: async () => {
      if (!tokens?.access_token) throw new Error(i18n("authenticationRequired9e44e0b"));

      const payload = payloadFromForm(form);

      if (selectedChallengeId) {
        return updateAdminChallenge(tokens.access_token, selectedChallengeId, payload);
      }

      return createAdminChallenge(tokens.access_token, payload);
    },
    onSuccess: async (response) => {
      await challengesQuery.refetch();
      setSelectedChallengeId(response.challenge.id);
      if (tokens?.access_token) {
        const detail = await fetchAdminChallenge(tokens.access_token, response.challenge.id);
        setForm(hydrateForm(detail.challenge));
      }
    },
  });

  const challenges = useMemo(() => challengesQuery.data?.challenges ?? [], [challengesQuery.data?.challenges]);
  const activeCount = useMemo(
    () => challenges.filter((challenge) => challengeStatus(challenge) === "active").length,
    [challenges],
  );
  const selectedChallenge = detailQuery.data?.challenge ?? null;
  const participants = detailQuery.data?.participants ?? [];
  const editing = Boolean(selectedChallengeId);
  const challengeInsight = i18n("createAndEditSeasonalChallengesInspectLiveParticipation96025e7");

  function updateForm<K extends keyof ChallengeFormState>(key: K, value: ChallengeFormState[K]) {
    setForm((current) => ({ ...current, [key]: value }));
  }

  function startCreateMode() {
    setSelectedChallengeId(null);
    setForm(emptyForm());
  }

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-7xl space-y-8">
        <TransientHero label={i18n("challengeManagementIntroduction7702a15")} timeoutMs={3000}>
        <section className="rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex flex-wrap items-start justify-between gap-6">
            <div className="max-w-4xl">
              <p className="text-sm font-semibold uppercase tracking-[0.28em] text-[var(--primary)]">{i18n("adminChallenges67e0d16")}</p>
              <h1 className="mt-2 text-3xl font-semibold tracking-tight md:text-4xl" style={{ color: "var(--text)" }}>
                {i18n("seasonalChallengeManagement522b160")}
              </h1>
              <p className="mt-2 text-sm leading-6" style={{ color: "var(--muted)" }}>
                {i18n("createAndEditSeasonalChallengesInspectLiveParticipation96025e7")}
              </p>
            </div>

            <div className="rounded-[1.4rem] px-5 py-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
              <div className="flex items-center gap-2">
                <p className="text-[11px] uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                  {i18n("activeToday9f14dee")}
                </p>
                <HelpTooltip label={i18n("activeToday9f14dee")}>{challengeInsight}</HelpTooltip>
              </div>
              <p className="mt-2 text-2xl font-semibold" style={{ color: "var(--text)" }}>
                {activeCount} / 3
              </p>
            </div>
          </div>
        </section>
        </TransientHero>

        <section className="grid gap-6 xl:grid-cols-[0.92fr_1.08fr]">
          <article className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>
                  {editing ? i18n("editChallenge9e06136") : i18n("createChallengea12c2ce")}
                </p>
                <h2 className="mt-2 text-2xl font-semibold" style={{ color: "var(--text)" }}>
                  {editing ? i18n("updateTheActiveDefinition98d94cb") : i18n("defineANewSeasonalChallenge47ea252")}
                </h2>
              </div>

              {editing ? (
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "var(--border)", color: "var(--text-soft)" }}
                  onClick={startCreateMode}
                  type="button"
                >
                  {i18n("newChallenge98b5e6d")}
                </button>
              ) : null}
            </div>

            <div className="mt-6 space-y-4">
              <label className="block space-y-2">
                <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                  {i18n("title768e0c1")}
                </span>
                <input
                  className="w-full rounded-2xl border px-4 py-3 text-sm"
                  style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                  value={form.title}
                  onChange={(event) => updateForm("title", event.target.value)}
                />
              </label>

              <label className="block space-y-2">
                <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                  {i18n("description55f8ebc")}
                </span>
                <textarea
                  className="min-h-28 w-full rounded-2xl border px-4 py-3 text-sm"
                  style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                  value={form.description}
                  onChange={(event) => updateForm("description", event.target.value)}
                />
              </label>

              <div className="grid gap-4 sm:grid-cols-2">
                <label className="block space-y-2">
                  <span className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {i18n("criteriaTypedf7b95e")}
                    <HelpTooltip label={i18n("criteriaTypedf7b95e")}>{challengeInsight}</HelpTooltip>
                  </span>
                  <select
                    className="w-full rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                    value={form.criteriaType}
                    onChange={(event) => updateForm("criteriaType", event.target.value as CriteriaType)}
                  >
                    <option value="workout_count">{i18n("workoutCountc0c4093")}</option>
                    <option value="workout_type_count">{i18n("workoutTypeCount2e4362c")}</option>
                    <option value="pr_count">{i18n("prCount5527d5d")}</option>
                    <option value="custom">{i18n("custom081ae3f")}</option>
                  </select>
                </label>

                <label className="block space-y-2">
                  <span className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {i18n("targetCountef87dbf")}
                    <HelpTooltip label={i18n("targetCountef87dbf")}>{criteriaSummary(payloadFromForm(form))}</HelpTooltip>
                  </span>
                  <input
                    className="w-full rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                    value={form.targetCount}
                    onChange={(event) => updateForm("targetCount", event.target.value)}
                    type="number"
                  />
                </label>
              </div>

              {form.criteriaType === "workout_type_count" ? (
                <label className="block space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {i18n("workoutTypeFiltercfb5c8d")}
                  </span>
                  <select
                    className="w-full rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                    value={form.typeFilter}
                    onChange={(event) => updateForm("typeFilter", event.target.value)}
                  >
                    {TRAINING_TYPES.map((value) => (
                      <option key={value} value={value}>
                        {value}
                      </option>
                    ))}
                  </select>
                </label>
              ) : null}

              {form.criteriaType === "custom" ? (
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <span
                      className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em]"
                      style={{ color: "var(--dim)" }}
                    >
                      {i18n("pointsRules6075014")}
                      <HelpTooltip label={i18n("pointsRules6075014")}>{criteriaSummary(payloadFromForm(form))}</HelpTooltip>
                    </span>
                    <button
                      type="button"
                      className="rounded-full px-3 py-1 text-xs font-semibold"
                      style={{ background: "var(--border)", color: "var(--text-soft)" }}
                      onClick={() => updateForm("rules", [...form.rules, defaultRuleRow()])}
                    >
                      {i18n("addRule5a8edc3")}
                    </button>
                  </div>

                  {form.rules.length === 0 ? (
                    <>
                      <label className="block space-y-2">
                        <span
                          className="text-xs font-semibold uppercase tracking-[0.18em]"
                          style={{ color: "var(--dim)" }}
                        >
                          {i18n("incrementPerCompletion9b4256e")}
                        </span>
                        <input
                          className="w-full rounded-2xl border px-4 py-3 text-sm"
                          style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                          value={form.incrementPerCompletion}
                          onChange={(e) => updateForm("incrementPerCompletion", e.target.value)}
                          type="number"
                          min={1}
                          step={1}
                        />
                      </label>
                      <label className="block space-y-2">
                        <span
                          className="text-xs font-semibold uppercase tracking-[0.18em]"
                          style={{ color: "var(--dim)" }}
                        >
                          {i18n("pointsLabelOptional2362394")}
                        </span>
                        <input
                          className="w-full rounded-2xl border px-4 py-3 text-sm"
                          style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                          placeholder={i18n("eGForCompletingAnyWorkout8cf1db0")}
                          value={form.incrementLabel}
                          onChange={(e) => updateForm("incrementLabel", e.target.value)}
                        />
                      </label>
                    </>
                  ) : (
                    <div className="space-y-2">
                      {form.rules.map((rule, idx) => (
                        <RuleRowEditor
                          key={rule.id}
                          row={rule}
                          onChange={(updated) =>
                            updateForm(
                              "rules",
                              form.rules.map((r, i) => (i === idx ? updated : r)),
                            )
                          }
                          onRemove={() =>
                            updateForm(
                              "rules",
                              form.rules.filter((_, i) => i !== idx),
                            )
                          }
                        />
                      ))}
                    </div>
                  )}
                </div>
              ) : null}

              <div className="grid gap-4 sm:grid-cols-2">
                <label className="block space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {i18n("badgeLabeld74ab69")}
                  </span>
                  <input
                    className="w-full rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                    value={form.badgeLabel}
                    onChange={(event) => updateForm("badgeLabel", event.target.value)}
                  />
                </label>

                <div className="space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {i18n("badgeKeyPreviewc86e06d")}
                  </span>
                  <div
                    className="rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                  >
                    {"challenge_" + (slugify(form.badgeLabel || form.title || "new_challenge"))}
                  </div>
                </div>
              </div>

              <div className="grid gap-4 sm:grid-cols-2">
                <label className="block space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {i18n("startsfc612a2")}
                  </span>
                  <input
                    className="w-full rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                    type="date"
                    value={form.startsAt}
                    onChange={(event) => updateForm("startsAt", event.target.value)}
                  />
                </label>

                <label className="block space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {i18n("ends91856dc")}
                  </span>
                  <input
                    className="w-full rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                    type="date"
                    value={form.endsAt}
                    onChange={(event) => updateForm("endsAt", event.target.value)}
                  />
                </label>
              </div>

              <div className="flex flex-wrap items-center gap-3">
                <button
                  className="rounded-full px-5 py-3 text-sm font-semibold text-[var(--primary-contrast)] disabled:opacity-50"
                  style={{ background: "var(--primary)" }}
                  disabled={saveMutation.isPending || form.title.trim().length === 0}
                  onClick={() => void saveMutation.mutateAsync()}
                  type="button"
                >
                  {saveMutation.isPending ? i18n("savingae7e887") : editing ? i18n("saveChanges179359b") : i18n("createChallengea12c2ce")}
                </button>
                <span className="text-sm" style={{ color: "var(--muted)" }}>
                  {criteriaSummary(payloadFromForm(form))}
                </span>
              </div>

              {saveMutation.isError ? (
                <p className="text-sm" style={{ color: "var(--primary)" }}>
                  {saveMutation.error instanceof Error ? localizeError(saveMutation.error, i18n) : i18n("challengeCouldNotBeSavedec78ef0")}
                </p>
              ) : null}
            </div>
          </article>

          <div className="space-y-6">
            <article className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <div className="flex items-center justify-between gap-4">
                <div>
                  <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>
                    {i18n("challengeRosterf464e7f")}
                  </p>
                  <h2 className="mt-2 text-2xl font-semibold" style={{ color: "var(--text)" }}>
                    {i18n("existingChallengesf1277f2")}
                  </h2>
                </div>
              </div>

              <div className="mt-5 space-y-4">
                {challengesQuery.isPending ? (
                  <p className="text-sm" style={{ color: "var(--muted)" }}>
                    {i18n("loadingChallengescfd3c00")}
                  </p>
                ) : challenges.length === 0 ? (
                  <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "var(--panel-muted)", color: "var(--muted)" }}>
                    {i18n("noSeasonalChallengesCreatedYet606b1c2")}
                  </p>
                ) : (
                  challenges.map((challenge) => {
                    const selected = challenge.id == selectedChallengeId;
                    const status = challengeStatus(challenge);

                    return (
                      <button
                        key={challenge.id}
                        className="w-full rounded-[1.6rem] p-4 text-start transition-colors"
                        style={
                          selected
                            ? { background: "var(--panel-raised)", border: "1px solid var(--primary)" }
                            : { background: "var(--panel-muted)", border: "1px solid var(--border)" }
                        }
                        onClick={async () => {
                          setSelectedChallengeId(challenge.id);

                          if (tokens?.access_token) {
                            const detail = await fetchAdminChallenge(tokens.access_token, challenge.id);
                            setForm(hydrateForm(detail.challenge));
                          }
                        }}
                        type="button"
                      >
                        <div className="flex items-start justify-between gap-4">
                          <div>
                            <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                              {challenge.title}
                            </p>
                            <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
                              {challenge.description || i18n("noDescriptionf354c94")}
                            </p>
                          </div>
                          <span
                            className="rounded-full px-3 py-1 text-xs font-semibold uppercase tracking-[0.12em]"
                            style={{
                              background:
                                status === "active"
                                  ? "color-mix(in srgb, var(--success) 12%, transparent)"
                                  : status === "upcoming"
                                    ? "color-mix(in srgb, var(--primary) 12%, transparent)"
                                    : "var(--border)",
                              color:
                                status === "active"
                                  ? "var(--success)"
                                  : status === "upcoming"
                                    ? "var(--primary)"
                                    : "var(--muted)",
                            }}
                          >
                            <SemanticLabel value={status} />
                          </span>
                        </div>

                        <div className="mt-4 grid gap-3 sm:grid-cols-4">
                          <div>
                            <p className="text-[11px] uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                              {i18n("participantscd56e08")}
                            </p>
                            <p className="mt-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
                              {challenge.progress_summary.participants}
                            </p>
                          </div>
                          <div>
                            <p className="text-[11px] uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                              {i18n("completed1798b3b")}
                            </p>
                            <p className="mt-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
                              {challenge.progress_summary.completed}
                            </p>
                          </div>
                          <div>
                            <p className="text-[11px] uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                              {i18n("avgProgress026284f")}
                            </p>
                            <p className="mt-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
                              {challenge.progress_summary.average_progress}
                            </p>
                          </div>
                          <div>
                            <p className="text-[11px] uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                              {i18n("completionRatea360083")}
                            </p>
                            <p className="mt-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
                              {(challenge.progress_summary.completion_rate * 100).toFixed(0)}%
                            </p>
                          </div>
                        </div>
                      </button>
                    );
                  })
                )}
              </div>
            </article>

            <article className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <div className="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>
                    {i18n("participation74d2f1b")}
                  </p>
                  <h2 className="mt-2 text-2xl font-semibold" style={{ color: "var(--text)" }}>
                    {selectedChallenge ? selectedChallenge.title : i18n("selectAChallengeb534934")}
                  </h2>
                </div>
                {selectedChallenge ? (
                  <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)" }}>
                    {i18n("target61ad50a")} {selectedChallenge.progress_summary.target}
                  </span>
                ) : null}
              </div>

              {detailQuery.isPending && selectedChallengeId ? (
                <p className="mt-5 text-sm" style={{ color: "var(--muted)" }}>
                  {i18n("loadingChallengeDetail675cf58")}
                </p>
              ) : !selectedChallenge ? (
                <p className="mt-5 rounded-2xl px-4 py-5 text-sm" style={{ background: "var(--panel-muted)", color: "var(--muted)" }}>
                  {i18n("chooseAChallengeFromTheRosterToInspect8e88bfd")}
                </p>
              ) : (
                <>
                  <div className="mt-5 grid gap-3 sm:grid-cols-4">
                    {metricCard(i18n("participantscd56e08"), selectedChallenge.progress_summary.participants, challengeInsight)}
                    {metricCard(i18n("completed1798b3b"), selectedChallenge.progress_summary.completed, challengeInsight)}
                    {metricCard(i18n("avgProgress026284f"), selectedChallenge.progress_summary.average_progress, criteriaSummary(selectedChallenge))}
                    {metricCard(i18n("completionRatea360083"), ((selectedChallenge.progress_summary.completion_rate * 100).toFixed(0)) + "%", criteriaSummary(selectedChallenge))}
                  </div>

                  <div className="mt-5 overflow-x-auto rounded-[1.4rem]" style={{ border: "1px solid var(--border)" }}>
                    <table className="min-w-full divide-y divide-[var(--border)] text-sm">
                      <thead style={{ background: "var(--panel-muted)", color: "var(--muted)" }}>
                        <tr>
                          <th className="px-4 py-3 text-start font-semibold">{i18n("user9f8a238")}</th>
                          <th className="px-4 py-3 text-start font-semibold">{i18n("rolec3f104d")}</th>
                          <th className="px-4 py-3 text-start font-semibold">{i18n("progress1b90271")}</th>
                          <th className="px-4 py-3 text-start font-semibold">{i18n("target61ad50a")}</th>
                          {selectedChallenge?.criteria_type === "custom" ? (
                            <>
                              <th className="px-4 py-3 text-start font-semibold">{i18n("donee9b450d")}</th>
                              <th className="px-4 py-3 text-start font-semibold">{i18n("remainingcc632b5")}</th>
                            </>
                          ) : null}
                          <th className="px-4 py-3 text-start font-semibold">{i18n("completion2ff2556")}</th>
                          <th className="px-4 py-3 text-start font-semibold">{i18n("completedAt3cabb39")}</th>
                        </tr>
                      </thead>
                      <tbody style={{ background: "var(--panel)", color: "var(--text)" }}>
                        {participants.length === 0 ? (
                          <tr>
                            <td
                              className="px-4 py-5 text-sm"
                              colSpan={selectedChallenge?.criteria_type === "custom" ? 8 : 6}
                              style={{ color: "var(--muted)" }}
                            >
                              {i18n("noMembersOrAthletesHaveRegisteredProgressFor68f49f1")}
                            </td>
                          </tr>
                        ) : (
                          participants.map((participant) => (
                            <tr key={participant.user_id} style={{ borderTop: "1px solid var(--border)" }}>
                              <td className="px-4 py-3">{participant.nickname || participant.user_id}</td>
                              <td className="px-4 py-3" style={{ color: "var(--muted)" }}>
                                {participant.role ? <SemanticLabel value={participant.role} /> : i18n("unknownbc7819b")}
                              </td>
                              <td className="px-4 py-3">{participant.progress}</td>
                              <td className="px-4 py-3">{participant.target}</td>
                              {selectedChallenge?.criteria_type === "custom" ? (
                                <>
                                  <td className="px-4 py-3">{participant.completions_done ?? "—"}</td>
                                  <td className="px-4 py-3">{participant.completions_remaining ?? "—"}</td>
                                </>
                              ) : null}
                              <td className="px-4 py-3">{(participant.completion_ratio * 100).toFixed(0)}%</td>
                              <td
                                className="px-4 py-3"
                                style={{ color: participant.completed_at ? "var(--success)" : "var(--muted)" }}
                              >
                                {participant.completed_at
                                  ? new Intl.DateTimeFormat(uiLocale, {
                                      month: "short",
                                      day: "numeric",
                                      hour: "numeric",
                                      minute: "2-digit",
                                    }).format(new Date(participant.completed_at))
                                  : i18n("inProgressb6bd42e")}
                              </td>
                            </tr>
                          ))
                        )}
                      </tbody>
                    </table>
                  </div>
                </>
              )}
            </article>
          </div>
        </section>
      </div>
    </main>
  );
}
