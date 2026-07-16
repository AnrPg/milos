"use client";




import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";

import type { ScaleLevel } from "@/api/workouts";
import { useWorkoutCreationStore } from "@/stores/workout-creation";

import { PreviewSection } from "./PreviewSection";

type Props = {
  scaleLevels: ScaleLevel[];
  mobile?: boolean;
};

export function RightPanel({ scaleLevels, mobile = false }: Props) {
  const i18n = useUiTranslations();
  const { sections, rightCollapsed, setRightCollapsed } = useWorkoutCreationStore();
  const [activeScale, setActiveScale] = useState<string | null>(null);

  if (!mobile && rightCollapsed) {
    return (
      <div
        className="flex w-10 shrink-0 cursor-pointer flex-col items-center justify-center"
        style={{ background: "var(--panel)", borderLeft: "1px solid var(--dim)" }}
        onClick={() => setRightCollapsed(false)}
      >
        <span
          className="text-xs font-bold uppercase tracking-widest"
          style={{
            writingMode: "vertical-rl",
            transform: "rotate(180deg)",
            color: "var(--muted)",
          }}
        >
          {i18n("previewf1fbb2b")}
        </span>
        <span className="mt-2 text-xs" style={{ color: "var(--muted)" }}>
          &lt;
        </span>
      </div>
    );
  }

  const activeScales = scaleLevels.filter((scaleLevel) =>
    sections.some((section) =>
      section.exercises.some((exercise) =>
        exercise.variations.some((variation) => variation.scaleLevelSlug === scaleLevel.slug),
      ),
    ),
  );

  return (
    <div
      className={"flex " + (mobile ? "w-full" : "w-72 shrink-0") + " flex-col overflow-hidden"}
      style={{ background: "var(--panel)", borderLeft: mobile ? "none" : "1px solid var(--dim)" }}
    >
      <div className="flex shrink-0 items-center justify-between px-4 py-3">
        <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          {i18n("previewf1fbb2b")}
        </span>
        {!mobile ? (
          <button onClick={() => setRightCollapsed(true)} className="text-xs" style={{ color: "var(--dim)" }}>
            &gt;
          </button>
        ) : null}
      </div>

      <div className="flex shrink-0 flex-wrap gap-1 px-4 pb-3">
        <button
          onClick={() => setActiveScale(null)}
          className="rounded-2xl px-3 py-1 text-xs font-semibold transition-colors"
          style={{
            background: activeScale === null ? "var(--lime)" : "var(--card)",
            color: activeScale === null ? "var(--bg)" : "var(--muted)",
          }}
        >
          {i18n("base077fe9c")}
        </button>
        {activeScales.map((scaleLevel) => (
          <button
            key={scaleLevel.slug}
            onClick={() => setActiveScale(scaleLevel.slug)}
            className="rounded-2xl px-3 py-1 text-xs font-semibold transition-colors"
            style={{
              background: activeScale === scaleLevel.slug ? "var(--lime)" : "var(--card)",
              color: activeScale === scaleLevel.slug ? "var(--bg)" : "var(--muted)",
            }}
          >
            {scaleLevel.label}
          </button>
        ))}
      </div>

      <div className="flex-1 overflow-y-auto px-4">
        {sections.length === 0 ? (
          <p className="py-4 text-center text-xs" style={{ color: "var(--dim)" }}>
            {i18n("addSectionsToSeePreviewef9458d")}
          </p>
        ) : (
          sections.map((section) => (
            <PreviewSection
              key={section.localId}
              section={section}
              activeScale={activeScale}
              scaleLevels={scaleLevels}
            />
          ))
        )}
      </div>
    </div>
  );
}
