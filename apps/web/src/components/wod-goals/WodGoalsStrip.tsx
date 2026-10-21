"use client";

import { useId, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useFormatter, useTranslations } from "next-intl";

import type { MemberWorkoutGoals } from "@/api/wod-goals";
import { AnatomyFigure } from "@/components/anatomy/AnatomyFigure";
import { AnatomyThumb } from "@/components/anatomy/AnatomyThumb";
import { Sheet, SheetButton } from "@/components/community/Sheet";
import { atlasHref } from "@/lib/anatomy/atlas";
import { goalHighlights, musclesByRole, summaryMuscleIds } from "@/lib/wod-goals/goals";

import { MuscleChip, RoleLegend, ToggleChip } from "./GoalChips";
import { useWorkoutGoals } from "./use-wod-goals";

/**
 * The member's goals strip (Q3) inside a workout card: fetches the
 * workout's visible goals and renders nothing while they are missing,
 * hidden, loading or failed, so the card never changes shape for them.
 */
export function WodGoalsStrip({ workoutId, className = "" }: { workoutId: string | null | undefined; className?: string }) {
  const goals = useWorkoutGoals(workoutId);
  return <WodGoalsStripView goals={goals.data?.goals ?? null} className={className} />;
}

export function WodGoalsStripView({ goals, className = "" }: { goals: MemberWorkoutGoals | null; className?: string }) {
  const t = useTranslations("WodGoals");
  const anatomy = useTranslations("Anatomy");
  const format = useFormatter();
  const [open, setOpen] = useState(false);
  if (!goals || (goals.muscles.length === 0 && goals.qualities.length === 0 && !goals.stimulus)) return null;

  const names = summaryMuscleIds(goals.muscles).map((id) => anatomy(`muscle.${id}`));
  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label={t("strip.open")}
        data-testid="wod-goals-strip"
        className={`flex w-full items-center gap-3 rounded-2xl px-3 py-2 text-start ${className}`}
        style={{ background: "var(--panel-raised, var(--panel))", border: "1px solid var(--border)" }}
      >
        {goals.muscles.length > 0 ? (
          <AnatomyThumb highlights={goalHighlights(goals.muscles, ["primary", "secondary"])} view="both" height={56} className="shrink-0" />
        ) : null}
        <span className="flex min-w-0 flex-1 flex-col gap-1">
          {names.length > 0 ? (
            <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>
              {t("strip.summary", { muscles: format.list(names) })}
            </span>
          ) : null}
          {goals.qualities.length > 0 ? (
            <span className="flex flex-wrap gap-1">
              {goals.qualities.slice(0, 3).map((quality) => (
                <span key={quality} className="rounded-full px-2 py-0.5 text-[11px] font-semibold" style={{ background: "var(--bg)", color: "var(--text-soft)" }}>
                  {anatomy(`quality.${quality}`)}
                </span>
              ))}
            </span>
          ) : null}
          {goals.stimulus ? (
            <span className="truncate text-xs" style={{ color: "var(--text-soft)" }}>{goals.stimulus}</span>
          ) : null}
        </span>
        <span aria-hidden="true" className="shrink-0 text-lg" style={{ color: "var(--dim)" }}>›</span>
      </button>
      {open ? <WodGoalsSheet goals={goals} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

/**
 * All the goals, stabilizers included, on the interactive figure. A muscle
 * opens the anatomy atlas on it (ADR-164); «Άτλαντας» opens it on the main one.
 */
export function WodGoalsSheet({ goals, onClose }: { goals: MemberWorkoutGoals; onClose: () => void }) {
  const t = useTranslations("WodGoals");
  const anatomy = useTranslations("Anatomy");
  const router = useRouter();
  const labelId = useId();
  return (
    <Sheet title={t("sheet.title")} labelId={labelId} onClose={onClose} footer={<SheetButton onClick={onClose}>{t("sheet.close")}</SheetButton>}>
      <div className="flex flex-col gap-4">
        {goals.muscles.length > 0 ? (
          <>
            <AnatomyFigure highlights={goalHighlights(goals.muscles)} view="both" interactive size="card" />
            <div className="flex flex-wrap items-center justify-between gap-2">
              <RoleLegend />
              <Link href={atlasHref(goals.muscles[0]?.id)} className="text-xs font-semibold" style={{ color: "var(--primary)" }} data-testid="wod-goals-atlas-link">
                {t("sheet.atlas")}
              </Link>
            </div>
            {musclesByRole(goals.muscles).map(([role, muscles]) => (
              <div key={role} className="flex flex-col gap-1">
                <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t(`legend.${role}`)}</p>
                <div className="flex flex-wrap gap-1.5">
                  {muscles.map((muscle) => (
                    <MuscleChip
                      key={muscle.id}
                      label={anatomy(`muscle.${muscle.id}`)}
                      role={muscle.role}
                      onPress={() => router.push(atlasHref(muscle.id))}
                      pressLabel={t("sheet.openInAtlas", { muscle: anatomy(`muscle.${muscle.id}`) })}
                    />
                  ))}
                </div>
              </div>
            ))}
          </>
        ) : null}
        {goals.qualities.length > 0 ? (
          <section className="flex flex-col gap-1">
            <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("qualities")}</p>
            <div className="flex flex-wrap gap-1.5">
              {goals.qualities.map((quality) => (
                <ToggleChip key={quality} pressed>{anatomy(`quality.${quality}`)}</ToggleChip>
              ))}
            </div>
          </section>
        ) : null}
        {goals.stimulus ? (
          <section className="flex flex-col gap-1">
            <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("stimulus")}</p>
            <p className="text-sm" style={{ color: "var(--text)" }}>{goals.stimulus}</p>
          </section>
        ) : null}
      </div>
    </Sheet>
  );
}
