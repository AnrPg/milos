/**
 * ADR-270: the athlete's 1RM per exercise, read from their PRs (the
 * existing `/prs` API), so a load prescribed in % of 1RM can be shown and
 * recorded in kg. A PR counts when it is in kg and is a one-rep max (one
 * rep in its metrics, or "1RM" in its name); names match loosely (case,
 * accents, "1RM" ignored).
 */
import type { PRRecord } from "@/api/gamification";

import type { OneRepMaxLookup } from "./actuals";

export function normalizeExerciseName(name: string): string {
  return name
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/\b1\s*rm\b/g, " ")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

const isOneRepMax = (pr: Pick<PRRecord, "name" | "unit" | "supporting_metrics">) =>
  pr.unit === "kg" && (pr.supporting_metrics?.reps === 1 || /\b1\s*rm\b/i.test(pr.name));

/** A lookup over the athlete's PRs; the best one wins when several match. */
export function oneRepMaxLookup(prs: ReadonlyArray<Pick<PRRecord, "name" | "unit" | "current_score" | "supporting_metrics">>): OneRepMaxLookup {
  const best = new Map<string, number>();
  for (const pr of prs) {
    if (!isOneRepMax(pr) || !(pr.current_score > 0)) continue;
    const key = normalizeExerciseName(pr.name);
    if (key) best.set(key, Math.max(best.get(key) ?? 0, pr.current_score));
  }
  return (name) => best.get(normalizeExerciseName(name)) ?? null;
}
