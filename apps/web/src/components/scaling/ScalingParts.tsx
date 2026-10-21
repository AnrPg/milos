"use client";

import { useTranslations } from "next-intl";

import type { ScalingChange } from "@/api/scaling";

type ChangeItem = {
  change: ScalingChange;
  exercise_name?: string | null;
  suggested?: string | null;
  reason: string;
};

const REGIONS = ["shoulder", "elbow", "wrist", "neck", "back", "hip", "knee", "hamstring", "ankle", "chest", "core"] as const;

/** Body regions (ADR-124 canonical ids) in the reader's language; unknown ids stay as they are. */
export function useRegionLabel() {
  const t = useTranslations("Scaling");
  return (region: string) =>
    (REGIONS as readonly string[]).includes(region) ? t(`regions.${region as (typeof REGIONS)[number]}`) : region;
}

/** One approved or proposed change: «Back Squat → Box squat», with its reason under it. */
export function ScalingChangeLine({ item, suggested }: { item: ChangeItem; suggested?: string | null }) {
  const t = useTranslations("Scaling");
  const movement = item.exercise_name ?? "";
  const target = suggested ?? item.suggested ?? "";

  return (
    <span className="flex flex-col">
      <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
        {item.change === "skip"
          ? t("change.skip", { movement })
          : item.change === "substitute"
            ? t("change.substitute", { movement, target })
            : t("change.adjust", { movement, target })}
      </span>
      <span className="text-xs" style={{ color: "var(--dim)" }}>{item.reason}</span>
    </span>
  );
}
