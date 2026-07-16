"use client";



import {useUiTranslations} from "@/i18n/ui";
import React from "react";

import type { TimerSegment } from "@/api/executions";

type Props = {
  segment: TimerSegment;
  elapsed: number;
  remaining: number | null;
  isExpired: boolean;
};

function formatTime(totalSeconds: number): string {
  const absSeconds = Math.abs(totalSeconds);
  const h = Math.floor(absSeconds / 3600);
  const m = Math.floor((absSeconds % 3600) / 60);
  const s = absSeconds % 60;
  const sign = totalSeconds < 0 ? "-" : "";

  if (h > 0) {
    return `${sign}${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  }
  return `${sign}${m}:${String(s).padStart(2, "0")}`;
}

export function TimerDisplay({ segment, elapsed, remaining, isExpired }: Props) {
  const i18n = useUiTranslations();
  const isNoTimer = segment.kind === "no_timer" || segment.kind === "manual";

  const displayValue = isNoTimer
    ? null
    : segment.kind === "countup"
      ? formatTime(elapsed)
      : remaining !== null
        ? formatTime(remaining)
        : formatTime(elapsed);

  const accentColor = isExpired
    ? "var(--danger)"
    : "var(--accent, var(--primary))";

  return (
    <div className="flex flex-col items-center gap-2 py-4">
      {/* Segment label */}
      <div
        className="text-sm font-semibold uppercase tracking-widest"
        style={{ color: "var(--muted)" }}
      >
        {segment.label}
      </div>

      {/* Rounds indicator */}
      {segment.total_rounds !== null && (
        <div className="flex items-center gap-1.5">
          {Array.from({ length: segment.total_rounds }, (_, i) => (
            <span
              key={i}
              className="h-1.5 w-1.5 rounded-full transition-colors"
              style={{
                background:
                  i + 1 === segment.round
                    ? accentColor
                    : i + 1 < (segment.round ?? 0)
                      ? "var(--dim)"
                      : "var(--border)",
              }}
            />
          ))}
        </div>
      )}

      {/* Main time display */}
      {displayValue !== null ? (
        <div
          className="font-mono text-7xl font-bold tabular-nums leading-none transition-colors"
          style={{ color: isExpired ? "var(--danger)" : "var(--text)" }}
        >
          {displayValue}
        </div>
      ) : (
        <div
          className="text-3xl font-semibold"
          style={{ color: "var(--muted)" }}
        >
          {segment.kind === "manual" ? i18n("manual4e836fd") : "—"}
        </div>
      )}

      {/* Format hint */}
      <div className="text-xs" style={{ color: "var(--dim)" }}>
        {segment.format}
        {segment.kind === "countup" && segment.duration_seconds
          ? i18n("capa8fba29") + (formatTime(segment.duration_seconds))
          : ""}
      </div>
    </div>
  );
}
