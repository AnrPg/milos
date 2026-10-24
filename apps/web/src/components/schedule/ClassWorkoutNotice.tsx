"use client";

import { useState } from "react";

import { linkScheduleSlotWorkout, type ScheduleSlot } from "@/api/schedule";
import { useUiTranslations } from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { WodPicker } from "@/components/schedule/WodPicker";
import { dateTimeLocalInZone } from "@/lib/zoned-time";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/** ADR-176: which notice a class without its WOD shows staff, if any. */
export function classWorkoutNoticeKind(slot: Pick<ScheduleSlot, "published" | "workout_status">) {
  if (slot.workout_status === "linked" || !slot.workout_status) return null;
  if (slot.published === false) return "draft" as const;
  return slot.workout_status === "missing" ? ("missing" as const) : ("awaiting" as const);
}

/**
 * ADR-176: tells staff a class has no WOD (a draft members can't see, or a
 * series class missing it today) and links one in place: picking a WOD in
 * the picker links it straight away; "+ New WOD" writes one and comes back.
 */
export function ClassWorkoutNotice({
  slot,
  accessToken,
  timeZone = null,
  onLinked,
  onCreateNew,
}: {
  slot: ScheduleSlot;
  accessToken: string;
  timeZone?: string | null;
  onLinked?: () => void;
  onCreateNew?: () => void;
}) {
  const i18n = useUiTranslations();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const kind = classWorkoutNoticeKind(slot);
  if (!kind) return null;

  const urgent = kind !== "awaiting";
  const tone = urgent ? "var(--danger)" : "var(--warning)";

  async function link(workoutId: string | null) {
    if (!workoutId || busy) return;
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
      aria-busy={busy}
      style={{ background: `color-mix(in srgb, ${tone} 10%, transparent)`, border: `1px solid color-mix(in srgb, ${tone} 35%, transparent)` }}
    >
      <p className="text-sm font-semibold" style={{ color: tone }}>
        {kind === "draft" ? i18n("classDraftTitle") : kind === "missing" ? i18n("classWodMissingTitle") : i18n("classWodAwaitingTitle")}
      </p>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {kind === "draft" ? i18n("classDraftBody") : kind === "missing" ? i18n("classWodMissingBody") : i18n("classWodAwaitingBody")}
      </p>
      <WodPicker
        label={i18n("classLinkWodLabel")}
        token={accessToken}
        value={null}
        onChange={(workoutId) => void link(workoutId)}
        onCreateNew={onCreateNew ?? (() => undefined)}
        date={dateTimeLocalInZone(slot.scheduled_at, timeZone).slice(0, 10) || null}
        classTypeId={slot.class_type_id}
        classTypeName={slot.class_type?.name ?? null}
      />
      {busy ? <p className="text-sm" role="status" style={{ color: "var(--muted)" }}>{i18n("classLinkWodSaving")}</p> : null}
      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
    </div>
  );
}
