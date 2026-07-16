"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

import { ApiError } from "@/api/client";
import { assignWorkout, listAthletes, type AthleteOption } from "@/api/assigned-workouts";
import { deleteWorkout, fetchAdminWorkout, type WorkoutRecord } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { formatLocalDate } from "@/lib/local-date";

type AssignWorkoutFormProps = {
  workoutId: string;
};

export function AssignWorkoutForm({ workoutId }: AssignWorkoutFormProps) {
  const i18n = useUiTranslations();
  const router = useRouter();
  const { tokens, signOut } = useSession();
  const [workout, setWorkout] = useState<WorkoutRecord | null>(null);
  const [athletes, setAthletes] = useState<AthleteOption[]>([]);
  const [query, setQuery] = useState("");
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [scheduledFor, setScheduledFor] = useState(() => formatLocalDate(new Date()));
  const [adminNotes, setAdminNotes] = useState("");
  const [loading, setLoading] = useState(true);
  const [athletesLoading, setAthletesLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!tokens?.access_token) return;

    let cancelled = false;

    fetchAdminWorkout(tokens.access_token, workoutId)
      .then((nextWorkout) => {
        if (cancelled) return;
        setWorkout(nextWorkout);
        setError(
          nextWorkout.status && nextWorkout.status !== "published"
            ? i18n("onlyPublishedWorkoutsCanBeAssignedToAthletes12a81f1")
            : null,
        );
      })
      .catch((requestError) => {
        if (cancelled) return;

        if (requestError instanceof ApiError && (requestError.status === 401 || requestError.status === 403)) {
          signOut();
          router.replace("/login?next=/admin/workouts");
          return;
        }

        setError(requestError instanceof Error ? requestError.message : i18n("couldNotLoadAssignmentDataea4b017"));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [router, signOut, tokens?.access_token, workoutId]);

  useEffect(() => {
    if (!tokens?.access_token) return;

    let cancelled = false;

    const timeoutId = window.setTimeout(() => {
      void listAthletes(tokens.access_token!, query)
        .then((nextAthletes) => {
          if (!cancelled) setAthletes(nextAthletes);
        })
        .catch((requestError) => {
          if (cancelled) return;

          if (requestError instanceof ApiError && (requestError.status === 401 || requestError.status === 403)) {
            signOut();
            router.replace("/login?next=/admin/workouts");
            return;
          }

          setError(requestError instanceof Error ? requestError.message : i18n("couldNotLoadAthletesb7948e1"));
        })
        .finally(() => {
          if (!cancelled) setAthletesLoading(false);
        });
    }, 150);

    return () => {
      cancelled = true;
      window.clearTimeout(timeoutId);
    };
  }, [query, router, signOut, tokens?.access_token]);

  async function submitAssignment() {
    if (!tokens?.access_token) return;

    setSaving(true);
    setError(null);

    try {
      await assignWorkout(tokens.access_token, {
        master_workout_id: workoutId,
        athlete_ids: selectedIds,
        scheduled_for: scheduledFor,
        admin_notes: adminNotes.trim() || undefined,
      });

      router.push("/my-workouts");
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : i18n("couldNotAssignWorkout58ad222"));
    } finally {
      setSaving(false);
    }
  }

  async function handleDeleteWorkout() {
    if (!tokens?.access_token || !workout) return;

    const confirmed = window.confirm(
      i18n("delete63346e8") + (workout.title) + i18n("permanentlyThisHardDeleteRemovesTheWorkoutDefinitionbb6e054"),
    );

    if (!confirmed) return;

    setDeleting(true);
    setError(null);

    try {
      await deleteWorkout(tokens.access_token, workout.id);
      router.push("/admin/workouts");
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : i18n("couldNotDeleteWorkout234fe2c"));
      setDeleting(false);
    }
  }

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-5xl space-y-8">
        <section className="rounded-[2.4rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex flex-wrap items-start justify-between gap-6">
            <div className="max-w-3xl">
              <p className="text-sm font-semibold uppercase tracking-[0.28em] text-[var(--primary)]">{i18n("assignWorkout08abff8")}</p>
              <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>
                {i18n("sendAPublishedWorkoutToOneOrMorefde1785")}
              </h1>
              <p className="mt-4 text-base leading-7" style={{ color: "var(--muted)" }}>
                {i18n("chooseAthletesPickADateAndAttachAnyfc98201")}
              </p>
            </div>

            <div className="flex shrink-0 flex-wrap gap-3">
              {workout ? (
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold transition-colors disabled:opacity-50"
                  style={{ background: "color-mix(in srgb, var(--primary) 16%, transparent)", color: "var(--primary-strong)" }}
                  disabled={deleting}
                  onClick={() => void handleDeleteWorkout()}
                  type="button"
                >
                  {deleting ? i18n("deletinge16cac6") : i18n("deleteWorkout6aa765c")}
                </button>
              ) : null}
              <Link
                className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
                href="/admin/workouts"
              >
                {i18n("backToWorkoutsdc51930")}
              </Link>
            </div>
          </div>
        </section>

        {error ? (
          <section className="rounded-[1.8rem] px-5 py-4 text-sm" style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary-strong)" }}>
            {error}
          </section>
        ) : null}

        <section className="grid gap-6 lg:grid-cols-[1.05fr_0.95fr]">
          <article className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <p className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{i18n("workout39463a5")}</p>
            {loading || !workout ? (
              <p className="mt-4 text-sm" style={{ color: "var(--dim)" }}>{i18n("loadingWorkoutaf4002f")}</p>
            ) : (
              <>
                <h2 className="mt-3 text-2xl font-semibold" style={{ color: "var(--text)" }}>{workout.title}</h2>
                <p className="mt-2 text-sm uppercase tracking-[0.18em] text-[var(--primary)]">{workout.type}</p>
                <div className="mt-5 space-y-3">
                  {workout.sections.map((section) => (
                    <div key={section.id ?? (workout.id) + "-" + (section.order)} className="rounded-[1.3rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                      <div className="flex items-center justify-between gap-4">
                        <p className="font-semibold" style={{ color: "var(--text)" }}>{section.name}</p>
                        <span className="text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                          {section.exercises.length} {i18n("exercises0ee6e81")}
                        </span>
                      </div>
                      <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>
                        {section.exercises.map((exercise) => exercise.name).join(" · ")}
                      </p>
                    </div>
                  ))}
                </div>
              </>
            )}
          </article>

          <article className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <label className="block">
              <span className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{i18n("dateeb9a4bc")}</span>
              <input
                className="mt-3 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                onChange={(event) => setScheduledFor(event.target.value)}
                type="date"
                value={scheduledFor}
              />
            </label>

            <label className="mt-5 block">
              <span className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{i18n("athleteSearch22491bf")}</span>
              <input
                className="mt-3 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                onChange={(event) => {
                  setAthletesLoading(true);
                  setQuery(event.target.value);
                }}
                placeholder={i18n("searchByNicknameac5a7b7")}
                value={query}
              />
            </label>

            <div className="mt-5 max-h-[20rem] space-y-3 overflow-y-auto pr-1">
              {athletes.map((athlete) => {
                const selected = selectedIds.includes(athlete.id);
                return (
                  <button
                    key={athlete.id}
                    className="flex w-full items-center justify-between rounded-[1.2rem] px-4 py-3 text-left transition-colors"
                    style={
                      selected
                        ? { background: "var(--primary)", color: "var(--bg)" }
                        : { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }
                    }
                    onClick={() =>
                      setSelectedIds((current) =>
                        current.includes(athlete.id)
                          ? current.filter((value) => value !== athlete.id)
                          : [...current, athlete.id],
                      )
                    }
                    type="button"
                  >
                    <span className="font-semibold">{athlete.nickname}</span>
                    <span className="text-xs uppercase tracking-[0.18em]">
                      {selected ? i18n("selected9a976fc") : i18n("tapToAdd22c76fc")}
                    </span>
                  </button>
                );
              })}
              {!athletesLoading && athletes.length === 0 ? (
                <p className="rounded-[1.2rem] px-4 py-5 text-sm" style={{ border: "1px dashed var(--border)", color: "var(--dim)" }}>
                  {i18n("noAthletesMatchedThatSearchd4f2c56")}
                </p>
              ) : null}
            </div>

            <label className="mt-5 block">
              <span className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{i18n("adminNotesdff73a2")}</span>
              <textarea
                className="mt-3 min-h-28 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                onChange={(event) => setAdminNotes(event.target.value)}
                placeholder={i18n("optionalProgrammingContextOrCuesa25eaae")}
                value={adminNotes}
              />
            </label>

            <div className="mt-6 flex flex-wrap items-center gap-3">
              <button
                className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--text)", color: "var(--bg)" }}
                disabled={saving || selectedIds.length === 0 || loading || Boolean(workout?.status && workout.status !== "published")}
                onClick={() => void submitAssignment()}
                type="button"
              >
                {saving ? i18n("assigningb89e1dc") : i18n("assignWorkout3e28a99")}
              </button>
              <p className="text-sm" style={{ color: "var(--dim)" }}>
                {selectedIds.length} {i18n("athlete2822571")}{selectedIds.length === 1 ? "" : i18n("sa0f1490")} {i18n("selected835f3b5")}
              </p>
            </div>
          </article>
        </section>
      </div>
    </main>
  );
}
