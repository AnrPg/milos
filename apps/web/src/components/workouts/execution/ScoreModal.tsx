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
        style={{ background: "var(--panel, var(--panel))", border: "1px solid var(--border)" }}
      >
        <div
          className="mb-1 text-xs font-semibold uppercase tracking-widest"
          style={{ color: "var(--muted)" }}
        >
          {segment.section_name}
        </div>
        <div className="mb-4 text-lg font-bold" style={{ color: "var(--text)" }}>
          {label}
        </div>
        <p className="mb-3 text-xs" style={{ color: "var(--muted)" }}>
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
                          background: "color-mix(in srgb, var(--success) 20%, transparent)",
                          border: "2px solid var(--success)",
                          color: "var(--success)",
                        }
                      : {
                          background: "color-mix(in srgb, var(--danger) 20%, transparent)",
                          border: "2px solid var(--danger)",
                          color: "var(--danger)",
                        }
                    : {
                        background: "var(--bg)",
                        border: "1px solid var(--dim)",
                        color: "var(--muted)",
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
                background: "var(--card, var(--panel-muted))",
                border: "1px solid var(--border)",
                color: "var(--text)",
              }}
            />
            {unit && (
              <div className="mt-1 text-right text-xs" style={{ color: "var(--muted)" }}>
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
              background: "var(--card, var(--panel-muted))",
              border: "1px solid var(--border)",
              color: "var(--muted)",
            }}
          >
            Back
          </button>
          <button
            onClick={handleSave}
            disabled={!value.trim() || isSaving}
            className="flex-1 rounded-xl py-2.5 text-sm font-semibold disabled:opacity-30"
            style={{ background: "var(--accent, var(--primary))", color: "var(--text)" }}
          >
            {isSaving ? "Saving…" : "Save"}
          </button>
        </div>
      </div>
    </div>
  );
}
