import type { TrainingHistoryKind } from "@/api/training-history";

/** Members mostly book classes; athletes mostly follow programmed workouts. */
export function defaultHistoryKind(role: string | null | undefined): TrainingHistoryKind {
  return role === "member" ? "classes" : "workouts";
}

/** "3×10 Back Squat @ 100 kg" from the canonical exercise fields. */
export function exerciseText(exercise: Record<string, unknown>) {
  const parts: string[] = [];
  const sets = typeof exercise.sets === "number" && exercise.sets > 1 ? exercise.sets : null;
  const value = typeof exercise.prescription_value === "number" ? exercise.prescription_value : null;
  const unit = typeof exercise.prescription_unit === "string" && exercise.prescription_unit !== "reps" ? exercise.prescription_unit : "";
  if (sets && value) parts.push(`${sets}×${value}${unit ? ` ${unit}` : ""}`);
  else if (value) parts.push(`${value}${unit ? ` ${unit}` : ""}`);
  else if (sets) parts.push(`${sets}×`);
  parts.push(String(exercise.name ?? ""));
  if (typeof exercise.load_value === "number") {
    parts.push(exercise.load_mode === "pct_1rm" ? `@ ${exercise.load_value}%` : `@ ${exercise.load_value} kg`);
  }
  return parts.join(" ").trim();
}
