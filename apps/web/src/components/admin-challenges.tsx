"use client";

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
import { addLocalDays, formatLocalDate } from "@/lib/local-date";

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

const CONDITION_LABELS: Record<RuleCondition, string> = {
  workout_type: "Workout type",
  scale_level: "Scale level",
  pr_beaten: "PR beaten",
  weekly_consistency: "Weekly consistency",
  rare_workout_type: "Rare workout type",
  team_workout_streak: "Team workout streak",
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

function criteriaSummary(challenge: Pick<AdminChallengeRecord, "criteria_type" | "criteria_value">) {
  const cv = challenge.criteria_value;
  const count = typeof cv.count === "number" ? cv.count : Number(cv.count ?? 0);

  switch (challenge.criteria_type) {
    case "workout_type_count":
      return `${count} ${String(cv.type_filter ?? "targeted")} workouts`;
    case "pr_count":
      return `${count} PRs`;
    case "custom": {
      const rules = cv.rules as Array<Record<string, unknown>> | undefined;
      if (rules && rules.length > 0) {
        const maxPts = rules.reduce((sum, r) => sum + Number(r.points ?? 0), 0);
        return `Reach ${count} pts · up to ${maxPts} pts per workout`;
      }
      const inc = Number(cv.increment_per_completion ?? 1);
      return `Reach ${count} pts (+${inc} per completion)`;
    }
    default:
      return `${count} workouts`;
  }
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
  const inputStyle = {
    background: "#0d0d18",
    borderColor: "#1a1a28",
    color: "#F0EDF8",
  };

  return (
    <div
      className="rounded-[1.2rem] p-3 space-y-2"
      style={{ background: "#0a0a14", border: "1px solid #1a1a28" }}
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
            placeholder="slug"
            value={row.slug}
            onChange={(e) => onChange({ ...row, slug: e.target.value })}
          />
        )}

        {row.condition === "weekly_consistency" && (
          <label className="flex items-center gap-1 text-xs" style={{ color: "#8888aa" }}>
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
          <label className="flex items-center gap-1 text-xs" style={{ color: "#8888aa" }}>
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
          <label className="flex items-center gap-1 text-xs" style={{ color: "#8888aa" }}>
            ≥
            <input
              className="rounded-xl border px-2 py-2 text-xs w-16"
              style={inputStyle}
              type="number"
              min={1}
              value={row.min_count}
              onChange={(e) => onChange({ ...row, min_count: e.target.value })}
            />
            workouts
          </label>
        )}

        <label className="flex items-center gap-1 text-xs ml-auto" style={{ color: "#8888aa" }}>
          pts:
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
          style={{ background: "rgba(217,93,57,0.12)", color: "#e07a5f" }}
          onClick={onRemove}
        >
          ×
        </button>
      </div>

      <input
        className="w-full rounded-xl border px-3 py-2 text-xs"
        style={{ ...inputStyle, color: "#8888aa" }}
        placeholder="Label (e.g. for beating a PR)"
        value={row.label}
        onChange={(e) => onChange({ ...row, label: e.target.value })}
      />
    </div>
  );
}

function metricCard(label: string, value: string | number) {
  return (
    <div className="rounded-[1.3rem] p-4" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
      <p className="text-[11px] uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
        {label}
      </p>
      <p className="mt-2 text-xl font-semibold" style={{ color: "#F0EDF8" }}>
        {value}
      </p>
    </div>
  );
}

