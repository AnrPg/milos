"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

import { ApiError } from "@/api/client";
import {
  deleteWorkout,
  listAdminWorkouts,
  type WorkoutRecord,
} from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";
import { USER_SYNC_EVENT, type UserSyncDetail } from "@/lib/user-sync";
import { AssignWorkoutPanel } from "@/components/workouts/AssignWorkoutPanel";
import { WorkoutEditModal } from "@/components/workouts/WorkoutEditModal";
import { WorkoutPreviewDetail } from "@/components/workouts/WorkoutPreviewDetail";

export function WorkoutAdminConsole() {
  const router = useRouter();
  const { currentUser, signOut, status, tokens } = useSession();
  const [workouts, setWorkouts] = useState<WorkoutRecord[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [editTarget, setEditTarget] = useState<WorkoutRecord | null>(null);
  const [assignTarget, setAssignTarget] = useState<WorkoutRecord | null>(null);
  const [previewWorkoutId, setPreviewWorkoutId] = useState<string | null>(null);

  function clearAdminData() {
    setWorkouts([]);
  }

  const reloadAdminData = useCallback(async () => {
    if (status !== "authenticated" || !tokens?.access_token || !currentUser) return;
    if (currentUser.role !== "admin") return;

    try {
      const workoutList = await listAdminWorkouts(tokens.access_token);
      setWorkouts(workoutList);
      setMessage(null);
      setError(null);
    } catch (loadError) {
      if (loadError instanceof ApiError && (loadError.status === 401 || loadError.status === 403)) {
        clearAdminData();
        signOut();
        router.replace("/login?next=/admin/workouts");
        return;
      }

      setError(loadError instanceof Error ? loadError.message : "Failed to load admin workout data.");
    }
  }, [currentUser, router, signOut, status, tokens]);

  useEffect(() => {
    queueMicrotask(() => {
      void reloadAdminData();
    });
  }, [reloadAdminData]);

  useEffect(() => {
    if (!previewWorkoutId) return;
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") setPreviewWorkoutId(null);
    }
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [previewWorkoutId]);

  useEffect(() => {
    function handleUserSync(event: Event) {
      const detail = (event as CustomEvent<UserSyncDetail>).detail;

      if (!detail?.scopes.includes("admin_workouts")) {
        return;
      }

      void reloadAdminData();
    }

    window.addEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);

    return () => {
      window.removeEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);
    };
  }, [reloadAdminData]);

  async function runAction(action: string, effect: () => Promise<void>) {
    setBusyAction(action);
    setError(null);
    setMessage(null);

    try {
      await effect();
    } catch (actionError) {
      if (actionError instanceof ApiError) {
        if (actionError.status === 401 || actionError.status === 403) {
          signOut();
          router.replace("/login?next=/admin/workouts");
          return;
        }

        setError(actionError.message);
      } else {
        setError(actionError instanceof Error ? actionError.message : "Unexpected request failure");
      }
    } finally {
      setBusyAction(null);
    }
  }

  async function handleDeleteWorkout(workout: WorkoutRecord) {
    if (!tokens?.access_token) return;

    const confirmed = window.confirm(
      `Delete "${workout.title || "this workout"}" permanently?\n\nThis hard delete removes the workout definition, assigned workouts, related schedule slots and bookings, and execution history. Affected athletes and booked members will be notified that the coach changed their workout.`,
    );

    if (!confirmed) return;

    await runAction(`delete-${workout.id}`, async () => {
      await deleteWorkout(tokens.access_token, workout.id);
      setWorkouts((current) => current.filter((item) => item.id !== workout.id));
      setMessage(`Deleted "${workout.title || "workout"}".`);
    });
  }

  return (
    <main className="min-h-screen px-6 py-8 md:px-10 md:py-12" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-7xl space-y-8">
        <TransientHero label="workout management introduction">
        <section className="rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex flex-wrap items-start justify-between gap-6">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.28em] text-[var(--primary)]">Workouts</p>
              <h1 className="mt-2 max-w-3xl text-3xl font-semibold tracking-tight md:text-4xl" style={{ color: "var(--text)" }}>
                Workout content management.
              </h1>
              <p className="mt-4 max-w-3xl text-base leading-7" style={{ color: "var(--muted)" }}>
                Author and manage master workout definitions. Workouts can be assigned to athletes individually or used across class schedule slots.
              </p>
            </div>
          </div>

          <div className="mt-6 flex flex-wrap gap-3 text-sm font-semibold">
            <Link
              className="rounded-full px-4 py-2"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              href="/admin/workouts"
            >
              Workout list
            </Link>
            <Link
              className="rounded-full px-4 py-2 transition-colors"
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
              href="/admin/workouts/new"
            >
              New workout
            </Link>
            <Link
              className="rounded-full px-4 py-2 transition-colors"
              style={{ background: "transparent", border: "1px solid var(--border)", color: "var(--dim)" }}
              href="/admin/settings#level-taxonomy"
            >
              Level Taxonomy ↗
            </Link>
          </div>
        </section>
        </TransientHero>

        {!currentUser ? null : (
          <>
            {message ? (
              <section className="rounded-[1.8rem] px-5 py-4 text-sm font-semibold" style={{ background: "color-mix(in srgb, var(--success) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--success) 20%, transparent)", color: "var(--success)" }}>
                {message}
              </section>
            ) : null}

            {error ? (
              <section className="rounded-[1.8rem] px-5 py-4 text-sm" style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary-strong)" }}>
                {error}
              </section>
            ) : null}

            <section className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <div className="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>Master Workouts</p>
                  <h2 className="mt-2 text-2xl font-semibold" style={{ color: "var(--text)" }}>Saved workout definitions</h2>
                </div>

                <Link
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "var(--text)", color: "var(--bg)" }}
                  href="/admin/workouts/new"
                >
                  New workout
                </Link>
              </div>

              <div className="mt-6 grid gap-4 lg:grid-cols-2">
                {workouts.map((workout) => (
                  <article key={workout.id} className="rounded-[1.5rem] p-5" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", cursor: "pointer" }} onClick={() => setPreviewWorkoutId(workout.id)}>
                    <div className="flex items-center justify-between gap-4">
                      <div>
                        <div className="flex items-center gap-2">
                          <p className="text-lg font-semibold" style={{ color: "var(--text)" }}>{workout.title || "Untitled workout"}</p>
                          {workout.status === "draft" ? (
                            <span className="rounded-full px-2 py-1 text-[10px] font-semibold uppercase tracking-widest" style={{ background: "color-mix(in srgb, var(--warning) 12%, transparent)", color: "var(--warning)" }}>
                              Draft
                            </span>
                          ) : null}
                          {workout.is_team_workout ? (
                            <span className="rounded-full px-2 py-1 text-[10px] font-semibold uppercase tracking-widest" style={{ background: "color-mix(in srgb, var(--warning) 12%, transparent)", color: "var(--warning)", border: "1px solid color-mix(in srgb, var(--warning) 30%, transparent)" }}>
                              Team
                            </span>
                          ) : null}
                        </div>
                        <p className="mt-1 text-sm uppercase tracking-[0.18em] text-[var(--primary)]">{workout.type}</p>
                      </div>
                      <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--border)", color: "var(--muted)" }}>
                        {(workout.sections ?? []).length} section{(workout.sections ?? []).length === 1 ? "" : "s"}
                      </span>
                    </div>

                    <div className="mt-4 flex flex-wrap gap-2" onClick={(e) => e.stopPropagation()}>
                      {workout.status === "draft" ? (
                        <Link
                          className="rounded-full px-3 py-1 text-xs font-semibold"
                          style={{ background: "var(--text)", color: "var(--bg)" }}
                          href={`/admin/workouts/new?draft=${workout.id}`}
                          onClick={(e) => e.stopPropagation()}
                        >
                          Continue editing
                        </Link>
                      ) : null}

                      {workout.status === "published" ? (
                        <>
                          <button
                            className="rounded-full px-3 py-1 text-xs font-semibold"
                            style={{ background: "var(--text)", color: "var(--bg)" }}
                            onClick={(e) => { e.stopPropagation(); setAssignTarget(workout); }}
                            type="button"
                          >
                            Assign to athletes
                          </button>
                          <button
                            className="rounded-full px-3 py-1 text-xs font-semibold"
                            style={{ background: "var(--border)", color: "var(--text-soft)" }}
                            onClick={(e) => { e.stopPropagation(); setEditTarget(workout); }}
                            type="button"
                          >
                            Edit
                          </button>
                        </>
                      ) : null}

                      <button
                        className="rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50"
                        style={{ background: "color-mix(in srgb, var(--primary) 16%, transparent)", color: "var(--primary-strong)" }}
                        disabled={busyAction === `delete-${workout.id}`}
                        onClick={(e) => { e.stopPropagation(); void handleDeleteWorkout(workout); }}
                        type="button"
                      >
                        {busyAction === `delete-${workout.id}` ? "Deleting..." : "Delete"}
                      </button>

                      {workout.available_scale_levels.length > 0 ? (
                        workout.available_scale_levels.map((scaleLevel) => (
                          <span
                            key={`${workout.id}-${scaleLevel.slug}`}
                            className="rounded-full px-3 py-1 text-xs font-semibold"
                            style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)" }}
                          >
                            {scaleLevel.label}
                          </span>
                        ))
                      ) : (
                        <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--border)", color: "var(--dim)" }}>
                          Base only
                        </span>
                      )}
                    </div>

                    <div className="mt-4 space-y-2 text-sm" style={{ color: "var(--muted)" }}>
                      {(workout.sections ?? []).map((section) => (
                        <div key={`${workout.id}-${section.order}`} className="flex items-center justify-between gap-4">
                          <span>{section.name}</span>
                          <span style={{ color: "var(--dim)" }}>{section.exercises.length} exercises</span>
                        </div>
                      ))}
                    </div>
                  </article>
                ))}
              </div>
            </section>
          </>
        )}
      </div>

      {editTarget && tokens?.access_token ? (
        <WorkoutEditModal
          key={editTarget.id}
          workoutId={editTarget.id}
          workoutTitle={editTarget.title ?? "Untitled workout"}
          accessToken={tokens.access_token}
          context={{ kind: "global" }}
          onClose={() => setEditTarget(null)}
        />
      ) : null}

      {assignTarget ? (
        <AssignWorkoutPanel
          workoutId={assignTarget.id}
          onClose={() => setAssignTarget(null)}
          onAssigned={() => {
            setAssignTarget(null);
            void listAdminWorkouts(tokens!.access_token!).then(setWorkouts).catch(() => undefined);
          }}
        />
      ) : null}

      {previewWorkoutId ? (() => {
        const pw = workouts.find((w) => w.id === previewWorkoutId);
        if (!pw) return null;
        return (
          <>
            <div
              className="fixed inset-0 z-40"
              style={{ background: "rgba(0,0,0,0.45)" }}
              onClick={() => setPreviewWorkoutId(null)}
            />
            <aside
              className="fixed right-0 top-0 z-50 flex h-full flex-col overflow-hidden"
              style={{
                width: "min(480px, 90vw)",
                background: "var(--panel)",
                borderLeft: "1px solid var(--border)",
                boxShadow: "-8px 0 32px rgba(0,0,0,0.18)",
              }}
            >
              <div className="flex shrink-0 items-start justify-between gap-4 border-b px-6 py-5" style={{ borderColor: "var(--border)" }}>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>{pw.type}</p>
                  <h2 className="mt-1 text-xl font-semibold" style={{ color: "var(--text)" }}>{pw.title || "Untitled workout"}</h2>
                  <p className="mt-1 text-sm" style={{ color: "var(--dim)" }}>
                    {pw.sections.length} section{pw.sections.length === 1 ? "" : "s"} · {pw.available_scale_levels.length > 0 ? `${pw.available_scale_levels.length} scale level${pw.available_scale_levels.length === 1 ? "" : "s"}` : "Base only"}
                  </p>
                </div>
                <button
                  className="shrink-0 rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "var(--border)", color: "var(--text-soft)" }}
                  onClick={() => setPreviewWorkoutId(null)}
                  type="button"
                >
                  Close
                </button>
              </div>
              <div className="flex-1 overflow-y-auto px-6 py-5">
                <WorkoutPreviewDetail sections={pw.sections} initiallyExpanded />
              </div>
            </aside>
          </>
        );
      })() : null}
    </main>
  );
}
