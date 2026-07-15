"use client";

import { useEffect, useState } from "react";

import { assignWorkout, listAthletes, type AthleteOption } from "@/api/assigned-workouts";
import { listAdminWorkouts, type WorkoutRecord } from "@/api/workouts";
import { workoutTypeColor } from "@/lib/workout-colors";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { WorkoutCreationCanvas } from "@/components/workouts/creation/WorkoutCreationCanvas";

type Props = {
  accessToken: string;
  defaultDate: string;
  onClose: () => void;
  onAssigned: () => void;
};

export function QuickAssignModal({ accessToken, defaultDate, onClose, onAssigned }: Props) {
  const [step, setStep] = useState<"workout" | "athletes">("workout");
  const [allWorkouts, setAllWorkouts] = useState<WorkoutRecord[]>([]);
  const [workoutsLoading, setWorkoutsLoading] = useState(true);
  const [workoutQuery, setWorkoutQuery] = useState("");
  const [selectedWorkout, setSelectedWorkout] = useState<WorkoutRecord | null>(null);
  const [athletes, setAthletes] = useState<AthleteOption[]>([]);
  const [athleteQuery, setAthleteQuery] = useState("");
  const [selectedAthleteIds, setSelectedAthleteIds] = useState<string[]>([]);
  const [scheduledFor, setScheduledFor] = useState(defaultDate);
  const [adminNotes, setAdminNotes] = useState("");
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

  async function handleAssign() {
    if (!selectedWorkout || selectedAthleteIds.length === 0) return;
    setSaving(true);
    setError(null);
    try {
      await assignWorkout(accessToken, {
        master_workout_id: selectedWorkout.id,
        athlete_ids: selectedAthleteIds,
        scheduled_for: scheduledFor,
        admin_notes: adminNotes.trim() || undefined,
      });
      onAssigned();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not assign workout.");
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
          role="dialog"
          aria-modal="true"
          aria-label="Assign workout"
          className="flex w-full max-w-lg flex-col rounded-[2rem] overflow-hidden"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", maxHeight: "90vh" }}
          onClick={(e) => e.stopPropagation()}
        >
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-5" style={{ borderBottom: "1px solid var(--border)" }}>
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>
                {step === "workout" ? "Step 1 of 2" : "Step 2 of 2"}
              </p>
              <h2 className="mt-1 text-lg font-bold" style={{ color: "var(--text)" }}>
                {step === "workout" ? "Choose a workout" : "Assign to athletes"}
              </h2>
            </div>
            <button
              className="rounded-full px-3 py-1.5 text-xs font-semibold"
              style={{ background: "var(--border)", color: "var(--muted)" }}
              onClick={onClose}
              type="button"
            >
              Cancel
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
                    placeholder="Search workouts…"
                    value={workoutQuery}
                    onChange={(e) => setWorkoutQuery(e.target.value)}
                  />
                  <button
                    type="button"
                    onClick={openWorkoutCreator}
                    className="shrink-0 rounded-[1rem] px-4 text-sm font-bold"
                    style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                    aria-label="Create a workout without leaving assignment"
                  >
                    + New
                  </button>
                </div>

                {workoutsLoading ? (
                  <p className="text-sm" style={{ color: "var(--dim)" }}>Loading…</p>
                ) : filteredWorkouts.length === 0 ? (
                  <p className="text-sm" style={{ color: "var(--dim)" }}>No published workouts found.</p>
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
                      Change
                    </button>
                  </div>
                ) : null}

                <label className="block">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>Date</span>
                  <input
                    className="mt-2 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
                    style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                    type="date"
                    value={scheduledFor}
                    onChange={(e) => setScheduledFor(e.target.value)}
                  />
                </label>

                <label className="block">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>Athlete search</span>
                  <input
                    autoFocus
                    className="mt-2 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
                    style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                    placeholder="Filter athletes…"
                    value={athleteQuery}
                    onChange={(e) => setAthleteQuery(e.target.value)}
                  />
                </label>

                <div className="max-h-48 space-y-2 overflow-y-auto">
                  {athletes.map((athlete) => {
                    const selected = selectedAthleteIds.includes(athlete.id);
                    return (
                      <button
                        key={athlete.id}
                        className="flex w-full items-center justify-between rounded-[1.1rem] px-4 py-2.5 text-sm transition-colors"
                        style={
                          selected
                            ? { background: "var(--primary)", color: "var(--bg)" }
                            : { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }
                        }
                        onClick={() =>
                          setSelectedAthleteIds((current) =>
                            current.includes(athlete.id)
                              ? current.filter((id) => id !== athlete.id)
                              : [...current, athlete.id],
                          )
                        }
                        type="button"
                      >
                        <span className="font-semibold">{athlete.nickname}</span>
                        <span className="text-[11px] uppercase tracking-[0.18em]">
                          {selected ? "Selected" : "Add"}
                        </span>
                      </button>
                    );
                  })}
                  {athletes.length === 0 && !athleteQuery ? (
                    <p className="text-xs" style={{ color: "var(--dim)" }}>Type to search athletes…</p>
                  ) : athletes.length === 0 ? (
                    <p className="text-xs" style={{ color: "var(--dim)" }}>No athletes found.</p>
                  ) : null}
                </div>

                <label className="block">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>Coach note (optional)</span>
                  <textarea
                    className="mt-2 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
                    style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)", minHeight: "4rem", resize: "vertical" }}
                    placeholder="Programming context or cues…"
                    value={adminNotes}
                    onChange={(e) => setAdminNotes(e.target.value)}
                  />
                </label>

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
                Next — assign to athletes
              </button>
            ) : (
              <button
                className="w-full rounded-full py-3 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--text)", color: "var(--bg)" }}
                disabled={saving || selectedAthleteIds.length === 0 || !scheduledFor}
                onClick={() => void handleAssign()}
                type="button"
              >
                {saving ? "Assigning…" : `Assign to ${selectedAthleteIds.length} athlete${selectedAthleteIds.length !== 1 ? "s" : ""}`}
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
          aria-label="Create workout"
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
