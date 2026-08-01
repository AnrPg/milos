"use client";

import { useEffect, useMemo, useState } from "react";

import {
  fetchAdminUserSchedule,
  programAdminUserWorkout,
  type AdminUserSchedule,
} from "@/api/admin-users";
import {
  createWorkoutFolder,
  listAdminWorkouts,
  listWorkoutFolders,
  type WorkoutFolder,
  type WorkoutRecord,
} from "@/api/workouts";
import { WorkoutCreationCanvas } from "@/components/workouts/creation/WorkoutCreationCanvas";
import { useUiTranslations } from "@/i18n/ui";
import { useWorkoutCreationStore } from "@/stores/workout-creation";

type Props = {
  token: string;
  userId: string;
  role: "member" | "athlete" | "admin";
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
  return fallback;
}

export function UserProgrammingSchedule({ token, userId, role }: Props) {
  const i18n = useUiTranslations();
  const [startDate, setStartDate] = useState(() => isoDate(new Date()));
  const [schedule, setSchedule] = useState<AdminUserSchedule | null>(null);
  const [workouts, setWorkouts] = useState<WorkoutRecord[]>([]);
  const [folders, setFolders] = useState<WorkoutFolder[]>([]);
  const [selectedDate, setSelectedDate] = useState(() => isoDate(new Date()));
  const [selectedWorkoutId, setSelectedWorkoutId] = useState("");
  const [selectedFolderId, setSelectedFolderId] = useState("");
  const [selectedSlotId, setSelectedSlotId] = useState("");
  const [creating, setCreating] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

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

  const dayItems = (schedule?.items ?? []).filter((item) => itemDate(item) === selectedDate);
  const selectedDaySlots = role === "member" ? dayItems : [];

  async function createFolder() {
    const name = window.prompt(i18n("featureFolderName"))?.trim();
    if (!name) return;
    const folder = await createWorkoutFolder(token, { name, parent_id: null });
    setFolders((current) => [...current, folder]);
    setSelectedFolderId(folder.id);
  }

  async function program(masterWorkoutId: string, copySource: boolean) {
    if (!selectedFolderId) {
      setError(i18n("featureChooseLibraryFolder"));
      return;
    }
    if (role === "member" && !selectedSlotId) {
      setError(i18n("featureChooseBookedClass"));
      return;
    }

    setBusy(true);
    setError(null);
    try {
      await programAdminUserWorkout(token, userId, {
        master_workout_id: masterWorkoutId,
        folder_id: selectedFolderId,
        scheduled_for: selectedDate,
        slot_id: role === "member" ? selectedSlotId : undefined,
        copy_source: copySource,
      });
      setMessage(role === "athlete" ? i18n("featurePersonalWodAssigned") : i18n("featureClassWodAttached"));
      setSelectedWorkoutId("");
      await reload();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : i18n("featureProgrammingSaveFailed"));
    } finally {
      setBusy(false);
    }
  }

  function openCreator() {
    if (!selectedFolderId) {
      setError(i18n("featureChooseFolderBeforeCreating"));
      return;
    }
    useWorkoutCreationStore.getState().resetDraft();
    setCreating(true);
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex gap-2">
          <button type="button" className="rounded-full px-3 py-2 text-sm" style={{ background: "var(--bg-soft)" }} onClick={() => {
            const date = new Date(`${startDate}T12:00:00`); date.setDate(date.getDate() - 7); setStartDate(isoDate(date));
          }}>{i18n("featurePreviousWeek")}</button>
          <button type="button" className="rounded-full px-3 py-2 text-sm" style={{ background: "var(--bg-soft)" }} onClick={() => setStartDate(isoDate(new Date()))}>{i18n("featureToday")}</button>
          <button type="button" className="rounded-full px-3 py-2 text-sm" style={{ background: "var(--bg-soft)" }} onClick={() => {
            const date = new Date(`${startDate}T12:00:00`); date.setDate(date.getDate() + 7); setStartDate(isoDate(date));
          }}>{i18n("featureNextWeek")}</button>
        </div>
        <p className="text-xs" style={{ color: "var(--muted)" }}>{startDate} — {endDate}</p>
      </div>

      <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-7">
        {days.map((day) => {
          const items = (schedule?.items ?? []).filter((item) => itemDate(item) === day);
          return <button key={day} type="button" className="min-h-28 rounded-2xl p-3 text-start" style={{ background: selectedDate === day ? "color-mix(in srgb, var(--primary) 14%, var(--bg-soft))" : "var(--bg-soft)", border: selectedDate === day ? "1px solid var(--primary)" : "1px solid var(--border)" }} onClick={() => { setSelectedDate(day); setSelectedSlotId(""); }}>
            <span className="block text-xs font-semibold">{new Intl.DateTimeFormat(undefined, { weekday: "short", day: "numeric" }).format(new Date(`${day}T12:00:00`))}</span>
            <span className="mt-2 block text-xs" style={{ color: "var(--muted)" }}>{items.length ? i18n("featureScheduledCount", { count: items.length }) : i18n("featureOpenDay")}</span>
            {items.slice(0, 2).map((item) => <span key={itemId(item)} className="mt-1 block truncate text-xs">{itemTitle(item, i18n("featureScheduledClass"))}</span>)}
          </button>;
        })}
      </div>

      <div className="rounded-2xl p-4" style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }}>
        <div className="grid gap-3 md:grid-cols-3">
          <label className="text-xs font-semibold">{i18n("featureSaveInFolder")}
            <select className="mt-2 w-full rounded-xl px-3 py-2" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} value={selectedFolderId} onChange={(event) => setSelectedFolderId(event.target.value)}>
              <option value="">{i18n("featureChooseFolder")}</option>
              {folders.map((folder) => <option key={folder.id} value={folder.id}>{folder.name}</option>)}
            </select>
          </label>
          <label className="text-xs font-semibold">{i18n("featureExistingWod")}
            <select className="mt-2 w-full rounded-xl px-3 py-2" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} value={selectedWorkoutId} onChange={(event) => setSelectedWorkoutId(event.target.value)}>
              <option value="">{i18n("featureChooseWod")}</option>
              {workouts.map((workout) => <option key={workout.id} value={workout.id}>{workout.title}</option>)}
            </select>
          </label>
          {role === "member" ? <label className="text-xs font-semibold">{i18n("featureBookedClass")}
            <select className="mt-2 w-full rounded-xl px-3 py-2" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} value={selectedSlotId} onChange={(event) => setSelectedSlotId(event.target.value)}>
              <option value="">{i18n("featureChooseClass")}</option>
              {selectedDaySlots.map((item) => <option key={itemId(item)} value={itemId(item)}>{itemTitle(item, i18n("featureScheduledClass"))}</option>)}
            </select>
          </label> : <div />}
        </div>
        <div className="mt-4 flex flex-wrap gap-2">
          <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} disabled={busy || !selectedWorkoutId} onClick={() => void program(selectedWorkoutId, true)}>{i18n("featureCopyAndAssign")}</button>
          <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--text)", color: "var(--bg)" }} onClick={openCreator}>{i18n("featureCreateNewWod")}</button>
          <button type="button" className="rounded-full px-4 py-2 text-sm" style={{ background: "var(--panel)" }} onClick={() => void createFolder()}>{i18n("featureNewFolder")}</button>
        </div>
        {message ? <p className="mt-3 text-sm" style={{ color: "var(--success)" }}>{message}</p> : null}
        {error ? <p className="mt-3 text-sm" style={{ color: "var(--danger)" }}>{error}</p> : null}
      </div>

      {creating ? <div className="fixed inset-0 z-[80] flex items-center justify-center p-3" style={{ background: "rgba(0,0,0,.82)" }}><div className="w-full max-w-[96rem] overflow-hidden rounded-3xl"><WorkoutCreationCanvas embedded onCancel={() => setCreating(false)} onPublished={(workout) => { setCreating(false); void program(workout.id, false); }} /></div></div> : null}
    </div>
  );
}
