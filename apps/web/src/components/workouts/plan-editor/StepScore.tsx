"use client";

import { useTranslations } from "next-intl";
import type { KeyboardEvent } from "react";

import { scoreLabelKey, scoresFor } from "@/lib/structured-plan";
import { focusKey, usePlanEditorStore, type PlanEditorSection } from "@/stores/structured-plan";

import { useKeyText } from "./plan-text";

/** A scale level of the workout (e.g. `{ key: "rx", label: "Rx" }`), for per-level notes. */
export type PlanLevel = { key: string; label: string };

// The border colour lives in the class, not the inline style, so the focus colour can win over it.
export const noteFieldClass =
  "w-full rounded-lg border border-[var(--control-border)] px-2.5 py-1.5 text-sm outline-none focus:border-[var(--primary)] focus:shadow-[0_0_0_1px_var(--primary)]";
export const noteFieldStyle = { background: "var(--control-bg)", color: "var(--text)" } as const;

/**
 * Step Σκορ: the flow's score (the usual one already chosen; ← → change it),
 * the section note, and quiet per-level notes.
 */
export function StepScore({ section, levels = [] }: { section: PlanEditorSection; levels?: PlanLevel[] }) {
  const t = useTranslations("PlanEditor");
  const k = useKeyText();
  const setScore = usePlanEditorStore((s) => s.setScore);
  const setNote = usePlanEditorStore((s) => s.setNote);
  const setLevelNote = usePlanEditorStore((s) => s.setLevelNote);
  const setFocus = usePlanEditorStore((s) => s.setFocus);
  const { plan } = section;
  const options = scoresFor(plan);
  const current = options.includes(plan.score as (typeof options)[number]) ? plan.score : options[0];

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if ((e.key !== "ArrowRight" && e.key !== "ArrowLeft") || e.altKey) return;
    e.preventDefault();
    const i = options.indexOf(current as (typeof options)[number]);
    const next = options[(i + (e.key === "ArrowRight" ? 1 : -1) + options.length) % options.length];
    setScore(section.id, next);
    setFocus(focusKey.score(section.id));
  };

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2 text-sm font-semibold">
        <span id={`score-${section.id}`}>{t("score")}</span>
        <div role="radiogroup" aria-labelledby={`score-${section.id}`} onKeyDown={onKeyDown} className="flex flex-wrap gap-1.5">
          {options.map((o) => {
            const on = o === current;
            return (
              <button
                key={o}
                type="button"
                role="radio"
                aria-checked={on}
                data-testid={`plan-score-${o}`}
                data-k={on ? focusKey.score(section.id) : undefined}
                tabIndex={on ? 0 : -1}
                onClick={() => setScore(section.id, o)}
                className="rounded-full border px-3 py-1 text-sm"
                style={on ? { background: "var(--primary)", borderColor: "var(--primary)", color: "var(--primary-contrast)" } : { background: "var(--card)", borderColor: "var(--border)", color: "var(--text)" }}
              >
                {k(scoreLabelKey(o))}
              </button>
            );
          })}
        </div>
      </div>
      <p className="text-xs" style={{ color: "var(--muted)" }}>{t("scoreHelp")}</p>
      <input
        data-testid="plan-section-note"
        data-k={focusKey.sectionNote(section.id)}
        value={plan.note ?? ""}
        placeholder={t("sectionNote")}
        aria-label={t("sectionNote")}
        onChange={(e) => setNote({ kind: "section", sectionId: section.id }, e.target.value)}
        className={noteFieldClass}
        style={noteFieldStyle}
      />
      {levels.length ? (
        <fieldset className="flex flex-col gap-1.5">
          <legend className="mb-1 text-xs" style={{ color: "var(--muted)" }}>{t("levelNotes")}</legend>
          {levels.map((level) => (
            <input
              key={level.key}
              data-testid={`plan-level-note-${level.key}`}
              data-k={`lnote:${section.id}:${level.key}`}
              value={plan.levelNotes?.[level.key] ?? ""}
              placeholder={t("levelNote", { level: level.label })}
              aria-label={t("levelNote", { level: level.label })}
              onChange={(e) => setLevelNote(section.id, level.key, e.target.value)}
              className={noteFieldClass}
              style={{ ...noteFieldStyle, borderStyle: "dashed" }}
            />
          ))}
        </fieldset>
      ) : null}
    </div>
  );
}
