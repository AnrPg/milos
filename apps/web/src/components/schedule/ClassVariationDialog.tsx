"use client";

import { useEffect, useMemo, useState } from "react";

import { programWorkoutForUsers } from "@/api/admin-users";
import type { ScheduleSlot } from "@/api/schedule";
import { listAdminWorkouts, type WorkoutRecord } from "@/api/workouts";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { GroupOutcomeList } from "@/components/workouts/GroupOutcomeList";
import { localizeAdminAssignmentError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import {
  GROUP_PROGRAMMING_LIMIT,
  classDay,
  groupOutcomeRows,
  toggleSelection,
  variationCandidates,
  type GroupOutcomeRow,
} from "@/lib/group-variations";

/**
 * ADR-201: «Variation for…» from the class popup. Staff pick several of the
 * class's attendees and a WOD; each one gets their own class version
 * (`class_variant`), exactly as if programmed alone from their profile.
 */
export function ClassVariationDialog({
  slot,
  accessToken,
  onClose,
  onProgrammed,
}: {
  slot: ScheduleSlot;
  accessToken: string;
  onClose: () => void;
  /** Called after at least one person got their version. */
  onProgrammed?: () => void;
}) {
  const i18n = useUiTranslations();
  const candidates = useMemo(
    () => variationCandidates(slot.bookings, slot.member_versions ?? []),
    [slot.bookings, slot.member_versions],
  );
  const [selected, setSelected] = useState<string[]>([]);
  const [workouts, setWorkouts] = useState<WorkoutRecord[]>([]);
  // Empty = start from the class's own WOD.
  const [workoutId, setWorkoutId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [rows, setRows] = useState<GroupOutcomeRow[]>([]);

  useEffect(() => {
    let active = true;
    listAdminWorkouts(accessToken)
      .then((list) => {
        if (active) setWorkouts(list.filter((workout) => workout.status === "published"));
      })
      .catch(() => {
        if (active) setWorkouts([]);
      });
    return () => {
      active = false;
    };
  }, [accessToken]);

  const classHasWorkout = Boolean(slot.master_workout_id ?? slot.workout?.id);
  const needsWorkout = !classHasWorkout && !workoutId;
  const allSelected = candidates.length > 0 && candidates.slice(0, GROUP_PROGRAMMING_LIMIT).every((c) => selected.includes(c.userId));

  async function submit() {
    if (!selected.length || needsWorkout) return;
    setBusy(true);
    setError(null);
    try {
      const response = await programWorkoutForUsers(accessToken, {
        user_ids: selected,
        ...(workoutId ? { master_workout_id: workoutId } : {}),
        folder_id: null,
        scheduled_for: classDay(slot.scheduled_at),
        slot_id: slot.id,
        copy_source: true,
        mode: "class_variant",
      });
      const names = new Map(candidates.map((candidate) => [candidate.userId, candidate.nickname]));
      const outcome = groupOutcomeRows(response.results, names);
      setRows(outcome);
      setSelected([]);
      if (outcome.some((row) => row.ok)) onProgrammed?.();
    } catch (reason) {
      setError(localizeAdminAssignmentError(reason, i18n));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog
      onClose={onClose}
      dismissible={!busy}
      eyebrow={slot.class_type.name}
      title={i18n("groupVariationTitle")}
      description={i18n("groupVariationIntro")}
      size="lg"
      variant="center"
      testId="class-variation-dialog"
      footer={
        <>
          <DialogButton tone="ghost" onClick={onClose} disabled={busy}>
            {i18n("closefeb3e25")}
          </DialogButton>
          <DialogButton
            tone="primary"
            onClick={() => void submit()}
            disabled={busy || !selected.length || needsWorkout}
          >
            {i18n("groupVariationSubmit", { count: selected.length })}
          </DialogButton>
        </>
      }
    >
      <div className="space-y-4">
        <label className="block text-xs font-semibold" style={{ color: "var(--text)" }}>
          {i18n("groupVariationWorkoutLabel")}
          <Select
            className="mt-2 w-full rounded-xl px-3 py-2"
            style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            value={workoutId}
            onValueChange={(value) => setWorkoutId(value)}
          >
            <option value="">
              {classHasWorkout ? i18n("groupVariationClassWod") : i18n("featureChooseWod")}
            </option>
            {workouts.map((workout) => (
              <option key={workout.id} value={workout.id}>
                {workout.title}
              </option>
            ))}
          </Select>
        </label>
        {needsWorkout ? (
          <p className="text-xs" style={{ color: "var(--muted)" }}>
            {i18n("groupVariationClassHasNoWod")}
          </p>
        ) : null}

        <fieldset className="rounded-2xl p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
          <legend className="px-1 text-xs font-semibold" style={{ color: "var(--text)" }}>
            {i18n("groupVariationPeople")}
          </legend>
          {candidates.length ? (
            <>
              <div className="mb-2 flex items-center justify-between gap-2">
                <p className="text-xs" style={{ color: "var(--muted)" }}>
                  {i18n("groupVariationLimit", { limit: GROUP_PROGRAMMING_LIMIT })}
                </p>
                <button
                  type="button"
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
                  onClick={() =>
                    setSelected(
                      allSelected ? [] : candidates.slice(0, GROUP_PROGRAMMING_LIMIT).map((candidate) => candidate.userId),
                    )
                  }
                >
                  {allSelected ? i18n("groupVariationClearSelection") : i18n("groupVariationSelectAll")}
                </button>
              </div>
              <ul className="max-h-72 space-y-1 overflow-y-auto">
                {candidates.map((candidate) => (
                  <li key={candidate.userId}>
                    <label
                      className="flex cursor-pointer items-center gap-3 rounded-xl px-3 py-2 text-sm"
                      style={{
                        background: selected.includes(candidate.userId)
                          ? "color-mix(in srgb, var(--primary) 12%, var(--panel))"
                          : "var(--panel)",
                        border: "1px solid var(--border)",
                        color: "var(--text)",
                      }}
                    >
                      <input
                        type="checkbox"
                        checked={selected.includes(candidate.userId)}
                        onChange={() => setSelected((current) => toggleSelection(current, candidate.userId))}
                      />
                      <span className="flex-1 font-semibold">{candidate.nickname}</span>
                      {candidate.hasVersion ? (
                        <span className="text-xs" style={{ color: "var(--primary)" }}>
                          {i18n("groupVariationHasVersion")}
                        </span>
                      ) : null}
                    </label>
                  </li>
                ))}
              </ul>
            </>
          ) : (
            <p className="text-sm" style={{ color: "var(--muted)" }}>
              {i18n("groupVariationNoAttendees")}
            </p>
          )}
        </fieldset>

        {error ? <ErrorNotice>{error}</ErrorNotice> : null}
        <GroupOutcomeList rows={rows} />
      </div>
    </Dialog>
  );
}
