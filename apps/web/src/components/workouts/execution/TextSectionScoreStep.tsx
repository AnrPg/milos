"use client";

import { useState } from "react";

import { useUiTranslations } from "@/i18n/ui";
import { useScoreKindLabels } from "@/components/workouts/creation/SectionScoringField";
import {
  SCORE_KIND_UNITS,
  parseMetricValue,
  type TextSection,
  type TextSectionResult,
} from "@/lib/text-sections";

import { formatClock } from "./TimerDisplay";

/** A result as the review shows it (a section score, keyed per metric). */
export type TextSectionScoreView = {
  section_id: string;
  section_key: string;
  section_name: string;
  value: number | string;
  unit?: string;
  score_type?: string;
};

const fieldKey = (sectionId: string, metricKey: string) => `${sectionId}:${metricKey}`;

/**
 * ADR-180: after a workout written in text sections, one named field for
 * each score the coach set («Rounds», «Top set»…), grouped by section. Time
 * is typed as m:ss; everything is optional.
 */
export function TextSectionScoreStep({
  sections,
  initial,
  onBack,
  backLabel,
  onNext,
  onSkip,
}: {
  sections: TextSection[];
  initial: TextSectionResult[];
  onBack: (() => void) | null;
  backLabel?: string;
  onNext: (results: TextSectionResult[], views: TextSectionScoreView[]) => void;
  onSkip: () => void;
}) {
  const i18n = useUiTranslations();
  const kindLabels = useScoreKindLabels();
  const scored = sections.filter((section) => section.metrics.length > 0);
  const [values, setValues] = useState<Record<string, string>>(() =>
    Object.fromEntries(
      initial.map((result) => {
        const metric = scored.find((s) => s.id === result.section_id)?.metrics.find((m) => m.key === result.metric_key);
        const text = metric?.kind === "time" ? formatClock(result.value) : String(result.value);
        return [fieldKey(result.section_id, result.metric_key), text];
      }),
    ),
  );

  const invalid = new Set(
    scored.flatMap((section) =>
      section.metrics
        .filter((metric) => {
          const text = values[fieldKey(section.id, metric.key)] ?? "";
          return text.trim() !== "" && parseMetricValue(text, metric.kind) === null;
        })
        .map((metric) => fieldKey(section.id, metric.key)),
    ),
  );

  function submit() {
    const results: TextSectionResult[] = [];
    const views: TextSectionScoreView[] = [];
    scored.forEach((section, index) => {
      const sectionTitle = section.title || i18n("textSectionNumber", { number: index + 1 });
      for (const metric of section.metrics) {
        const value = parseMetricValue(values[fieldKey(section.id, metric.key)] ?? "", metric.kind);
        if (value === null) continue;
        results.push({ section_id: section.id, metric_key: metric.key, value });
        views.push({
          section_id: section.id,
          section_key: fieldKey(section.id, metric.key),
          section_name: `${sectionTitle} · ${metric.label}`,
          value: metric.kind === "time" ? formatClock(value) : value,
          unit: metric.kind === "time" ? undefined : (SCORE_KIND_UNITS[metric.kind] ?? undefined),
          score_type: metric.kind,
        });
      }
    });
    onNext(results, views);
  }

  return (
    <div className="flex h-dvh flex-col" style={{ background: "var(--bg)", color: "var(--text)" }}>
      <div className="flex items-center justify-between px-5 pt-8 pb-2">
        <div>
          {onBack ? (
            <button type="button" onClick={onBack} className="text-sm" style={{ color: "var(--dim)" }}>
              {backLabel ?? i18n("backc32ae9f")}
            </button>
          ) : null}
        </div>
        <button type="button" onClick={onSkip} className="text-sm font-semibold" style={{ color: "var(--dim)" }}>
          {i18n("skip10b7bbe")}
        </button>
      </div>

      <div className="flex flex-col items-center gap-2 px-6 pt-4 pb-6">
        <div className="text-4xl" aria-hidden="true">
          🏁
        </div>
        <h2 className="text-center text-xl font-bold">{i18n("logYourScoresaeffd3b")}</h2>
        <p className="max-w-xs text-center text-sm" style={{ color: "var(--muted)" }}>
          {i18n("textSectionResultsHint")}
        </p>
      </div>

      <div className="flex-1 space-y-3 overflow-y-auto px-4 pb-4">
        {scored.map((section) => {
          const number = sections.indexOf(section) + 1;
          return (
            <fieldset
              key={section.id}
              className="rounded-2xl p-4"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
              <legend className="sr-only">{section.title || i18n("textSectionNumber", { number })}</legend>
              <p aria-hidden="true" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                {section.title || i18n("textSectionNumber", { number })}
              </p>
              <div className="mt-2 space-y-2">
                {section.metrics.map((metric) => {
                  const key = fieldKey(section.id, metric.key);
                  const isTime = metric.kind === "time";
                  const wrong = invalid.has(key);
                  return (
                    <label key={metric.key} className="flex items-center justify-between gap-4">
                      <span className="min-w-0 text-sm" style={{ color: "var(--text-soft)" }}>
                        {metric.label}
                      </span>
                      <span className="flex shrink-0 items-center gap-1.5">
                        <input
                          type="text"
                          inputMode={isTime ? "numeric" : "decimal"}
                          placeholder={isTime ? "m:ss" : "—"}
                          aria-invalid={wrong}
                          aria-label={`${section.title || i18n("textSectionNumber", { number })} · ${metric.label}`}
                          className="w-24 rounded-xl px-3 py-2 text-end text-sm font-bold outline-none"
                          style={{
                            background: "var(--bg)",
                            border: `1px solid ${wrong ? "var(--danger)" : values[key] ? "var(--primary)" : "var(--border)"}`,
                            color: "var(--text)",
                          }}
                          value={values[key] ?? ""}
                          onChange={(event) => setValues((current) => ({ ...current, [key]: event.target.value }))}
                        />
                        <span className="w-10 shrink-0 text-xs" style={{ color: "var(--muted)" }}>
                          {isTime ? "" : kindUnitLabel(metric.kind, kindLabels)}
                        </span>
                      </span>
                    </label>
                  );
                })}
              </div>
            </fieldset>
          );
        })}
      </div>

      <div className="p-4 pt-0">
        <button
          type="button"
          disabled={invalid.size > 0}
          onClick={submit}
          className="w-full rounded-2xl py-3.5 text-base font-semibold disabled:opacity-40"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {i18n("next2f04eb1")}
        </button>
      </div>
    </div>
  );
}

/** The short unit after a field: kg, kcal, m; rounds and reps say their kind. */
function kindUnitLabel(kind: keyof typeof SCORE_KIND_UNITS, kindLabels: Record<string, string>) {
  const unit = SCORE_KIND_UNITS[kind];
  return kind === "rounds" || kind === "reps" ? kindLabels[kind] : (unit ?? "");
}
