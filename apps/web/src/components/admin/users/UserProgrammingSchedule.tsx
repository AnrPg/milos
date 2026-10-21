"use client";

import { useEffect, useMemo, useState } from "react";
import { useLocale } from "next-intl";

import {
  fetchAdminUserSchedule,
  programAdminUserWorkout,
  type AdminUserSchedule,
  type MemberProgrammingMode,
} from "@/api/admin-users";
import {
  duplicateWorkout,
  listAdminWorkouts,
  listWorkoutFolders,
  type WorkoutFolder,
  type WorkoutRecord,
} from "@/api/workouts";
import { WorkoutCreationCanvas } from "@/components/workouts/creation/WorkoutCreationCanvas";
import { compareFolders, folderDisplayName } from "@/components/workouts/library/library-folders";
import { localizeAdminAssignmentError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import {
  MEMBER_PROGRAMMING_MODES,
  modeRequiresBookedClass,
  programmingSuccessKey,
} from "@/lib/member-programming";
import { useWorkoutCreationStore } from "@/stores/workout-creation";

type Props = {
  token: string;
  userId: string;
  role: "member" | "athlete" | "admin";
  /** When set, opens the assignment dialog for this day (used by the profile's quick action). */
  assignRequestDate?: string | null;
  onAssignRequestHandled?: () => void;
};

const MODE_LABEL_KEYS: Record<MemberProgrammingMode, string> = {
  class_variant: "memberProgrammingModeClassVariant",
  personal: "memberProgrammingModePersonal",
  class_workout: "memberProgrammingModeClassWorkout",
};

const MODE_HINT_KEYS: Record<MemberProgrammingMode, string> = {
  class_variant: "memberProgrammingModeClassVariantHint",
  personal: "memberProgrammingModePersonalHint",
  class_workout: "memberProgrammingModeClassWorkoutHint",
};

function isoDate(date: Date) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 10);
}

function itemDate(item: Record<string, unknown>) {
  const value = item.scheduled_for ?? item.scheduled_at;
  return typeof value === "string" ? value.slice(0, 10) : "";
}

function itemId(item: Record<string, unknown>) {
  return typeof item.id === "string" ? item.id : "";
}

function itemTitle(item: Record<string, unknown>, fallback: string) {
  const workout = item.workout;
  if (workout && typeof workout === "object" && "title" in workout) return String(workout.title);
  if (typeof item.name === "string" && item.name) return item.name;
  return fallback;
}

function isClassItem(item: Record<string, unknown>) {
  return item.kind === "class";
}

function isClassVariantItem(item: Record<string, unknown>) {
  return item.kind === "assignment" && item.assignment_kind === "class_variant";
}

