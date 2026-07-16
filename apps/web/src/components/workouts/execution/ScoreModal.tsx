"use client";





import {useUiTranslations} from "@/i18n/ui";
import React, { useId, useState } from "react";

import type { SectionScore } from "@/api/executions";
import type { TimerSegment } from "@/api/executions";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

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
  const i18n = useUiTranslations();
  const scoreType = segment.score_config?.type ?? "time";
  const unit = segment.score_config?.unit ?? "";
  const label = segment.score_config?.label ?? i18n("score489f487");

  const defaultValue = scoreType === "pass_fail" ? i18n("passd7cd56f") : "";
  const [value, setValue] = useState(
    existingScore?.value != null ? String(existingScore.value) : defaultValue,
  );
  const dialogRef = useModalFocusTrap<HTMLDivElement>(onClose);
  const titleId = useId();

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
      ? i18n("mmSsOrSeconds8fe060d")
      : scoreType === "reps"
        ? i18n("eG153cfcdb3")
        : scoreType === "load"
          ? i18n("eG80Kgde59a3f")
          : i18n("eG4Rounds3Reps688d025");

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center p-4 sm:items-center">
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
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
        <div id={titleId} className="mb-4 text-lg font-bold" style={{ color: "var(--text)" }}>
          {label}
        </div>
        <p className="mb-3 text-xs" style={{ color: "var(--muted)" }}>
          {i18n("theMeasuredScoreIsPrefilledChangeItOnly56e1bc0")}
        </p>

        {scoreType === "pass_fail" ? (
          <div className="flex gap-3">
            {([i18n("passd7cd56f"), i18n("fail2758e32")] as const).map((option) => (
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
            {i18n("backb52b36b")}
          </button>
          <button
            onClick={handleSave}
            disabled={!value.trim() || isSaving}
            className="flex-1 rounded-xl py-2.5 text-sm font-semibold disabled:opacity-30"
            style={{ background: "var(--accent, var(--primary))", color: "var(--text)" }}
          >
            {isSaving ? i18n("saving56a2285") : i18n("saveefc007a")}
          </button>
        </div>
      </div>
    </div>
  );
}
