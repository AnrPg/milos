"use client";

import { useUiTranslations } from "@/i18n/ui";
import React from "react";

import type { TimerSegment } from "@/api/executions";
import { segmentLimitMs } from "@/lib/timer-engine";
import { getFormatLabels, type SectionFormat } from "@/types/workout";

import { formatClock } from "./TimerDisplay";

type SectionSummary = { id: string; name: string; format: string; timedMs: number; open: boolean };

/** One row per workout section, in order, with how long its timed parts run. */
export function summarizeSections(segments: TimerSegment[]): SectionSummary[] {
  const sections: SectionSummary[] = [];

  for (const segment of segments) {
    if (segment.between_sections) continue;
    let summary = sections.at(-1);
    if (summary?.id !== segment.section_id) {
      summary = { id: segment.section_id, name: segment.section_name, format: segment.format, timedMs: 0, open: false };
      sections.push(summary);
    }

    const limit = segmentLimitMs(segment);
    if (limit === null || segment.kind === "countup") summary.open = true;
    summary.timedMs += limit ?? 0;
  }

  return sections;
}

export function ReadyScreen({
  segments,
  soundControl,
  onTestSound,
  onStart,
}: {
  segments: TimerSegment[];
  soundControl: React.ReactNode;
  onTestSound: () => void;
  onStart: () => void;
}) {
  const i18n = useUiTranslations();
  const formatLabels = getFormatLabels(i18n);
  const sections = summarizeSections(segments);

  return (
    <div
      className="flex h-dvh flex-col"
      style={{ background: "var(--bg)", color: "var(--text)" }}
    >
      <div className="flex items-center justify-end px-4 py-3">{soundControl}</div>

      <div className="flex-1 overflow-y-auto px-5">
        <h1 className="text-3xl font-bold">{i18n("readyTitle")}</h1>
        <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>
          {i18n("readySubtitle")}
        </p>

        <ol className="mt-6 flex flex-col gap-2">
          {sections.map((section, index) => (
            <li
              key={section.id}
              className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
              <span className="min-w-0">
                <span className="block truncate text-sm font-semibold">
                  {index + 1}. {section.name || formatLabels[section.format as SectionFormat] || section.format}
                </span>
                <span className="block text-xs" style={{ color: "var(--muted)" }}>
                  {formatLabels[section.format as SectionFormat] ?? section.format}
                </span>
              </span>
              <span className="shrink-0 text-sm font-semibold tabular-nums" style={{ color: "var(--text-soft)" }}>
                {section.timedMs > 0 && !section.open
                  ? formatClock(Math.round(section.timedMs / 1000))
                  : i18n("openDurationLabel")}
              </span>
            </li>
          ))}
        </ol>
      </div>

      <div
        className="flex flex-col gap-3 px-5 pt-4"
        style={{ paddingBottom: "max(1.25rem, env(safe-area-inset-bottom))" }}
      >
        <button
          type="button"
          onClick={onTestSound}
          className="min-h-12 rounded-2xl text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
        >
          {i18n("testSoundLabel")}
        </button>
        <button
          type="button"
          onClick={onStart}
          autoFocus
          className="min-h-16 rounded-2xl text-xl font-bold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {i18n("start952f375")}
        </button>
      </div>
    </div>
  );
}
