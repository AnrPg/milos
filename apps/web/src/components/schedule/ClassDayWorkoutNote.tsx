"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { followDayWorkout, type DayWorkout } from "@/api/day-workouts";
import type { ScheduleSlot } from "@/api/schedule";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * ADR-224, staff: where the class's WOD comes from. An inherited WOD says
 * so (it changes with the day's WOD); a class with its own WOD on a day that
 * has one names the day's WOD and offers «Επαναφορά στο WOD ημέρας». Shows
 * nothing when the day has no WOD for this class.
 */
export function ClassDayWorkoutNote({
  slot,
  dayWorkout,
  accessToken,
  isPast,
  onChanged,
}: {
  slot: ScheduleSlot;
  dayWorkout: DayWorkout | null;
  accessToken: string;
  isPast: boolean;
  onChanged?: () => void;
}) {
  const t = useTranslations("Schedule");
  const i18n = useUiTranslations();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function follow() {
    setBusy(true);
    setError(null);
    try {
      await followDayWorkout(accessToken, slot.id);
      onChanged?.();
    } catch (reason) {
      setError(localizeError(reason, i18n));
    } finally {
      setBusy(false);
    }
  }

  if (slot.workout_source === "day") {
    return (
      <p className="mt-3 flex flex-wrap items-center gap-2 text-xs" style={{ color: "var(--muted)" }} data-testid="class-day-wod-note">
        <span
          className="rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-[0.12em]"
          style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)" }}
        >
          {t("dayWodLabel")}
        </span>
        {t("slotFromDayWod")}
      </p>
    );
  }

  if (slot.workout_source !== "class" || !dayWorkout) return null;

  return (
    <div className="mt-3 space-y-2" data-testid="class-day-wod-note">
      <p className="flex flex-wrap items-center gap-2 text-xs" style={{ color: "var(--muted)" }}>
        <span>{t("slotOwnWod", { title: dayWorkout.workout?.title ?? "WOD" })}</span>
        {isPast ? null : (
          <button
            type="button"
            className="rounded-full px-3 py-1 text-xs font-semibold"
            style={{ background: "var(--card)", color: "var(--text-soft)", border: "1px solid var(--border)" }}
            onClick={() => void follow()}
            disabled={busy}
          >
            {t("slotFollowDay")}
          </button>
        )}
      </p>
      {error ? <ErrorNotice variant="field">{error}</ErrorNotice> : null}
    </div>
  );
}
