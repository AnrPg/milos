"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

import { ApiError } from "@/api/client";
import {
  listAdminWorkouts,
  listScaleLevels,
  replaceScaleLevels,
  type ScaleLevel,
  type WorkoutRecord,
} from "@/api/workouts";
import { useSession } from "@/components/session-provider";

export function WorkoutAdminConsole() {
  const router = useRouter();
  const { currentUser, signOut, status, tokens } = useSession();
  const [scaleLevels, setScaleLevels] = useState<ScaleLevel[]>([]);
  const [workouts, setWorkouts] = useState<WorkoutRecord[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busyAction, setBusyAction] = useState<string | null>(null);

  useEffect(() => {
    if (status !== "authenticated" || !tokens?.access_token || !currentUser) return;
    if (currentUser.role !== "admin") return;

    const accessToken = tokens.access_token;
    let cancelled = false;

    async function bootstrap() {
      try {
        const [levels, workoutList] = await Promise.all([
          listScaleLevels(accessToken),
          listAdminWorkouts(accessToken),
        ]);

        if (cancelled) return;

        setScaleLevels(levels);
        setWorkouts(workoutList);
        setMessage(null);
        setError(null);
      } catch (loadError) {
        if (cancelled) return;

        if (loadError instanceof ApiError && (loadError.status === 401 || loadError.status === 403)) {
          clearAdminData();
          signOut();
          router.replace("/login?next=/admin/workouts");
          return;
        }

        setError(loadError instanceof Error ? loadError.message : "Failed to load admin workout data.");
      }
    }

    void bootstrap();

    return () => {
      cancelled = true;
    };
  }, [currentUser, router, signOut, status, tokens?.access_token]);

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

  function clearAdminData() {
    setScaleLevels([]);
    setWorkouts([]);
  }

  async function saveScaleLevels() {
    if (!tokens?.access_token) return;

    await runAction("scale-levels", async () => {
      const updatedLevels = await replaceScaleLevels(tokens.access_token, {
        scale_levels: scaleLevels.map((scaleLevel, index) => ({
          slug: scaleLevel.slug,
          label: scaleLevel.label,
          sort_order: index + 1,
        })),
      });

      setScaleLevels(updatedLevels);
      setMessage("Scale levels saved.");
    });
  }

  return (
    <main className="min-h-screen bg-[radial-gradient(circle_at_top_left,rgba(217,93,57,0.14),transparent_26%),linear-gradient(180deg,#fffdf8_0%,#f5ede3_100%)] px-6 py-8 md:px-10 md:py-12">
      <div className="mx-auto max-w-7xl space-y-8">
        <section className="rounded-[2.4rem] border border-black/10 bg-white/80 p-7 shadow-[0_28px_80px_rgba(20,40,29,0.12)]">
          <div className="flex flex-wrap items-start justify-between gap-6">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.28em] text-accent-strong">Phase 2</p>
              <h1 className="mt-2 max-w-3xl text-4xl font-semibold tracking-tight text-slate-950 md:text-5xl">
                Workout content management with configurable scale levels.
              </h1>
              <p className="mt-4 max-w-3xl text-base leading-7 text-slate-600">
                This admin surface manages the global scale taxonomy first, then authors master workouts that inherit
                those scales uniformly across previews and API materialization.
              </p>
            </div>

            <div className="rounded-[1.6rem] border border-black/10 bg-[#14281d] px-5 py-4 text-white">
              <p className="text-xs uppercase tracking-[0.24em] text-white/60">Current route</p>
              <p className="mt-2 text-xl font-semibold">/admin/workouts</p>
            </div>
          </div>

          <div className="mt-6 flex flex-wrap gap-3 text-sm font-medium">
            <Link
              className="rounded-full bg-slate-950 px-4 py-2 text-white"
              href="/admin/workouts"
            >
              Workout list
            </Link>
            <Link
              className="rounded-full border border-black/10 bg-white px-4 py-2 text-slate-700"
              href="/admin/workouts/new"
            >
              New workout
            </Link>
          </div>
        </section>

        {!currentUser ? null : (
          <>
            <section className="rounded-[2rem] border border-black/10 bg-white/80 p-6 shadow-[0_20px_60px_rgba(20,40,29,0.08)]">
              <div className="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <p className="text-sm font-semibold uppercase tracking-[0.24em] text-slate-500">Authenticated admin</p>
                  <h2 className="mt-2 text-2xl font-semibold text-slate-950">{currentUser.nickname}</h2>
                </div>

                <button
                  className="rounded-full border border-black/10 bg-black/5 px-4 py-2 text-sm font-medium text-slate-700"
                  onClick={() => {
                    clearAdminData();
                    signOut();
                  }}
                  type="button"
                >
                  Clear admin session
                </button>
              </div>

              {message ? (
                <p className="mt-4 rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
                  {message}
                </p>
              ) : null}

              {error ? (
                <p className="mt-4 rounded-2xl border border-[#d95d39]/20 bg-[#d95d39]/10 px-4 py-3 text-sm text-[#a4462c]">
                  {error}
                </p>
              ) : null}
            </section>

            <section className="rounded-[2rem] border border-black/10 bg-white/85 p-6 shadow-[0_20px_60px_rgba(20,40,29,0.08)]">
              <div className="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <p className="text-sm font-semibold uppercase tracking-[0.24em] text-accent-strong">Scale Taxonomy</p>
                  <h2 className="mt-2 text-2xl font-semibold text-slate-950">Configure the app-wide scale ladder.</h2>
                </div>

                <button
                  className="rounded-full bg-[#d95d39] px-4 py-2 text-sm font-semibold text-white disabled:opacity-60"
                  disabled={busyAction === "scale-levels"}
                  onClick={saveScaleLevels}
                  type="button"
                >
                  {busyAction === "scale-levels" ? "Saving..." : "Save scale levels"}
                </button>
              </div>

              <div className="mt-6 space-y-3">
                {scaleLevels.map((scaleLevel, index) => (
                  <div key={scaleLevel.id || scaleLevel.slug || index} className="grid gap-3 rounded-[1.4rem] border border-black/10 bg-[#fbfaf7] p-4 md:grid-cols-[0.8fr_1fr_auto]">
                    <input
                      className="rounded-2xl border border-black/10 bg-white px-4 py-3 text-sm outline-none"
                      placeholder="slug"
                      value={scaleLevel.slug}
                      onChange={(event) =>
                        setScaleLevels((current) =>
                          current.map((item, currentIndex) =>
                            currentIndex === index ? { ...item, slug: event.target.value } : item,
                          ),
                        )
                      }
                    />
                    <input
                      className="rounded-2xl border border-black/10 bg-white px-4 py-3 text-sm outline-none"
                      placeholder="Display label"
                      value={scaleLevel.label}
                      onChange={(event) =>
                        setScaleLevels((current) =>
                          current.map((item, currentIndex) =>
                            currentIndex === index ? { ...item, label: event.target.value } : item,
                          ),
                        )
                      }
                    />
                    <button
                      className="rounded-full border border-black/10 px-4 py-2 text-sm text-slate-600"
                      onClick={() =>
                        setScaleLevels((current) =>
                          current.length === 1 ? current : current.filter((_, currentIndex) => currentIndex !== index),
                        )
                      }
                      type="button"
                    >
                      Remove
                    </button>
                  </div>
                ))}
              </div>

              <button
                className="mt-4 rounded-full border border-black/10 bg-black/5 px-4 py-2 text-sm font-medium text-slate-700"
                onClick={() =>
                  setScaleLevels((current) => [
                    ...current,
                    {
                      id: `draft-${current.length + 1}`,
                      slug: "",
                      label: "",
                      sort_order: current.length + 1,
                      is_active: true,
                    },
                  ])
                }
                type="button"
              >
                + Add scale level
              </button>
            </section>
            <section className="rounded-[2rem] border border-black/10 bg-white/85 p-6 shadow-[0_20px_60px_rgba(20,40,29,0.08)]">
              <div className="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <p className="text-sm font-semibold uppercase tracking-[0.24em] text-slate-500">Master Workouts</p>
                  <h2 className="mt-2 text-2xl font-semibold text-slate-950">Saved workout definitions</h2>
                </div>

                <Link
                  className="rounded-full bg-slate-950 px-4 py-2 text-sm font-semibold text-white"
                  href="/admin/workouts/new"
                >
                  New workout
                </Link>
              </div>

              <div className="mt-6 grid gap-4 lg:grid-cols-2">
                {workouts.map((workout) => (
                  <article key={workout.id} className="rounded-[1.5rem] border border-black/10 bg-[#fbfaf7] p-5">
                    <div className="flex items-center justify-between gap-4">
                      <div>
                        <div className="flex items-center gap-2">
                          <p className="text-lg font-semibold text-slate-950">{workout.title || "Untitled workout"}</p>
                          {workout.status === "draft" ? (
                            <span className="rounded-full bg-amber-100 px-2 py-1 text-[10px] font-semibold uppercase tracking-widest text-amber-700">
                              Draft
                            </span>
                          ) : null}
                        </div>
                        <p className="mt-1 text-sm uppercase tracking-[0.18em] text-slate-500">{workout.type}</p>
                      </div>
                      <span className="rounded-full border border-black/10 px-3 py-1 text-xs font-semibold text-slate-600">
                        {workout.sections.length} section{workout.sections.length === 1 ? "" : "s"}
                      </span>
                    </div>

                    <div className="mt-4 flex flex-wrap gap-2">
                      {workout.available_scale_levels.length > 0 ? (
                        workout.available_scale_levels.map((scaleLevel) => (
                          <span
                            key={`${workout.id}-${scaleLevel.slug}`}
                            className="rounded-full bg-[#d95d39]/10 px-3 py-1 text-xs font-semibold text-[#a4462c]"
                          >
                            {scaleLevel.label}
                          </span>
                        ))
                      ) : (
                        <span className="rounded-full bg-slate-950/5 px-3 py-1 text-xs font-semibold text-slate-600">
                          Base only
                        </span>
                      )}
                    </div>

                    <div className="mt-4 space-y-2 text-sm text-slate-600">
                      {workout.sections.map((section) => (
                        <div key={`${workout.id}-${section.order}`} className="flex items-center justify-between gap-4">
                          <span>{section.name}</span>
                          <span>{section.exercises.length} exercises</span>
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
    </main>
  );
}
