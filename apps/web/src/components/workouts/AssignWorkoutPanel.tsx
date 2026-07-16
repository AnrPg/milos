"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useEffect, useState } from "react";

import { ApiError } from "@/api/client";
import { assignWorkout, listAthletes, type AthleteOption } from "@/api/assigned-workouts";
import { fetchAdminWorkout, type WorkoutRecord } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { formatLocalDate } from "@/lib/local-date";
import { SemanticLabel } from "@/components/semantic-label";

type Props = {
  workoutId: string;
  onClose: () => void;
  onAssigned: () => void;
};

export function AssignWorkoutPanel({ workoutId, onClose, onAssigned }: Props) {
  const i18n = useUiTranslations();
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
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!tokens?.access_token) return;

    let cancelled = false;

    fetchAdminWorkout(tokens.access_token, workoutId)
      .then((nextWorkout) => {
        if (cancelled) return;
        setWorkout(nextWorkout);
        if (nextWorkout.status && nextWorkout.status !== "published") {
          setError(i18n("onlyPublishedWorkoutsCanBeAssignedToAthletes12a81f1"));
        }
      })
      .catch((requestError) => {
        if (cancelled) return;
        if (requestError instanceof ApiError && (requestError.status === 401 || requestError.status === 403)) {
          signOut();
          return;
        }
        setError(requestError instanceof Error ? localizeError(requestError, i18n) : i18n("couldNotLoadWorkout548f9e9"));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [i18n, signOut, tokens?.access_token, workoutId]);

  useEffect(() => {
    if (!tokens?.access_token) return;

    let cancelled = false;

    const timeoutId = window.setTimeout(() => {
      void listAthletes(tokens.access_token!, query)
        .then((nextAthletes) => {
          if (!cancelled) setAthletes(nextAthletes);
        })
        .catch(() => {
          if (!cancelled) setAthletes([]);
        })
        .finally(() => {
          if (!cancelled) setAthletesLoading(false);
        });
    }, 150);

    return () => {
      cancelled = true;
      window.clearTimeout(timeoutId);
    };
  }, [query, tokens?.access_token]);

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

      onAssigned();
      onClose();
    } catch (requestError) {
      setError(requestError instanceof Error ? localizeError(requestError, i18n) : i18n("couldNotAssignWorkout58ad222"));
    } finally {
      setSaving(false);
    }
  }

  const isUnassignable = Boolean(workout?.status && workout.status !== "published");

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 z-40"
        style={{ background: "rgba(0,0,0,0.5)" }}
        onClick={onClose}
      />

      {/* Panel */}
      <div
        className="fixed inset-y-0 end-0 z-50 flex w-full flex-col overflow-hidden md:max-w-[480px]"
        style={{ background: "var(--bg)", borderInlineStart: "1px solid var(--border)" }}
      >
        {/* Sticky header */}
        <div
          className="sticky top-0 z-10 flex items-center justify-between gap-4 px-5 py-4"
          style={{ background: "var(--bg)", borderBottom: "1px solid var(--border)", minHeight: "3.25rem" }}
        >
          <div className="min-w-0">
            <p className="truncate text-xs font-semibold uppercase tracking-[0.2em] text-[var(--primary)]">
              {i18n("assignWorkout3e28a99")}
            </p>
            <h2 className="mt-0.5 truncate text-base font-bold" style={{ color: "var(--text)" }}>
              {loading ? i18n("loading33ce417") : (workout?.title ?? i18n("untitledWorkouta1885a5"))}
            </h2>
          </div>
          <button
            className="shrink-0 rounded-full px-3 py-1 text-xs font-semibold transition-colors"
            style={{ background: "var(--border)", color: "var(--muted)" }}
            onClick={onClose}
            type="button"
          >
            {i18n("closefeb3e25")}
          </button>
        </div>

        {/* Scrollable body */}
        <div className="flex-1 overflow-y-auto px-5 py-5 space-y-5">
          {error ? (
            <p
              className="rounded-[1rem] px-4 py-3 text-sm"
              style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary-strong)" }}
            >
              {error}
            </p>
          ) : null}

          {/* Workout summary */}
          {workout && !loading ? (
            <section
              className="rounded-[1.4rem] p-4 space-y-2"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--primary)]">
                <SemanticLabel value={workout.type} />
              </p>
              <div className="space-y-1">
                {workout.sections.map((section) => (
                  <div
                    key={section.id ?? (workout.id) + "-" + (section.order)}
                    className="flex items-center justify-between gap-3"
                  >
                    <span className="text-sm" style={{ color: "var(--text)" }}>{section.name}</span>
                    <span className="text-xs" style={{ color: "var(--dim)" }}>
                      {section.exercises.length} {i18n("exercises0ee6e81")}
                    </span>
                  </div>
                ))}
              </div>
            </section>
          ) : null}

          {/* Date */}
          <label className="block">
            <span className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
              {i18n("dateeb9a4bc")}
            </span>
            <input
              className="mt-2 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              onChange={(e) => setScheduledFor(e.target.value)}
              type="date"
              value={scheduledFor}
            />
          </label>

          {/* Athlete search */}
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
              {i18n("athletesda22204")}
              {selectedIds.length > 0 ? (
                <span
                  className="ms-2 rounded-full px-1.5 py-0.5 text-[10px]"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                >
                  {selectedIds.length} {i18n("selected835f3b5")}
                </span>
              ) : null}
            </p>
            <input
              className="mt-2 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              onChange={(e) => {
                setAthletesLoading(true);
                setQuery(e.target.value);
              }}
              placeholder={i18n("searchByNicknameac5a7b7")}
              value={query}
            />

            <div className="mt-3 max-h-56 space-y-2 overflow-y-auto pe-1">
              {athletes.map((athlete) => {
                const selected = selectedIds.includes(athlete.id);
                return (
                  <button
                    key={athlete.id}
                    className="flex w-full items-center justify-between rounded-[1rem] px-4 py-2.5 text-start text-sm transition-colors"
                    style={
                      selected
                        ? { background: "var(--primary)", color: "var(--bg)" }
                        : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }
                    }
                    onClick={() =>
                      setSelectedIds((current) =>
                        current.includes(athlete.id)
                          ? current.filter((id) => id !== athlete.id)
                          : [...current, athlete.id],
                      )
                    }
                    type="button"
                  >
                    <span className="font-semibold">{athlete.nickname}</span>
                    <span className="text-xs uppercase tracking-[0.18em]">
                      {selected ? i18n("selected9a976fc") : i18n("add61cc55a")}
                    </span>
                  </button>
                );
              })}
              {!athletesLoading && athletes.length === 0 ? (
                <p
                  className="rounded-[1rem] px-4 py-4 text-sm"
                  style={{ border: "1px dashed var(--border)", color: "var(--dim)" }}
                >
                  {i18n("noAthletesMatchedThatSearchd4f2c56")}
                </p>
              ) : null}
            </div>
          </div>

          {/* Admin notes */}
          <label className="block">
            <span className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
              {i18n("adminNotesdff73a2")}
            </span>
            <textarea
              className="mt-2 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
              style={{
                background: "var(--panel)",
                border: "1px solid var(--border)",
                color: "var(--text)",
                minHeight: "5rem",
                resize: "vertical",
              }}
              onChange={(e) => setAdminNotes(e.target.value)}
              placeholder={i18n("optionalProgrammingContextOrCuesa25eaae")}
              value={adminNotes}
            />
          </label>
        </div>

        {/* Bottom CTA */}
        <div
          className="border-t px-5 py-4"
          style={{ borderColor: "var(--border)", background: "var(--bg)" }}
        >
          <button
            className="w-full rounded-full py-3 text-sm font-bold tracking-wide disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            disabled={saving || selectedIds.length === 0 || loading || isUnassignable}
            onClick={() => void submitAssignment()}
            type="button"
          >
            {saving
              ? i18n("assigning4d16a1a")
              : selectedIds.length === 0
                ? i18n("selectAthletesToAssign1666500")
                : i18n("assignToAthletes", {count: selectedIds.length})}
          </button>
        </div>
      </div>
    </>
  );
}
