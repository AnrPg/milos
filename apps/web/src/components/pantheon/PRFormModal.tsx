"use client";






import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useId, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  createPR,
  updatePR,
  type PRRecord,
  type PRSupportingMetricKey,
  type PRSupportingMetrics,
  type PRUnit,
} from "@/api/gamification";
import { useSession } from "@/components/session-provider";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

type TimeFields = { hours: string; minutes: string; seconds: string; milliseconds: string };

const NUMERIC_DETAIL_FIELDS: PRSupportingMetricKey[] = [
  "reps",
  "sets",
  "load_kg",
  "duration_seconds",
  "distance_m",
  "calories",
  "rounds",
];

const DETAIL_OPTIONS: Record<PRUnit, PRSupportingMetricKey[]> = {
  kg: ["reps", "sets", "duration_seconds", "distance_m", "calories", "rounds", "variation"],
  reps: ["load_kg", "sets", "duration_seconds", "distance_m", "calories", "rounds", "variation"],
  mins_secs: ["reps", "sets", "load_kg", "distance_m", "calories", "rounds", "variation"],
  m: ["duration_seconds", "reps", "sets", "load_kg", "calories", "rounds", "variation"],
  kcals: ["duration_seconds", "distance_m", "reps", "sets", "load_kg", "rounds", "variation"],
  sets: ["reps", "load_kg", "duration_seconds", "distance_m", "calories", "rounds", "variation"],
};

function metricLabel(metric: PRSupportingMetricKey, i18n: ReturnType<typeof useUiTranslations>) {
  switch (metric) {
    case "reps": return i18n("reps702045f");
    case "sets": return i18n("sets2ab262f");
    case "load_kg": return `${i18n("semanticLoad")} (${i18n("kg1389845")})`;
    case "duration_seconds": return `${i18n("time6c82e6d")} (${i18n("semanticSeconds")})`;
    case "distance_m": return i18n("meters6ad427c");
    case "calories": return i18n("semanticKilocalories");
    case "rounds": return i18n("roundsceeac4a");
    case "variation": return i18n("variation15920a4");
  }
}

function metricInputType(metric: PRSupportingMetricKey) {
  return NUMERIC_DETAIL_FIELDS.includes(metric) ? "number" : "text";
}

function rawMetrics(metrics: PRSupportingMetrics | undefined): Partial<Record<PRSupportingMetricKey, string>> {
  return Object.fromEntries(
    Object.entries(metrics ?? {}).map(([key, value]) => [key, String(value)]),
  ) as Partial<Record<PRSupportingMetricKey, string>>;
}

function submitMetrics(raw: Partial<Record<PRSupportingMetricKey, string>>): PRSupportingMetrics {
  return Object.entries(raw).reduce<PRSupportingMetrics>((metrics, [key, value]) => {
    const metric = key as PRSupportingMetricKey;
    const normalized = value.trim();
    if (!normalized) return metrics;

    if (NUMERIC_DETAIL_FIELDS.includes(metric)) {
      const numeric = Number(normalized);
      if (Number.isFinite(numeric)) {
        metrics[metric as Exclude<PRSupportingMetricKey, "variation">] = numeric as never;
      }
    } else {
      metrics[metric as "variation"] = normalized;
    }

    return metrics;
  }, {});
}

function secondsToTimeFields(totalSeconds: number): TimeFields {
  const h = Math.floor(totalSeconds / 3600);
  const rem1 = totalSeconds - h * 3600;
  const m = Math.floor(rem1 / 60);
  const rem2 = rem1 - m * 60;
  const s = Math.floor(rem2);
  const ms = Math.round((rem2 - s) * 1000);
  return {
    hours: h > 0 ? String(h) : "",
    minutes: String(m),
    seconds: String(s),
    milliseconds: ms > 0 ? String(ms) : "",
  };
}

function timeFieldsToSeconds(t: TimeFields): number {
  const h = parseInt(t.hours || "0", 10) || 0;
  const m = parseInt(t.minutes || "0", 10) || 0;
  const s = parseInt(t.seconds || "0", 10) || 0;
  const ms = parseInt(t.milliseconds || "0", 10) || 0;
  return h * 3600 + m * 60 + s + ms / 1000;
}

