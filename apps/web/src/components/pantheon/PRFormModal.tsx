"use client";

import { useEffect, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { createPR, updatePR, type PRRecord, type PRUnit } from "@/api/gamification";
import { useSession } from "@/components/session-provider";

const UNITS: { value: PRUnit; label: string }[] = [
  { value: "kg", label: "kg" },
  { value: "reps", label: "Reps" },
  { value: "mins_secs", label: "Time" },
  { value: "m", label: "Meters" },
  { value: "kcals", label: "Kcal" },
  { value: "sets", label: "Sets" },
];

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

type TimeFields = { hours: string; minutes: string; seconds: string; milliseconds: string };

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
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const isEdit = Boolean(pr);

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
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [onClose]);

  const mutation = useMutation({
    mutationFn: async () => {
      if (!tokens) throw new Error("Not authenticated");
      const current_score =
        unit === "mins_secs" ? timeFieldsToSeconds(timeFields) : parseFloat(score);
      const params = {
        name: name.trim(),
        current_score,
        unit,
        higher_is_better: higherIsBetter,
        beaten_on: beatenOn,
      };
      if (isEdit && pr) {
        return updatePR(tokens.access_token, pr.id, params);
      }
      return createPR(tokens.access_token, params);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["prs"] });
      void queryClient.invalidateQueries({ queryKey: ["landing"] });
      onClose();
    },
    onError: (err) => {
      setError(err instanceof Error ? err.message : "Failed to save.");
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
        className="w-full max-w-md rounded-[2rem] p-6"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <h2 className="text-xl font-semibold" style={{ color: "var(--text)" }}>
          {isEdit ? "Edit PR" : "New PR"}
        </h2>

        <form className="mt-5 space-y-4" onSubmit={handleSubmit}>
          <div className="space-y-1.5">
            <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
              Exercise name
            </label>
            <input
              className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Back Squat 1RM"
              required
              autoFocus
            />
          </div>

          <div className="space-y-1.5">
            <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
              Unit
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
                Time
              </label>
              <div className="grid grid-cols-4 gap-2">
                {(
                  [
                    { key: "hours", placeholder: "0", label: "h" },
                    { key: "minutes", placeholder: "0", label: "min" },
                    { key: "seconds", placeholder: "0", label: "sec" },
                    { key: "milliseconds", placeholder: "0", label: "ms" },
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
                Score
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
              Date achieved
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

          <label className="flex items-center gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={higherIsBetter}
              onChange={(e) => setHigherIsBetter(e.target.checked)}
              className="rounded"
            />
            <span className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
              Higher score is better
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
              {mutation.isPending ? "Saving…" : isEdit ? "Update PR" : "Add PR"}
            </button>
            <button
              type="button"
              onClick={onClose}
              className="rounded-xl px-5 py-2.5 text-sm font-semibold"
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
            >
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