export function UserProgrammingSchedule({ token, userId, role, assignRequestDate, onAssignRequestHandled }: Props) {
  const i18n = useUiTranslations();
  const locale = useLocale();
  const isMember = role === "member";
  const [startDate, setStartDate] = useState(() => isoDate(new Date()));
  const [schedule, setSchedule] = useState<AdminUserSchedule | null>(null);
  const [workouts, setWorkouts] = useState<WorkoutRecord[]>([]);
  const [folders, setFolders] = useState<WorkoutFolder[]>([]);
  const [selectedDate, setSelectedDate] = useState(() => isoDate(new Date()));
  const [selectedWorkoutId, setSelectedWorkoutId] = useState("");
  const [selectedFolderId, setSelectedFolderId] = useState("");
  const [selectedSlotId, setSelectedSlotId] = useState("");
  const [memberMode, setMemberMode] = useState<MemberProgrammingMode>("class_variant");
  const [assignmentModalOpen, setAssignmentModalOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const [editingDraftId, setEditingDraftId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const needsClass = isMember && modeRequiresBookedClass(memberMode);
  const automaticFolderLabel = !isMember
    ? i18n("featureAutoAthleteFolder")
    : memberMode === "class_workout"
      ? i18n("featureAutoClassFolder")
      : i18n("featureAutoMemberVariationFolder");
  const folderLabels = {
    athletes: i18n("featureAthletesFolder"),
    classes: i18n("featureClassesFolder"),
    memberVariations: i18n("featureMemberVariationsFolder"),
  };

  const endDate = useMemo(() => {
    const date = new Date(`${startDate}T12:00:00`);
    date.setDate(date.getDate() + 6);
    return isoDate(date);
  }, [startDate]);

  const days = useMemo(() => Array.from({ length: 7 }, (_, index) => {
    const date = new Date(`${startDate}T12:00:00`);
    date.setDate(date.getDate() + index);
    return isoDate(date);
  }), [startDate]);

  async function reload() {
    const [nextSchedule, nextWorkouts, nextFolders] = await Promise.all([
      fetchAdminUserSchedule(token, userId, startDate, endDate),
      listAdminWorkouts(token),
      listWorkoutFolders(token),
    ]);
    setSchedule(nextSchedule);
    setWorkouts(nextWorkouts.filter((workout) => workout.status === "published"));
    setFolders(nextFolders);
  }

  useEffect(() => {
    const frame = window.requestAnimationFrame(() => {
      void reload().catch((reason) => setError(reason instanceof Error ? reason.message : i18n("featureCouldNotLoadSchedule")));
    });
    return () => window.cancelAnimationFrame(frame);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, userId, startDate, endDate, i18n]);

  useEffect(() => {
    if (!assignRequestDate) return;
    const frame = window.requestAnimationFrame(() => {
      setSelectedDate(assignRequestDate);
      setSelectedSlotId("");
      setAssignmentModalOpen(true);
      onAssignRequestHandled?.();
    });
    return () => window.cancelAnimationFrame(frame);
  }, [assignRequestDate, onAssignRequestHandled]);

  const dayItems = (schedule?.items ?? []).filter((item) => itemDate(item) === selectedDate);
  const selectedDaySlots = isMember ? dayItems.filter(isClassItem) : [];
  const selectedSlot = selectedDaySlots.find((item) => itemId(item) === selectedSlotId);

  function validateTarget() {
    if (needsClass && !selectedSlotId) {
      setError(i18n("featureChooseBookedClass"));
      return false;
    }
    return true;
  }

  async function program(masterWorkoutId: string | null, copySource: boolean) {
    if (!validateTarget()) return;

    setBusy(true);
    setError(null);
    try {
      await programAdminUserWorkout(token, userId, {
        ...(masterWorkoutId ? { master_workout_id: masterWorkoutId } : {}),
        // Empty = file automatically in the athlete's, class-day or member variations folder.
        folder_id: selectedFolderId || null,
        scheduled_for: selectedDate,
        slot_id: needsClass ? selectedSlotId : undefined,
        copy_source: copySource,
        ...(isMember ? { mode: memberMode } : {}),
      });
      setMessage(i18n(programmingSuccessKey(role, memberMode)));
      setSelectedWorkoutId("");
      setAssignmentModalOpen(false);
      await reload();
    } catch (reason) {
      setError(reason instanceof Error ? localizeAdminAssignmentError(reason, i18n) : i18n("featureProgrammingSaveFailed"));
    } finally {
      setBusy(false);
    }
  }

  function openCreator() {
    useWorkoutCreationStore.getState().resetDraft();
    setEditingDraftId(null);
    setCreating(true);
  }

  // ADR-125: duplicate the class's workout into a draft and edit it in the
  // embedded canvas; publishing assigns it as this member's version.
  async function editClassWorkoutForMember() {
    if (!validateTarget()) return;
    const sourceWorkoutId = typeof selectedSlot?.master_workout_id === "string" ? selectedSlot.master_workout_id : null;
    if (!sourceWorkoutId) {
      setError(i18n("memberProgrammingClassHasNoWorkout"));
      return;
    }

    setBusy(true);
    setError(null);
    try {
      const draft = await duplicateWorkout(token, sourceWorkoutId, { slot_id: selectedSlotId });
      useWorkoutCreationStore.getState().resetDraft();
      setEditingDraftId(draft.id);
      setCreating(true);
    } catch (reason) {
      setError(reason instanceof Error ? localizeAdminAssignmentError(reason, i18n) : i18n("featureProgrammingSaveFailed"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex gap-2">
          <button type="button" className="rounded-full px-3 py-2 text-sm" style={{ background: "var(--panel-muted)" }} onClick={() => {
            const date = new Date(`${startDate}T12:00:00`); date.setDate(date.getDate() - 7); setStartDate(isoDate(date));
          }}>{i18n("featurePreviousWeek")}</button>
          <button type="button" className="rounded-full px-3 py-2 text-sm" style={{ background: "var(--panel-muted)" }} onClick={() => setStartDate(isoDate(new Date()))}>{i18n("featureToday")}</button>
          <button type="button" className="rounded-full px-3 py-2 text-sm" style={{ background: "var(--panel-muted)" }} onClick={() => {
            const date = new Date(`${startDate}T12:00:00`); date.setDate(date.getDate() + 7); setStartDate(isoDate(date));
          }}>{i18n("featureNextWeek")}</button>
        </div>
        <p className="text-xs" style={{ color: "var(--muted)" }}>{startDate} — {endDate}</p>
      </div>

      <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-7">
        {days.map((day) => {
          const items = (schedule?.items ?? []).filter((item) => itemDate(item) === day);
          return <button key={day} type="button" className="min-h-28 rounded-2xl p-3 text-start" style={{ background: selectedDate === day ? "color-mix(in srgb, var(--primary) 14%, var(--panel-muted))" : "var(--panel-muted)", border: selectedDate === day ? "1px solid var(--primary)" : "1px solid var(--border)" }} onClick={() => { setSelectedDate(day); setSelectedSlotId(""); setAssignmentModalOpen(true); }}>
            <span className="block text-xs font-semibold">{new Intl.DateTimeFormat(undefined, { weekday: "short", day: "numeric" }).format(new Date(`${day}T12:00:00`))}</span>
            <span className="mt-2 block text-xs" style={{ color: "var(--muted)" }}>{items.length ? i18n("featureScheduledCount", { count: items.length }) : i18n("featureOpenDay")}</span>
            {items.slice(0, 2).map((item) => <span key={itemId(item)} className="mt-1 block truncate text-xs">
              {isClassVariantItem(item) ? <span style={{ color: "var(--primary)" }}>{i18n("memberProgrammingClassVersionBadge")} · </span> : null}
              {itemTitle(item, i18n("featureScheduledClass"))}
            </span>)}
          </button>;
        })}
      </div>

      {message ? <p className="text-sm" style={{ color: "var(--success)" }}>{message}</p> : null}
      {error ? <p className="text-sm" style={{ color: "var(--danger)" }}>{error}</p> : null}

      {assignmentModalOpen ? <div className="fixed inset-0 z-[70] flex items-center justify-center p-4" style={{ background: "var(--scrim)" }} onClick={() => setAssignmentModalOpen(false)} role="presentation">
      <div className="w-full max-w-3xl rounded-2xl p-4 shadow-[var(--shadow-lg)]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} onClick={(event) => event.stopPropagation()}>
        <div className="mb-4 flex items-start justify-between gap-3">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--primary)" }}>{i18n("featureScheduleProgramming")}</p>
            <h3 className="mt-1 text-xl font-semibold" style={{ color: "var(--text)" }}>{selectedDate}</h3>
          </div>
          <button type="button" className="rounded-full px-3 py-1.5 text-xs font-semibold" style={{ background: "var(--border)", color: "var(--muted)" }} onClick={() => setAssignmentModalOpen(false)}>{i18n("closebbfa773")}</button>
        </div>
      {isMember ? <fieldset className="mb-4 rounded-2xl p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
        <legend className="px-1 text-xs font-semibold">{i18n("memberProgrammingModeLegend")}</legend>
        <div className="grid gap-2 md:grid-cols-3">
          {MEMBER_PROGRAMMING_MODES.map((mode) => <label key={mode} className="flex cursor-pointer gap-2 rounded-xl p-3 text-xs" style={{ background: memberMode === mode ? "color-mix(in srgb, var(--primary) 12%, var(--panel))" : "var(--panel)", border: memberMode === mode ? "1px solid var(--primary)" : "1px solid var(--border)" }}>
            <input type="radio" name="member-programming-mode" value={mode} checked={memberMode === mode} onChange={() => setMemberMode(mode)} />
            <span>
              <span className="block font-semibold" style={{ color: "var(--text)" }}>{i18n(MODE_LABEL_KEYS[mode])}</span>
              <span className="mt-1 block" style={{ color: "var(--muted)" }}>{i18n(MODE_HINT_KEYS[mode])}</span>
            </span>
          </label>)}
        </div>
      </fieldset> : null}
      <div className="rounded-2xl p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
        <div className="grid gap-3 md:grid-cols-3">
          <label className="text-xs font-semibold">{i18n("featureSaveInFolder")}
            <select className="mt-2 w-full rounded-xl px-3 py-2" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} value={selectedFolderId} onChange={(event) => setSelectedFolderId(event.target.value)}>
              <option value="">{automaticFolderLabel}</option>
              {[...folders].sort(compareFolders).map((folder) => (
                <option key={folder.id} value={folder.id}>
                  {folderDisplayName(folder, folderLabels, locale)}
                </option>
              ))}
            </select>
          </label>
          <label className="text-xs font-semibold">{i18n("featureExistingWod")}
            <select className="mt-2 w-full rounded-xl px-3 py-2" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} value={selectedWorkoutId} onChange={(event) => setSelectedWorkoutId(event.target.value)}>
              <option value="">{i18n("featureChooseWod")}</option>
              {workouts.map((workout) => <option key={workout.id} value={workout.id}>{workout.title}</option>)}
            </select>
          </label>
          {needsClass ? <label className="text-xs font-semibold">{i18n("featureBookedClass")}
            <select className="mt-2 w-full rounded-xl px-3 py-2" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} value={selectedSlotId} onChange={(event) => setSelectedSlotId(event.target.value)}>
              <option value="">{i18n("featureChooseClass")}</option>
              {selectedDaySlots.map((item) => <option key={itemId(item)} value={itemId(item)}>{itemTitle(item, i18n("featureScheduledClass"))}</option>)}
            </select>
          </label> : <div />}
        </div>
        <div className="mt-4 flex flex-wrap gap-2">
          {isMember && memberMode === "class_variant" ? <>
            <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} disabled={busy || !selectedSlotId} onClick={() => void editClassWorkoutForMember()}>{i18n("memberProgrammingEditClassWodForMember")}</button>
            <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} disabled={busy || !selectedSlotId} onClick={() => void program(null, true)}>{i18n("memberProgrammingCopyClassWodForMember")}</button>
          </> : null}
          <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: isMember && memberMode === "class_variant" ? "var(--panel)" : "var(--primary)", color: isMember && memberMode === "class_variant" ? "var(--text)" : "var(--primary-contrast)", border: "1px solid var(--border)" }} disabled={busy || !selectedWorkoutId} onClick={() => void program(selectedWorkoutId, true)}>{i18n("featureCopyAndAssign")}</button>
          <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--text)", color: "var(--bg)" }} onClick={openCreator}>{i18n("featureCreateNewWod")}</button>
        </div>
        {isMember ? <p className="mt-3 text-xs" style={{ color: "var(--muted)" }}>{i18n(MODE_HINT_KEYS[memberMode])}</p> : null}
        {message ? <p className="mt-3 text-sm" style={{ color: "var(--success)" }}>{message}</p> : null}
        {error ? <p className="mt-3 text-sm" style={{ color: "var(--danger)" }}>{error}</p> : null}
      </div>
      </div>
      </div> : null}

      {creating ? <div className="fixed inset-0 z-[80] flex items-center justify-center p-3" style={{ background: "var(--scrim)" }}><div className="w-full max-w-[96rem] overflow-hidden rounded-3xl"><WorkoutCreationCanvas embedded initialDraftId={editingDraftId} onCancel={() => { setCreating(false); setEditingDraftId(null); }} onPublished={(workout) => { setCreating(false); setEditingDraftId(null); void program(workout.id, false); }} /></div></div> : null}
    </div>
  );
}