export function PRFormModal({
  pr,
  onClose,
}: {
  pr?: PRRecord | null;
  onClose: () => void;
}) {
  const i18n = useUiTranslations();
  const UNITS: { value: PRUnit; label: string }[] = [
    { value: "kg", label: i18n("kg1389845") },
    { value: "reps", label: i18n("reps702045f") },
    { value: "mins_secs", label: i18n("time6c82e6d") },
    { value: "m", label: i18n("meters6ad427c") },
    { value: "kcals", label: i18n("kcalb78ae8a") },
    { value: "sets", label: i18n("sets2ab262f") },
  ];
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const isEdit = Boolean(pr);
  const titleId = useId();
  const dialogRef = useModalFocusTrap<HTMLDivElement>(onClose);

  const [name, setName] = useState(pr?.name ?? "");
  const [score, setScore] = useState(pr ? String(pr.current_score) : "");
  const [unit, setUnit] = useState<PRUnit>(pr?.unit ?? "kg");
  const [timeFields, setTimeFields] = useState<TimeFields>(() =>
    pr?.unit === "mins_secs"
      ? secondsToTimeFields(Number(pr.current_score))
      : { hours: "", minutes: "", seconds: "", milliseconds: "" },
  );
  const [higherIsBetter, setHigherIsBetter] = useState(pr?.higher_is_better ?? false);
  const [beatenOn, setBeatenOn] = useState(pr?.beaten_on ?? todayIso());
  const [details, setDetails] = useState<Partial<Record<PRSupportingMetricKey, string>>>(() => rawMetrics(pr?.supporting_metrics));
  const [detailToAdd, setDetailToAdd] = useState<PRSupportingMetricKey | "">("");
  const [notes, setNotes] = useState(pr?.notes ?? "");
  const [error, setError] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: async () => {
      if (!tokens) throw new Error(i18n("notAuthenticated0c91acb"));
      const current_score =
        unit === "mins_secs" ? timeFieldsToSeconds(timeFields) : parseFloat(score);
      const params = {
        name: name.trim(),
        current_score,
        unit,
        higher_is_better: higherIsBetter,
        beaten_on: beatenOn,
        supporting_metrics: submitMetrics(details),
        notes: notes.trim() || null,
      };
      if (isEdit && pr) {
        return updatePR(tokens.access_token, pr.id, params);
      }
      return createPR(tokens.access_token, params);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["prs"] });
      if (pr) void queryClient.invalidateQueries({ queryKey: ["prs", pr.id, "history"] });
      void queryClient.invalidateQueries({ queryKey: ["landing"] });
      onClose();
    },
    onError: (err) => {
      setError(err instanceof Error ? localizeError(err, i18n) : i18n("failedToSave3d4146c"));
    },
  });

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const scoreValid =
      unit === "mins_secs"
        ? timeFieldsToSeconds(timeFields) > 0
        : Boolean(score);
    if (!name.trim() || !scoreValid) return;
    setError(null);
    mutation.mutate();
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center p-4 sm:items-center"
      style={{ background: "rgba(0,0,0,0.5)" }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        className="w-full max-w-md rounded-[2rem] p-6 outline-none"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <h2 id={titleId} className="text-xl font-semibold" style={{ color: "var(--text)" }}>
          {isEdit ? i18n("updatePr71b8cf3") : i18n("newPr1c0d9f2")}
        </h2>

        <form className="mt-5 space-y-4" onSubmit={handleSubmit}>
          <div className="space-y-1.5">
            <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
              {i18n("exerciseName9a5c1af")}
            </label>
            <input
              className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={i18n("eGBackSquat1rm675304b")}
              required
              autoFocus
            />
          </div>

          <div className="space-y-1.5">
            <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
              {i18n("unitf6b935a")}
            </label>
            <select
              className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={unit}
              onChange={(e) => {
                const next = e.target.value as PRUnit;
                setUnit(next);
                if (next === "mins_secs") setHigherIsBetter(false);
                else setHigherIsBetter(true);
              }}
            >
              {UNITS.map((u) => (
                <option key={u.value} value={u.value}>{u.label}</option>
              ))}
            </select>
          </div>

          {unit === "mins_secs" ? (
            <div className="space-y-1.5">
              <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
                {i18n("time6c82e6d")}
              </label>
              <div className="grid grid-cols-4 gap-2">
                {(
                  [
                    { key: "hours", placeholder: "0", label: i18n("h27d5482") },
                    { key: "minutes", placeholder: "0", label: i18n("minb6c935d") },
                    { key: "seconds", placeholder: "0", label: i18n("sec920a25e") },
                    { key: "milliseconds", placeholder: "0", label: i18n("ms26cc321") },
                  ] as const
                ).map(({ key, placeholder, label }) => (
                  <div key={key} className="flex flex-col items-center gap-1">
                    <input
                      className="w-full rounded-xl px-2 py-2.5 text-sm text-center outline-none"
                      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                      type="number"
                      inputMode="numeric"
                      min="0"
                      max={key === "minutes" || key === "seconds" ? "59" : key === "milliseconds" ? "999" : undefined}
                      value={timeFields[key]}
                      placeholder={placeholder}
                      onChange={(e) => setTimeFields((prev) => ({ ...prev, [key]: e.target.value }))}
                    />
                    <span className="text-[10px] font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
                      {label}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          ) : (
            <div className="space-y-1.5">
              <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
                {i18n("score489f487")}
              </label>
              <input
                className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                type="number"
                step="any"
                min="0"
                value={score}
                onChange={(e) => setScore(e.target.value)}
                placeholder="0"
                required
              />
            </div>
          )}

          <div className="space-y-1.5">
            <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
              {i18n("dateAchieved8e4464d")}
            </label>
            <input
              className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              type="date"
              value={beatenOn}
              onChange={(e) => setBeatenOn(e.target.value)}
              required
            />
          </div>

          <div className="space-y-2">
            {Object.keys(details).length > 0 && (
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                {(Object.keys(details) as PRSupportingMetricKey[]).map((metric) => (
                  <div key={metric} className="space-y-1">
                    <label className="block text-xs font-semibold" style={{ color: "var(--muted)" }}>{metricLabel(metric, i18n)}</label>
                    <div className="flex gap-1.5">
                      <input
                        className="min-w-0 flex-1 rounded-xl px-3 py-2.5 text-sm outline-none"
                        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                        type={metricInputType(metric)}
                        inputMode={metricInputType(metric) === "number" ? "decimal" : undefined}
                        min={metricInputType(metric) === "number" ? "0" : undefined}
                        step={metric === "reps" || metric === "sets" || metric === "rounds" ? "1" : "any"}
                        value={details[metric] ?? ""}
                        onChange={(event) => setDetails((current) => ({ ...current, [metric]: event.target.value }))}
                      />
                      <button type="button" onClick={() => setDetails((current) => {
                        const next = { ...current };
                        delete next[metric];
                        return next;
                      })} className="w-10 rounded-xl text-sm font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }} aria-label={i18n("deletef6fdbe4")} title={i18n("deletef6fdbe4")}>×</button>
                    </div>
                  </div>
                ))}
              </div>
            )}
            {DETAIL_OPTIONS[unit].filter((metric) => !(metric in details)).length > 0 && (
              <select className="w-full rounded-xl px-4 py-2.5 text-sm outline-none" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }} value={detailToAdd} onChange={(event) => {
                const metric = event.target.value as PRSupportingMetricKey;
                if (metric) setDetails((current) => ({ ...current, [metric]: "" }));
                setDetailToAdd("");
              }}>
                <option value="">{`${i18n("add61cc55a")} ${i18n("detail7c9a7c0")}`}</option>
                {DETAIL_OPTIONS[unit].filter((metric) => !(metric in details)).map((metric) => <option key={metric} value={metric}>{metricLabel(metric, i18n)}</option>)}
              </select>
            )}
          </div>

          <div className="space-y-1.5">
            <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>{i18n("notesOptional4d56ca9")}</label>
            <textarea className="min-h-24 w-full resize-y rounded-xl px-4 py-2.5 text-sm outline-none" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }} value={notes} onChange={(event) => setNotes(event.target.value)} maxLength={2000} />
          </div>

          <label className="flex items-center gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={higherIsBetter}
              onChange={(e) => setHigherIsBetter(e.target.checked)}
              className="rounded"
            />
            <span className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
              {i18n("higherScoreIsBetter33060b7")}
            </span>
          </label>

          {error && (
            <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{error}</p>
          )}

          <div className="flex gap-3 pt-2">
            <button
              type="submit"
              disabled={mutation.isPending}
              className="flex-1 rounded-xl py-2.5 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {mutation.isPending ? i18n("saving56a2285") : isEdit ? i18n("updatePr71b8cf3") : i18n("addPr24c8c6f")}
            </button>
            <button
              type="button"
              onClick={onClose}
              className="rounded-xl px-5 py-2.5 text-sm font-semibold"
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
            >
              {i18n("cancel77dfd21")}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
