"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useId, useState } from "react";

import { assignWorkout, listAthletes, type AthleteOption } from "@/api/assigned-workouts";
import { listAdminWorkouts, type WorkoutRecord } from "@/api/workouts";
import { workoutTypeColor } from "@/lib/workout-colors";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { WorkoutCreationCanvas } from "@/components/workouts/creation/WorkoutCreationCanvas";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

type Props = {
  accessToken: string;
  defaultDate: string;
  onClose: () => void;
  onAssigned: () => void;
};

export function QuickAssignModal({ accessToken, defaultDate, onClose, onAssigned }: Props) {
  const i18n = useUiTranslations();
  const titleId = useId();
  const dialogRef = useModalFocusTrap<HTMLDivElement>(onClose);
  const [step, setStep] = useState<"workout" | "athletes">("workout");
  const [allWorkouts, setAllWorkouts] = useState<WorkoutRecord[]>([]);
  const [workoutsLoading, setWorkoutsLoading] = useState(true);
  const [workoutQuery, setWorkoutQuery] = useState("");
  const [selectedWorkout, setSelectedWorkout] = useState<WorkoutRecord | null>(null);
  const [athletes, setAthletes] = useState<AthleteOption[]>([]);
  const [athleteQuery, setAthleteQuery] = useState("");
  const [selectedAthleteIds, setSelectedAthleteIds] = useState<string[]>([]);
  const [scheduledFor, setScheduledFor] = useState(defaultDate);
  const [athleteNotes, setAthleteNotes] = useState<Record<string, string>>({});
  const [openNoteAthleteIds, setOpenNoteAthleteIds] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [creatingWorkout, setCreatingWorkout] = useState(false);

  function openWorkoutCreator() {
    useWorkoutCreationStore.getState().resetDraft();
    setCreatingWorkout(true);
  }

  function closeWorkoutCreator() {
    useWorkoutCreationStore.getState().resetDraft();
    setCreatingWorkout(false);
  }

  function handleWorkoutPublished(workout: WorkoutRecord) {
    setAllWorkouts((current) => [workout, ...current.filter((item) => item.id !== workout.id)]);
    setSelectedWorkout(workout);
    useWorkoutCreationStore.getState().resetDraft();
    setCreatingWorkout(false);
  }

  useEffect(() => {
    listAdminWorkouts(accessToken)
      .then((workouts) => {
        setAllWorkouts(workouts.filter((w) => w.status === "published"));
        setWorkoutsLoading(false);
      })
      .catch(() => setWorkoutsLoading(false));
  }, [accessToken]);

  useEffect(() => {
    if (step !== "athletes") return;

    let cancelled = false;
    const timer = window.setTimeout(() => {
      void listAthletes(accessToken, athleteQuery)
        .then((result) => { if (!cancelled) setAthletes(result); })
        .catch(() => { if (!cancelled) setAthletes([]); });
    }, 150);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [accessToken, athleteQuery, step]);

  const filteredWorkouts = workoutQuery.trim()
    ? allWorkouts.filter((w) => w.title.toLowerCase().includes(workoutQuery.toLowerCase()))
    : allWorkouts;

  function toggleAthlete(athleteId: string) {
    setSelectedAthleteIds((current) => {
      if (current.includes(athleteId)) {
        setOpenNoteAthleteIds((openIds) => openIds.filter((id) => id !== athleteId));
        return current.filter((id) => id !== athleteId);
      }

      return [...current, athleteId];
    });
  }

  function assignmentNotes() {
    const notes = selectedAthleteIds
      .map((athleteId) => {
        const note = athleteNotes[athleteId]?.trim();
        if (!note) return null;

        const athlete = athletes.find((item) => item.id === athleteId);
        return (athlete?.nickname ?? i18n("athleteaa86fd2")) + ": " + (note);
      })
      .filter(Boolean);

    return notes.length > 0 ? notes.join("\n\n") : undefined;
  }

  async function handleAssign() {
    if (!selectedWorkout || selectedAthleteIds.length === 0) return;
    setSaving(true);
    setError(null);
    try {
      await assignWorkout(accessToken, {
        master_workout_id: selectedWorkout.id,
        athlete_ids: selectedAthleteIds,
        scheduled_for: scheduledFor,
        admin_notes: assignmentNotes(),
      });
      onAssigned();
    } catch (err) {
      setError(err instanceof Error ? err.message : i18n("couldNotAssignWorkout58ad222"));
    } finally {
      setSaving(false);
    }
  }

  return (
    <>
      <div
        className="fixed inset-0 z-50 flex items-center justify-center p-4"
        style={{ background: "rgba(0,0,0,0.65)" }}
        onClick={onClose}
        role="presentation"
      >
        <div
          ref={dialogRef}
          role="dialog"
          aria-modal="true"
          aria-labelledby={titleId}
          tabIndex={-1}
          className="flex w-full max-w-lg flex-col overflow-hidden rounded-[2rem] outline-none"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", maxHeight: "90vh" }}
          onClick={(e) => e.stopPropagation()}
        >
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-5" style={{ borderBottom: "1px solid var(--border)" }}>
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>
                {step === "workout" ? i18n("step1Of20b5d808") : i18n("step2Of22510514")}
              </p>
              <h2 id={titleId} className="mt-1 text-lg font-bold" style={{ color: "var(--text)" }}>
                {step === "workout" ? i18n("chooseAWorkoutd02066c") : i18n("assignToAthletesafa315d")}
              </h2>
            </div>
            <button
              className="rounded-full px-3 py-1.5 text-xs font-semibold"
              style={{ background: "var(--border)", color: "var(--muted)" }}
              onClick={onClose}
              type="button"
            >
              {i18n("cancel77dfd21")}
            </button>
          </div>

          {/* Body */}
          <div className="flex-1 overflow-y-auto px-6 py-5 space-y-4">
            {step === "workout" ? (
              <>
                <div className="flex gap-2">
                  <input
                    autoFocus
                    className="min-w-0 flex-1 rounded-[1rem] px-4 py-3 text-sm outline-none"
                    style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                    placeholder={i18n("searchWorkouts4be8edc")}
                    value={workoutQuery}
                    onChange={(e) => setWorkoutQuery(e.target.value)}
                  />
                  <button
                    type="button"
                    onClick={openWorkoutCreator}
                    className="shrink-0 rounded-[1rem] px-4 text-sm font-bold"
                    style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                    aria-label={i18n("createAWorkoutWithoutLeavingAssignment5dafefa")}
                  >
                    {i18n("newb53f9d0")}
                  </button>
                </div>

                {workoutsLoading ? (
                  <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
                ) : filteredWorkouts.length === 0 ? (
                  <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("noPublishedWorkoutsFound6285b56")}</p>
                ) : (
                  <div className="space-y-2">
                    {filteredWorkouts.map((workout) => {
                      const selected = selectedWorkout?.id === workout.id;
                      return (
                        <button
                          key={workout.id}
                          className="flex w-full items-start gap-3 rounded-[1.2rem] px-4 py-3 text-left transition-colors"
                          style={
                            selected
                              ? { background: "color-mix(in srgb, var(--primary) 15%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 35%, transparent)" }
                              : { background: "var(--panel-muted)", border: "1px solid var(--border)" }
                          }
                          onClick={() => setSelectedWorkout(workout)}
                          type="button"
                        >
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                              {workout.title}
                            </p>
                            <p
                              className="mt-0.5 text-[10px] uppercase tracking-[0.14em]"
                              style={{ color: workoutTypeColor(workout.type) }}
                            >
                              {workout.type}
                            </p>
                          </div>
                          {selected ? (
                            <span className="mt-0.5 shrink-0 text-sm" style={{ color: "var(--primary)" }}>✓</span>
                          ) : null}
                        </button>
                      );
                    })}
                  </div>
                )}
              </>
            ) : (
              <>
                {selectedWorkout ? (
                  <div
                    className="flex items-center justify-between rounded-[1.2rem] px-4 py-3"
                    style={{ background: "color-mix(in srgb, var(--primary) 8%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)" }}
                  >
                    <div>
                      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{selectedWorkout.title}</p>
                      <p className="text-[10px] uppercase tracking-[0.14em]" style={{ color: workoutTypeColor(selectedWorkout.type) }}>
                        {selectedWorkout.type}
                      </p>
                    </div>
                    <button
                      className="text-xs"
                      style={{ color: "var(--dim)" }}
                      onClick={() => setStep("workout")}
                      type="button"
                    >
                      {i18n("change64fbd99")}
                    </button>
                  </div>
                ) : null}

                <label className="block">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("dateeb9a4bc")}</span>
                  <input
                    className="mt-2 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
                    style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                    type="date"
                    value={scheduledFor}
                    onChange={(e) => setScheduledFor(e.target.value)}
                  />
                </label>

                <label className="block">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("athleteSearch22491bf")}</span>
                  <input
                    autoFocus
                    className="mt-2 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
                    style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                    placeholder={i18n("filterAthletes7579f90")}
                    value={athleteQuery}
                    onChange={(e) => setAthleteQuery(e.target.value)}
                  />
                </label>

                <div className="max-h-48 space-y-2 overflow-y-auto">
                  {athletes.map((athlete) => {
                    const selected = selectedAthleteIds.includes(athlete.id);
                    const noteOpen = openNoteAthleteIds.includes(athlete.id);
                    return (
                      <div key={athlete.id} className="rounded-[1.1rem]">
                        <div
                          className="flex w-full items-center gap-2 rounded-[1.1rem] px-4 py-2.5 text-sm transition-colors"
                          style={
                            selected
                              ? { background: "var(--primary)", color: "var(--bg)" }
                              : { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }
                          }
                        >
                          <button
                            className="flex min-w-0 flex-1 items-center justify-between gap-3 text-left"
                            onClick={() => toggleAthlete(athlete.id)}
                            type="button"
                          >
                            <span className="truncate font-semibold">{athlete.nickname}</span>
                            <span className="text-[11px] uppercase tracking-[0.18em]">
                              {selected ? i18n("selected9a976fc") : i18n("add61cc55a")}
                            </span>
                          </button>
                          {selected ? (
                            <button
                              className="rounded-full px-2 py-1 text-[10px] font-bold"
                              style={{
                                background: "color-mix(in srgb, var(--bg) 12%, transparent)",
                                border: "1px solid color-mix(in srgb, var(--bg) 18%, transparent)",
                                color: "var(--bg)",
                              }}
                              onClick={() =>
                                setOpenNoteAthleteIds((current) =>
                                  current.includes(athlete.id)
                                    ? current.filter((id) => id !== athlete.id)
                                    : [...current, athlete.id],
                                )
                              }
                              type="button"
                            >
                              {noteOpen ? i18n("hideNote84df0c5") : i18n("notecf79ada")}
                            </button>
                          ) : null}
                        </div>
                        {selected && noteOpen ? (
                          <textarea
                            className="mt-2 min-h-20 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
                            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)", resize: "vertical" }}
                            placeholder={i18n("coachNoteFor3d1b8c2") + (athlete.nickname) + "..."}
                            value={athleteNotes[athlete.id] ?? ""}
                            onChange={(event) =>
                              setAthleteNotes((current) => ({
                                ...current,
                                [athlete.id]: event.target.value,
                              }))
                            }
                          />
                        ) : null}
                      </div>
                    );
                  })}
                  {athletes.length === 0 && !athleteQuery ? (
                    <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("typeToSearchAthletes771b6d4")}</p>
                  ) : athletes.length === 0 ? (
                    <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("noAthletesFound97fe277")}</p>
                  ) : null}
                </div>

                {error ? (
                  <p className="text-xs" style={{ color: "var(--primary-strong)" }}>{error}</p>
                ) : null}
              </>
            )}
          </div>

          {/* Footer */}
          <div className="px-6 py-4" style={{ borderTop: "1px solid var(--border)" }}>
            {step === "workout" ? (
              <button
                className="w-full rounded-full py-3 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                disabled={!selectedWorkout}
                onClick={() => setStep("athletes")}
                type="button"
              >
                {i18n("nextAssignToAthletesc7320c9")}
              </button>
            ) : (
              <button
                className="w-full rounded-full py-3 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--text)", color: "var(--bg)" }}
                disabled={saving || selectedAthleteIds.length === 0 || !scheduledFor}
                onClick={() => void handleAssign()}
                type="button"
              >
                {saving ? i18n("assigning4d16a1a") : i18n("assignTocc79072") + (selectedAthleteIds.length) + " athlete" + (selectedAthleteIds.length !== 1 ? "s" : "")}
              </button>
            )}
          </div>
        </div>
      </div>
      {creatingWorkout ? (
        <div
          className="fixed inset-0 z-[70] flex items-center justify-center p-2 sm:p-5"
          style={{ background: "rgba(0,0,0,0.82)" }}
          role="dialog"
          aria-modal="true"
          aria-label={i18n("createWorkoutc7c6baa")}
        >
          <div
            className="w-full max-w-[96rem] overflow-hidden rounded-[1.5rem]"
            style={{ border: "1px solid var(--border)", boxShadow: "0 30px 90px rgba(0,0,0,.55)" }}
          >
            <WorkoutCreationCanvas
              embedded
              onCancel={closeWorkoutCreator}
              onPublished={handleWorkoutPublished}
            />
          </div>
        </div>
      ) : null}
    </>
  );
}
