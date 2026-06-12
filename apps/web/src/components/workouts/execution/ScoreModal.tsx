"use client";

import React, { useState } from "react";

import type { SectionScore } from "@/api/executions";
import type { TimerSegment } from "@/api/executions";

type Props = {
  segment: TimerSegment;
  existingScore: SectionScore | undefined;
  onSave: (score: SectionScore) => void;
  onClose: () => void;
  isSaving?: boolean;
};

export function ScoreModal({
  segment,
  existingScore,
  onSave,
  onClose,
  isSaving = false,
}: Props) {
  const scoreType = segment.score_config?.type ?? "time";
  const unit = segment.score_config?.unit ?? "";
  const label = segment.score_config?.label ?? "Score";

  const defaultValue = scoreType === "pass_fail" ? "Pass" : "";
  const [value, setValue] = useState(
    existingScore?.value != null ? String(existingScore.value) : defaultValue,
  );

  function handleSave() {
    if (isSaving) return;
    const trimmed = value.trim();
    if (!trimmed) return;
    onSave({ section_id: segment.section_id, value: trimmed, unit: unit || undefined });
  }

  const inputMode =
    scoreType === "reps" || scoreType === "load" ? "decimal" : undefined;

  const placeholder =
    scoreType === "time"
      ? "mm:ss or seconds"
      : scoreType === "reps"
        ? "e.g. 15"
        : scoreType === "load"
          ? "e.g. 80 kg"
          : "e.g. 4 rounds + 3 reps";

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center p-4 sm:items-center">
      <div
        className="absolute inset-0"
        style={{ background: "rgba(0,0,0,0.7)" }}
      />
      <div
        className="relative z-10 w-full max-w-sm rounded-2xl p-6"
        style={{ background: "var(--panel, #111118)", border: "1px solid var(--border, #2a2a3a)" }}
      >
        <div
          className="mb-1 text-xs font-semibold uppercase tracking-widest"
          style={{ color: "var(--muted, #8888aa)" }}
        >
          {segment.section_name}
        </div>
        <div className="mb-4 text-lg font-bold" style={{ color: "var(--text, #f0edf8)" }}>
          {label}
        </div>
        <p className="mb-3 text-xs" style={{ color: "var(--muted, #8888aa)" }}>
          The measured score is prefilled. Change it only if you want to override it.
        </p>

        {scoreType === "pass_fail" ? (
          <div className="flex gap-3">
            {(["Pass", "Fail"] as const).map((option) => (
              <button
                key={option}
                type="button"
                onClick={() => setValue(option)}
                className="flex-1 rounded-2xl py-4 text-lg font-bold transition-colors"
                style={
                  value === option
                    ? option === "Pass"
                      ? {
                          background: "color-mix(in srgb, #22c55e 20%, transparent)",
                          border: "2px solid #22c55e",
                          color: "#22c55e",
                        }
                      : {
                          background: "color-mix(in srgb, #ef4444 20%, transparent)",
                          border: "2px solid #ef4444",
                          color: "#ef4444",
                        }
                    : {
                        background: "var(--bg, #0d0d14)",
                        border: "1px solid var(--dim, #3a3a4a)",
                        color: "var(--muted, #888)",
                      }
                }
              >
                {option}
              </button>
            ))}
          </div>
        ) : (
          <>
            <input
              autoFocus
              type="text"
              inputMode={inputMode}
              placeholder={placeholder}
              value={value}
              onChange={(e) => setValue(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && handleSave()}
              className="w-full rounded-xl px-4 py-3 text-base outline-none focus:ring-2"
              style={{
                background: "var(--card, #151520)",
                border: "1px solid var(--border, #2a2a3a)",
                color: "var(--text, #f0edf8)",
              }}
            />
            {unit && (
              <div className="mt-1 text-right text-xs" style={{ color: "var(--muted, #8888aa)" }}>
                {unit}
              </div>
            )}
          </>
        )}

        <div className="mt-4 flex gap-3">
          <button
            onClick={onClose}
            disabled={isSaving}
            className="flex-1 rounded-xl py-2.5 text-sm font-semibold"
            style={{
              background: "var(--card, #151520)",
              border: "1px solid var(--border, #2a2a3a)",
              color: "var(--muted, #8888aa)",
            }}
          >
            Back
          </button>
          <button
            onClick={handleSave}
            disabled={!value.trim() || isSaving}
            className="flex-1 rounded-xl py-2.5 text-sm font-semibold disabled:opacity-30"
            style={{ background: "var(--accent, #9c799c)", color: "var(--text, #f0edf8)" }}
          >
            {isSaving ? "Saving…" : "Save"}
          </button>
        </div>
      </div>
    </div>
  );
}