export function AdminChallenges() {
  const { tokens } = useSession();
  const [selectedChallengeId, setSelectedChallengeId] = useState<string | null>(null);
  const [form, setForm] = useState<ChallengeFormState>(() => emptyForm());

  const challengesQuery = useQuery({
    queryKey: ["admin", "challenges"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => {
      if (!tokens?.access_token) throw new Error("Authentication required.");
      return fetchAdminChallenges(tokens.access_token);
    },
  });

  const detailQuery = useQuery({
    queryKey: ["admin", "challenges", selectedChallengeId],
    enabled: Boolean(tokens?.access_token && selectedChallengeId),
    queryFn: async () => {
      if (!tokens?.access_token || !selectedChallengeId) throw new Error("Challenge selection required.");
      return fetchAdminChallenge(tokens.access_token, selectedChallengeId);
    },
  });

  const saveMutation = useMutation({
    mutationFn: async () => {
      if (!tokens?.access_token) throw new Error("Authentication required.");

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

  function updateForm<K extends keyof ChallengeFormState>(key: K, value: ChallengeFormState[K]) {
    setForm((current) => ({ ...current, [key]: value }));
  }

  function startCreateMode() {
    setSelectedChallengeId(null);
    setForm(emptyForm());
  }

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "#0A0A0F" }}>
      <div className="mx-auto max-w-7xl space-y-8">
        <section className="rounded-[2.4rem] p-8" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
          <div className="flex flex-wrap items-start justify-between gap-6">
            <div className="max-w-4xl">
              <p className="text-sm font-semibold uppercase tracking-[0.28em] text-[#d95d39]">Admin Challenges</p>
              <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "#F0EDF8" }}>
                Seasonal challenge management.
              </h1>
              <p className="mt-4 text-base leading-7" style={{ color: "#8888aa" }}>
                Create and edit seasonal challenges, inspect live participation, and review how members and
                athletes are progressing against each target.
              </p>
            </div>

            <div className="rounded-[1.4rem] px-5 py-4" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
              <p className="text-[11px] uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                Active today
              </p>
              <p className="mt-2 text-2xl font-semibold" style={{ color: "#F0EDF8" }}>
                {activeCount} / 3
              </p>
            </div>
          </div>
        </section>

        <section className="grid gap-6 xl:grid-cols-[0.92fr_1.08fr]">
          <article className="rounded-[2rem] p-6" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "#55556a" }}>
                  {editing ? "Edit challenge" : "Create challenge"}
                </p>
                <h2 className="mt-2 text-2xl font-semibold" style={{ color: "#F0EDF8" }}>
                  {editing ? "Update the active definition." : "Define a new seasonal challenge."}
                </h2>
              </div>

              {editing ? (
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "#1a1a28", color: "#c0c0d8" }}
                  onClick={startCreateMode}
                  type="button"
                >
                  New challenge
                </button>
              ) : null}
            </div>

            <div className="mt-6 space-y-4">
              <label className="block space-y-2">
                <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                  Title
                </span>
                <input
                  className="w-full rounded-2xl border px-4 py-3 text-sm"
                  style={{ background: "#0d0d18", borderColor: "#1a1a28", color: "#F0EDF8" }}
                  value={form.title}
                  onChange={(event) => updateForm("title", event.target.value)}
                />
              </label>

              <label className="block space-y-2">
                <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                  Description
                </span>
                <textarea
                  className="min-h-28 w-full rounded-2xl border px-4 py-3 text-sm"
                  style={{ background: "#0d0d18", borderColor: "#1a1a28", color: "#F0EDF8" }}
                  value={form.description}
                  onChange={(event) => updateForm("description", event.target.value)}
                />
              </label>

              <div className="grid gap-4 sm:grid-cols-2">
                <label className="block space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                    Criteria type
                  </span>
                  <select
                    className="w-full rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "#0d0d18", borderColor: "#1a1a28", color: "#F0EDF8" }}
                    value={form.criteriaType}
                    onChange={(event) => updateForm("criteriaType", event.target.value as CriteriaType)}
                  >
                    <option value="workout_count">Workout count</option>
                    <option value="workout_type_count">Workout type count</option>
                    <option value="pr_count">PR count</option>
                    <option value="custom">Custom</option>
                  </select>
                </label>

                <label className="block space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                    Target count
                  </span>
                  <input
                    className="w-full rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "#0d0d18", borderColor: "#1a1a28", color: "#F0EDF8" }}
                    value={form.targetCount}
                    onChange={(event) => updateForm("targetCount", event.target.value)}
                    type="number"
                  />
                </label>
              </div>

              {form.criteriaType === "workout_type_count" ? (
                <label className="block space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                    Workout type filter
                  </span>
                  <select
                    className="w-full rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "#0d0d18", borderColor: "#1a1a28", color: "#F0EDF8" }}
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
                      className="text-xs font-semibold uppercase tracking-[0.18em]"
                      style={{ color: "#55556a" }}
                    >
                      Points Rules
                    </span>
                    <button
                      type="button"
                      className="rounded-full px-3 py-1 text-xs font-semibold"
                      style={{ background: "#1a1a28", color: "#c0c0d8" }}
                      onClick={() => updateForm("rules", [...form.rules, defaultRuleRow()])}
                    >
                      + Add rule
                    </button>
                  </div>

                  {form.rules.length === 0 ? (
                    <>
                      <label className="block space-y-2">
                        <span
                          className="text-xs font-semibold uppercase tracking-[0.18em]"
                          style={{ color: "#55556a" }}
                        >
                          Increment per completion
                        </span>
                        <input
                          className="w-full rounded-2xl border px-4 py-3 text-sm"
                          style={{ background: "#0d0d18", borderColor: "#1a1a28", color: "#F0EDF8" }}
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
                          style={{ color: "#55556a" }}
                        >
                          Points label (optional)
                        </span>
                        <input
                          className="w-full rounded-2xl border px-4 py-3 text-sm"
                          style={{ background: "#0d0d18", borderColor: "#1a1a28", color: "#F0EDF8" }}
                          placeholder="e.g. for completing any workout"
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
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                    Badge label
                  </span>
                  <input
                    className="w-full rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "#0d0d18", borderColor: "#1a1a28", color: "#F0EDF8" }}
                    value={form.badgeLabel}
                    onChange={(event) => updateForm("badgeLabel", event.target.value)}
                  />
                </label>

                <div className="space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                    Badge key preview
                  </span>
                  <div
                    className="rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "#0d0d18", borderColor: "#1a1a28", color: "#F0EDF8" }}
                  >
                    {`challenge_${slugify(form.badgeLabel || form.title || "new_challenge")}`}
                  </div>
                </div>
              </div>

              <div className="grid gap-4 sm:grid-cols-2">
                <label className="block space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                    Starts
                  </span>
                  <input
                    className="w-full rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "#0d0d18", borderColor: "#1a1a28", color: "#F0EDF8" }}
                    type="date"
                    value={form.startsAt}
                    onChange={(event) => updateForm("startsAt", event.target.value)}
                  />
                </label>

                <label className="block space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                    Ends
                  </span>
                  <input
                    className="w-full rounded-2xl border px-4 py-3 text-sm"
                    style={{ background: "#0d0d18", borderColor: "#1a1a28", color: "#F0EDF8" }}
                    type="date"
                    value={form.endsAt}
                    onChange={(event) => updateForm("endsAt", event.target.value)}
                  />
                </label>
              </div>

              <div className="flex flex-wrap items-center gap-3">
                <button
                  className="rounded-full px-5 py-3 text-sm font-semibold text-white disabled:opacity-50"
                  style={{ background: "#d95d39" }}
                  disabled={saveMutation.isPending || form.title.trim().length === 0}
                  onClick={() => void saveMutation.mutateAsync()}
                  type="button"
                >
                  {saveMutation.isPending ? "Saving..." : editing ? "Save changes" : "Create challenge"}
                </button>
                <span className="text-sm" style={{ color: "#8888aa" }}>
                  {criteriaSummary(payloadFromForm(form))}
                </span>
              </div>

              {saveMutation.isError ? (
                <p className="text-sm" style={{ color: "#d95d39" }}>
                  {saveMutation.error instanceof Error ? saveMutation.error.message : "Challenge could not be saved."}
                </p>
              ) : null}
            </div>
          </article>

          <div className="space-y-6">
            <article className="rounded-[2rem] p-6" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
              <div className="flex items-center justify-between gap-4">
                <div>
                  <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "#55556a" }}>
                    Challenge roster
                  </p>
                  <h2 className="mt-2 text-2xl font-semibold" style={{ color: "#F0EDF8" }}>
                    Existing challenges
                  </h2>
                </div>
              </div>

              <div className="mt-5 space-y-4">
                {challengesQuery.isPending ? (
                  <p className="text-sm" style={{ color: "#8888aa" }}>
                    Loading challenges...
                  </p>
                ) : challenges.length === 0 ? (
                  <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "#0d0d18", color: "#8888aa" }}>
                    No seasonal challenges created yet.
                  </p>
                ) : (
                  challenges.map((challenge) => {
                    const selected = challenge.id == selectedChallengeId;
                    const status = challengeStatus(challenge);

                    return (
                      <button
                        key={challenge.id}
                        className="w-full rounded-[1.6rem] p-4 text-left transition-colors"
                        style={
                          selected
                            ? { background: "#151126", border: "1px solid #9c799c" }
                            : { background: "#0d0d18", border: "1px solid #1a1a28" }
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
                            <p className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                              {challenge.title}
                            </p>
                            <p className="mt-1 text-sm" style={{ color: "#8888aa" }}>
                              {challenge.description || "No description"}
                            </p>
                          </div>
                          <span
                            className="rounded-full px-3 py-1 text-xs font-semibold uppercase tracking-[0.12em]"
                            style={{
                              background:
                                status === "active"
                                  ? "rgba(34,197,94,0.12)"
                                  : status === "upcoming"
                                    ? "rgba(217,93,57,0.12)"
                                    : "#1a1a28",
                              color:
                                status === "active"
                                  ? "#4ade80"
                                  : status === "upcoming"
                                    ? "#d95d39"
                                    : "#8888aa",
                            }}
                          >
                            {status}
                          </span>
                        </div>

                        <div className="mt-4 grid gap-3 sm:grid-cols-4">
                          <div>
                            <p className="text-[11px] uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                              Participants
                            </p>
                            <p className="mt-1 text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                              {challenge.progress_summary.participants}
                            </p>
                          </div>
                          <div>
                            <p className="text-[11px] uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                              Completed
                            </p>
                            <p className="mt-1 text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                              {challenge.progress_summary.completed}
                            </p>
                          </div>
                          <div>
                            <p className="text-[11px] uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                              Avg progress
                            </p>
                            <p className="mt-1 text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                              {challenge.progress_summary.average_progress}
                            </p>
                          </div>
                          <div>
                            <p className="text-[11px] uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                              Completion rate
                            </p>
                            <p className="mt-1 text-sm font-semibold" style={{ color: "#F0EDF8" }}>
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

            <article className="rounded-[2rem] p-6" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
              <div className="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "#55556a" }}>
                    Participation
                  </p>
                  <h2 className="mt-2 text-2xl font-semibold" style={{ color: "#F0EDF8" }}>
                    {selectedChallenge ? selectedChallenge.title : "Select a challenge"}
                  </h2>
                </div>
                {selectedChallenge ? (
                  <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "rgba(217,93,57,0.12)", color: "#d95d39" }}>
                    Target {selectedChallenge.progress_summary.target}
                  </span>
                ) : null}
              </div>

              {detailQuery.isPending && selectedChallengeId ? (
                <p className="mt-5 text-sm" style={{ color: "#8888aa" }}>
                  Loading challenge detail...
                </p>
              ) : !selectedChallenge ? (
                <p className="mt-5 rounded-2xl px-4 py-5 text-sm" style={{ background: "#0d0d18", color: "#8888aa" }}>
                  Choose a challenge from the roster to inspect member and athlete progress.
                </p>
              ) : (
                <>
                  <div className="mt-5 grid gap-3 sm:grid-cols-4">
                    {metricCard("Participants", selectedChallenge.progress_summary.participants)}
                    {metricCard("Completed", selectedChallenge.progress_summary.completed)}
                    {metricCard("Avg progress", selectedChallenge.progress_summary.average_progress)}
                    {metricCard("Completion rate", `${(selectedChallenge.progress_summary.completion_rate * 100).toFixed(0)}%`)}
                  </div>

                  <div className="mt-5 overflow-x-auto rounded-[1.4rem]" style={{ border: "1px solid #1a1a28" }}>
                    <table className="min-w-full divide-y divide-[#1a1a28] text-sm">
                      <thead style={{ background: "#0d0d18", color: "#8888aa" }}>
                        <tr>
                          <th className="px-4 py-3 text-left font-semibold">User</th>
                          <th className="px-4 py-3 text-left font-semibold">Role</th>
                          <th className="px-4 py-3 text-left font-semibold">Progress</th>
                          <th className="px-4 py-3 text-left font-semibold">Target</th>
                          {selectedChallenge?.criteria_type === "custom" ? (
                            <>
                              <th className="px-4 py-3 text-left font-semibold">Done</th>
                              <th className="px-4 py-3 text-left font-semibold">Remaining</th>
                            </>
                          ) : null}
                          <th className="px-4 py-3 text-left font-semibold">Completion</th>
                          <th className="px-4 py-3 text-left font-semibold">Completed at</th>
                        </tr>
                      </thead>
                      <tbody style={{ background: "#111118", color: "#F0EDF8" }}>
                        {participants.length === 0 ? (
                          <tr>
                            <td
                              className="px-4 py-5 text-sm"
                              colSpan={selectedChallenge?.criteria_type === "custom" ? 8 : 6}
                              style={{ color: "#8888aa" }}
                            >
                              No members or athletes have registered progress for this challenge yet.
                            </td>
                          </tr>
                        ) : (
                          participants.map((participant) => (
                            <tr key={participant.user_id} style={{ borderTop: "1px solid #1a1a28" }}>
                              <td className="px-4 py-3">{participant.nickname || participant.user_id}</td>
                              <td className="px-4 py-3" style={{ color: "#8888aa" }}>
                                {participant.role || "unknown"}
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
                                style={{ color: participant.completed_at ? "#4ade80" : "#8888aa" }}
                              >
                                {participant.completed_at
                                  ? new Intl.DateTimeFormat("en-US", {
                                      month: "short",
                                      day: "numeric",
                                      hour: "numeric",
                                      minute: "2-digit",
                                    }).format(new Date(participant.completed_at))
                                  : "In progress"}
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
