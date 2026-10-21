"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchMyWorkoutScaling, myScalingKey } from "@/api/scaling";
import { ScalingChangeLine } from "@/components/scaling/ScalingParts";

/**
 * «Προσαρμογή από τον coach» (ADR-174) on the member's workout card. The API
 * returns only a coach-approved adaptation, so this renders nothing at all
 * for everyone else (no empty slot, no hint that a suggestion exists).
 */
export function MyWorkoutScaling({
  token,
  workoutId,
  className = "",
}: {
  token: string;
  workoutId: string;
  className?: string;
}) {
  const t = useTranslations("Scaling");
  const query = useQuery({
    queryKey: myScalingKey(workoutId),
    queryFn: () => fetchMyWorkoutScaling(token, workoutId),
    staleTime: 60_000,
  });
  const scaling = query.data;
  if (!scaling) return null;
  const items = scaling.items ?? [];

  return (
    <section
      className={`rounded-2xl p-3 ${className}`}
      style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}
      aria-labelledby={`scaling-${scaling.id}`}
      data-testid="my-workout-scaling"
    >
      <h3 id={`scaling-${scaling.id}`} className="text-sm font-bold" style={{ color: "var(--text)" }}>
        {t("member.title")}
      </h3>
      {scaling.scale_level_label ?? scaling.scale_level_slug ? (
        <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }}>
          {t("member.scaleLevel", { level: scaling.scale_level_label ?? scaling.scale_level_slug ?? "" })}
        </p>
      ) : null}
      {items.length > 0 ? (
        <ul className="mt-2 space-y-2">
          {items.map((item) => (
            <li key={`${item.section_id ?? ""}-${item.exercise_id}`}>
              <ScalingChangeLine item={item} />
            </li>
          ))}
        </ul>
      ) : null}
      {scaling.coach_note ? (
        <p className="mt-2 whitespace-pre-wrap text-sm" data-user-text style={{ color: "var(--text)" }}>
          «{scaling.coach_note}»
        </p>
      ) : null}
      <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("member.disclosure")}</p>
    </section>
  );
}
