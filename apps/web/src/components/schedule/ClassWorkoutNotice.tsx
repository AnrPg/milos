"use client";

import { useState } from "react";

import { linkScheduleSlotWorkout, type ScheduleSlot } from "@/api/schedule";
import type { WorkoutRecord } from "@/api/workouts";
import { useUiTranslations } from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { Select } from "@/components/ui/Select";

/** ADR-176: which notice a class without its WOD shows staff, if any. */
export function classWorkoutNoticeKind(slot: Pick<ScheduleSlot, "published" | "workout_status">) {
  if (slot.workout_status === "linked" || !slot.workout_status) return null;
  if (slot.published === false) return "draft" as const;
  return slot.workout_status === "missing" ? ("missing" as const) : ("awaiting" as const);
}

/**
 * ADR-176: tells staff a class has no WOD (a draft members can't see, or a
 * series class missing it today) and links one in place.
 */
export function ClassWorkoutNotice({
  slot,
  accessToken,
  workouts,
  onLinked,
}: {
  slot: ScheduleSlot;
  accessToken: string;
  workouts: WorkoutRecord[];
  onLinked?: () => void;
}) {
  const i18n = useUiTranslations();
  const [workoutId, setWorkoutId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const kind = classWorkoutNoticeKind(slot);
  if (!kind) return null;

  const urgent = kind !== "awaiting";
  const tone = urgent ? "var(--danger)" : "var(--warning)";

  async function link() {
    if (!workoutId) return;
    setBusy(true);
    setError(null);
    try {
      await linkScheduleSlotWorkout(accessToken, slot.id, workoutId);
      onLinked?.();
    } catch (reason) {
      setError(localizeError(reason, i18n));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div
      className="mt-6 space-y-3 rounded-[1.4rem] p-4"
      role={urgent ? "alert" : "status"}
      style={{ background: `color-mix(in srgb, ${tone} 10%, transparent)`, border: `1px solid color-mix(in srgb, ${tone} 35%, transparent)` }}
    >
      <p className="text-sm font-semibold" style={{ color: tone }}>
        {kind === "draft" ? i18n("classDraftTitle") : kind === "missing" ? i18n("classWodMissingTitle") : i18n("classWodAwaitingTitle")}
      </p>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {kind === "draft" ? i18n("classDraftBody") : kind === "missing" ? i18n("classWodMissingBody") : i18n("classWodAwaitingBody")}
      </p>
      {workouts.length > 0 ? (
        <div className="flex flex-wrap items-center gap-2">
          <Select
            aria-label={i18n("classLinkWodLabel")}
            className="min-w-0 flex-1 rounded-xl px-3 py-2 text-sm outline-none"
            style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
            value={workoutId}
            onValueChange={(value) => setWorkoutId(value)}
          >
            <option value="">{i18n("classLinkWodPlaceholder")}</option>
            {workouts.map((workout) => (
              <option key={workout.id} value={workout.id}>
                {workout.title}
              </option>
            ))}
          </Select>
          <button
            type="button"
            disabled={!workoutId || busy}
            className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            onClick={() => void link()}
          >
            {busy ? i18n("classLinkWodSaving") : i18n("classLinkWod")}
          </button>
        </div>
      ) : null}
      {error ? <p className="text-sm" style={{ color: "var(--danger)" }}>{error}</p> : null}
    </div>
  );
}
