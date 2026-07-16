"use client";





import {useUiTranslations} from "@/i18n/ui";
import React, { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useDrag } from "@use-gesture/react";

import { fetchTimerSequence, startExecution } from "@/api/executions";
import { fetchSchedule, type ClassTypeRecord, type ScheduleSlot } from "@/api/schedule";
import {
  fetchMaterializedWorkout,
  type WorkoutRecord,
} from "@/api/workouts";
import { AuthGuard } from "@/components/auth-guard";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";
import { subscribeToTopic } from "@/lib/realtime";
import { useExecutionStore } from "@/stores/execution";

type Step = "type" | "week" | "preview";

type WorkoutOption = {
  slug: string | null;
  label: string;
  workout: WorkoutRecord;
};

function formatDate(d: Date): string {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function startOfWeek(d: Date): Date {
  const date = new Date(d);
  const day = date.getDay();
  const diff = (day === 0 ? -6 : 1) - day;
  date.setDate(date.getDate() + diff);
  date.setHours(0, 0, 0, 0);
  return date;
}

function formatDayLabel(iso: string): string {
  const d = new Date(`${iso}T00:00:00`);
  return d.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
}

function scaleTone(label: string) {
  const normalized = label.toLowerCase();

  if (normalized.includes("beginner") || normalized.includes("scaled")) {
    return {
      background: "color-mix(in srgb, var(--success) 14%, transparent)",
      border: "color-mix(in srgb, var(--success) 50%, transparent)",
      text: "var(--success)",
    };
  }

  if (normalized.includes("intermediate") || normalized === "base" || normalized === "rx") {
    return {
      background: "color-mix(in srgb, var(--warning) 14%, transparent)",
      border: "color-mix(in srgb, var(--warning) 50%, transparent)",
      text: "var(--warning)",
    };
  }

  return {
    background: "color-mix(in srgb, var(--primary) 14%, transparent)",
    border: "color-mix(in srgb, var(--primary) 50%, transparent)",
    text: "var(--primary-strong)",
  };
}

function WorkoutsPageContent() {
  const i18n = useUiTranslations();
  const router = useRouter();
  const { tokens } = useSession();
  const initExecution = useExecutionStore((s) => s.initExecution);

  const [step, setStep] = useState<Step>("type");
  const [classTypes, setClassTypes] = useState<ClassTypeRecord[]>([]);
  const [selectedClassType, setSelectedClassType] = useState<ClassTypeRecord | null>(null);
  const [weekStart, setWeekStart] = useState(() => startOfWeek(new Date()));
  const [slots, setSlots] = useState<ScheduleSlot[]>([]);
  const [loadingSlots, setLoadingSlots] = useState(false);
  const [loadingOptions, setLoadingOptions] = useState(false);
  const [selectedSlot, setSelectedSlot] = useState<ScheduleSlot | null>(null);
  const [selectedWorkout, setSelectedWorkout] = useState<WorkoutRecord | null>(null);
  const [selectedScale, setSelectedScale] = useState<string | null>(null);
  const [launching, setLaunching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [workoutOptionsById, setWorkoutOptionsById] = useState<Record<string, WorkoutOption[]>>({});

  function shiftWeek(days: number) {
    setWeekStart((current) => {
      const next = new Date(current);
      next.setDate(next.getDate() + days);
      return next;
    });
  }

  const bindWeekSwipe = useDrag(
    ({ last, movement: [mx] }) => {
      if (!last || Math.abs(mx) < 48) {
        return;
      }

      shiftWeek(mx > 0 ? -7 : 7);
    },
    { axis: "x", filterTaps: true },
  );

  const accessToken = tokens?.access_token;

  useEffect(() => {
    if (!accessToken) return;

    const start = startOfWeek(new Date());
    const end = new Date(start);
    end.setDate(end.getDate() + 7);

    void fetchSchedule(accessToken, {
      startAt: start.toISOString(),
      endAt: end.toISOString(),
      days: 7,
      classTypeIds: [],
    }).then((schedule) => setClassTypes(schedule.class_types)).catch(() => setClassTypes([]));
  }, [accessToken]);

  const loadWeek = useCallback(async () => {
    if (step !== "week" || !accessToken || !selectedClassType) return;

    let cancelled = false;

    setLoadingSlots(true);
    setLoadingOptions(true);
    setError(null);

    const endDate = new Date(weekStart);
    endDate.setDate(endDate.getDate() + 7);

    try {
      const schedule = await fetchSchedule(accessToken, {
        startAt: weekStart.toISOString(),
        endAt: endDate.toISOString(),
        days: 7,
        classTypeIds: [selectedClassType.id],
      });

      if (cancelled) return;
      setSlots(schedule.slots);

      const uniqueWorkoutIds = Array.from(
        new Set(
          schedule.slots
            .map((slot) => slot.workout?.id)
            .filter((id): id is string => Boolean(id)),
        ),
      );

      const details = await Promise.allSettled(
        uniqueWorkoutIds.map(async (workoutId) => {
          const materialized = await fetchMaterializedWorkout(accessToken, workoutId);

          const options: WorkoutOption[] = [
            { slug: null, label: i18n("base077fe9c"), workout: materialized.workout },
            ...materialized.scales.map((scaleWorkout) => ({
              slug: scaleWorkout.scale_level?.slug ?? null,
              label: scaleWorkout.scale_level?.label ?? i18n("scalea29f025"),
              workout: scaleWorkout,
            })),
          ];

          return [workoutId, options] as const;
        }),
      );

      if (cancelled) return;

      const nextOptions: Record<string, WorkoutOption[]> = {};

      for (const detail of details) {
        if (detail.status === "fulfilled") {
          const [workoutId, options] = detail.value;
          nextOptions[workoutId] = options;
        }
      }

      setWorkoutOptionsById(nextOptions);
    } catch {
      if (cancelled) return;
      setSlots([]);
      setWorkoutOptionsById({});
      setError(i18n("couldNotLoadWorkoutsForThisWeek40a04ec"));
    } finally {
      if (!cancelled) {
        setLoadingSlots(false);
        setLoadingOptions(false);
      }
    }

    return () => {
      cancelled = true;
    };
  }, [accessToken, selectedClassType, step, weekStart]);

  useEffect(() => {
    let cleanup: (() => void) | undefined;

    queueMicrotask(() => {
      void loadWeek().then((teardown) => {
        cleanup = teardown;
      });
    });

    return () => {
      cleanup?.();
    };
  }, [loadWeek]);

  useEffect(() => {
    if (step !== "week" || !accessToken) return;

    return subscribeToTopic(accessToken, "schedule:lobby", {
      schedule_refresh: () => {
        void loadWeek();
      },
    });
  }, [accessToken, loadWeek, step]);

  const weekDays = useMemo(
    () =>
      Array.from({ length: 7 }, (_, i) => {
        const d = new Date(weekStart);
        d.setDate(d.getDate() + i);
        return formatDate(d);
      }),
    [weekStart],
  );

  const slotsByDate = useMemo(
    () =>
      slots.reduce<Record<string, ScheduleSlot[]>>((acc, slot) => {
        const date = slot.scheduled_at.split("T")[0];
        return { ...acc, [date]: [...(acc[date] ?? []), slot] };
      }, {}),
    [slots],
  );

  async function launchExecution() {
    if (!tokens?.access_token || !selectedSlot?.workout || !selectedWorkout) return;

    setLaunching(true);
    setError(null);

    try {
      const execution = await startExecution(tokens.access_token, {
        master_workout_id: selectedSlot.workout.id,
        scale_level_slug: selectedScale,
        source: "self_selected",
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      });

      const segments = await fetchTimerSequence(
        tokens.access_token,
        selectedSlot.workout.id,
        {
          scaleSlug: selectedScale,
          source: "self_selected",
        },
      );

      initExecution({
        executionId: execution.id,
        workoutId: selectedSlot.workout.id,
        scaleSlug: selectedScale,
        segments,
        checkedExerciseIds: execution.checked_exercise_ids,
        sectionScores: execution.section_scores,
        exerciseNotes: execution.exercise_notes,
        currentSegmentIndex: execution.current_segment_index,
        status: execution.status,
        segmentStartedAt: execution.segment_started_at_utc
          ? Date.parse(execution.segment_started_at_utc)
          : null,
        pausedElapsed: execution.paused_elapsed_ms,
        totalElapsedMs: execution.total_elapsed_ms,
        sectionElapsedMs: execution.section_elapsed_ms,
        segmentCycleCounts: execution.segment_cycle_counts,
        resumeCountdownEndsAt: execution.resume_countdown_ends_at_utc
          ? Date.parse(execution.resume_countdown_ends_at_utc)
          : null,
      });

      router.push(`/workouts/${execution.id}/execute`);
    } catch {
      setError(i18n("workoutCouldNotBeStartedc7410d6"));
      setLaunching(false);
    }
  }

  function selectWorkout(slot: ScheduleSlot, option: WorkoutOption) {
    setSelectedSlot(slot);
    setSelectedWorkout(option.workout);
    setSelectedScale(option.slug);
    setStep("preview");
    setError(null);
  }

  function renderWorkoutPreview(workout: WorkoutRecord) {
    return (
      <div className="space-y-4">
        {workout.sections.map((section) => (
          <section
            key={section.id ?? (String(section.name ?? i18n("sectionf2c6b56"))) + "-" + (section.order)}
            className="rounded-3xl border p-5"
            style={{
              background: "color-mix(in srgb, var(--panel) 78%, transparent)",
              borderColor: "var(--border)",
            }}
          >
            <div className="flex items-center justify-between gap-3">
              <h2 className="text-lg font-semibold">{section.name}</h2>
              {section.timer_config?.type ? (
                <span
                  className="rounded-full px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.18em]"
                  style={{
                    background: "color-mix(in srgb, var(--primary) 15%, transparent)",
                    border: "1px solid color-mix(in srgb, var(--primary) 35%, transparent)",
                    color: "var(--primary)",
                  }}
                >
                  {String(section.timer_config.type).replaceAll("_", " ")}
                </span>
              ) : null}
            </div>

            <div className="mt-4 space-y-3">
              {section.exercises.map((exercise) => (
                <div
                  key={exercise.id ?? (exercise.name) + "-" + (exercise.order)}
                  className="rounded-2xl border px-4 py-3"
                  style={{
                    background: "color-mix(in srgb, var(--panel-muted) 78%, transparent)",
                    borderColor: "color-mix(in srgb, var(--border-strong) 90%, transparent)",
                  }}
                >
                  <div className="text-sm font-semibold">{exercise.name}</div>
                  <div className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
                    {[
                      exercise.sets ? (exercise.sets) + " sets" : null,
                      exercise.prescription_value
                        ? (exercise.prescription_value) + " " + (exercise.prescription_unit ?? "").trim()
                        : null,
                      exercise.load_value
                        ? (exercise.load_value) + " " + (exercise.load_mode === "pct_1rm" ? "% RM" : "kg")
                        : exercise.load_mode === "bw"
                          ? "Bodyweight"
                          : null,
                    ]
                      .filter(Boolean)
                      .join(" · ") || i18n("customExecutionDetailsb430ba9")}
                  </div>
                </div>
              ))}
            </div>
          </section>
        ))}
      </div>
    );
  }

  if (step === "type") {
    return (
      <div
        className="min-h-screen p-6"
        style={{ background: "var(--bg)", color: "var(--text)" }}
      >
        <div className="mx-auto max-w-lg">
          <TransientHero label={i18n("workoutSelectionIntroductionb11d827")}>
            <div className="mb-5">
              <h1 className="text-2xl font-bold">{i18n("startWorkoutd1072dd")}</h1>
              <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
                {i18n("pickAClassTypeThenChooseADayd4c9a74")}
              </p>
            </div>
          </TransientHero>
          <div className="grid grid-cols-2 gap-3">
            {classTypes.map((classType) => (
              <button
                key={classType.id}
                onClick={() => {
                  setSelectedClassType(classType);
                  setSelectedSlot(null);
                  setSelectedWorkout(null);
                  setSelectedScale(null);
                  setStep("week");
                }}
                className="flex flex-col items-center gap-3 rounded-[28px] border px-4 py-7 text-center transition-transform hover:-translate-y-0.5"
                style={{
                  background:
                    "radial-gradient(circle at top, color-mix(in srgb, var(--primary) 16%, transparent), color-mix(in srgb, var(--panel) 92%, transparent) 62%)",
                  borderColor: "color-mix(in srgb, var(--primary) 18%, transparent)",
                }}
              >
                <span className="text-3xl">◆</span>
                <span className="text-sm font-semibold">{classType.name}</span>
              </button>
            ))}
            {classTypes.length === 0 ? <p className="col-span-2 text-sm" style={{ color: "var(--muted)" }}>{i18n("noActiveClassTypesAreAvailable16b92ac")}</p> : null}
          </div>
        </div>
      </div>
    );
  }

  if (step === "week") {
    return (
      <div
        className="min-h-screen"
        style={{ background: "var(--bg)", color: "var(--text)" }}
      >
        <div
          className="sticky top-0 z-10 px-4 py-4"
          style={{
            background:
              "linear-gradient(180deg, color-mix(in srgb, var(--bg) 98%, transparent), color-mix(in srgb, var(--bg) 88%, transparent))",
            borderBottom: "1px solid var(--border)",
          }}
        >
          <div className="mx-auto flex max-w-5xl items-center justify-between gap-3">
            <button
              onClick={() => setStep("type")}
              className="text-sm"
              style={{ color: "var(--muted)" }}
            >
              {i18n("backdc381ae")}
            </button>
            <div className="text-center">
              <div className="text-xs uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
                {selectedClassType?.name}
              </div>
              <div className="text-sm font-semibold">
                {weekStart.toLocaleDateString(undefined, { month: "short", day: "numeric" })} –{" "}
                {(() => {
                  const end = new Date(weekStart);
                  end.setDate(end.getDate() + 6);
                  return end.toLocaleDateString(undefined, { month: "short", day: "numeric" });
                })()}
              </div>
            </div>
            <div className="flex items-center gap-2">
              <button
                onClick={() => shiftWeek(-7)}
                className="h-9 w-9 rounded-full border text-lg"
                style={{ borderColor: "var(--border)", color: "var(--muted)" }}
              >
                ←
              </button>
              <button
                onClick={() => shiftWeek(7)}
                className="h-9 w-9 rounded-full border text-lg"
                style={{ borderColor: "var(--border)", color: "var(--muted)" }}
              >
                →
              </button>
            </div>
          </div>
        </div>

        <div {...bindWeekSwipe()} className="mx-auto max-w-5xl p-4 touch-pan-y">
          {error && (
            <div
              className="mb-4 rounded-3xl border px-4 py-3 text-sm"
              style={{
                background: "color-mix(in srgb, var(--primary) 12%, transparent)",
                borderColor: "color-mix(in srgb, var(--primary) 35%, transparent)",
                color: "var(--primary-strong)",
              }}
            >
              {error}
            </div>
          )}

          {loadingSlots ? (
            <div className="py-12 text-center text-sm" style={{ color: "var(--muted)" }}>
              {i18n("loadingWeekView9b97e58")}
            </div>
          ) : slots.length === 0 ? (
            <div className="py-12 text-center text-sm" style={{ color: "var(--muted)" }}>
              {i18n("no816c52f")} {selectedClassType?.name} {i18n("classesAreAvailableThisWeek291e151")}
            </div>
          ) : (
            <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
              {weekDays.map((date) => {
                const daySlots = slotsByDate[date] ?? [];

                return (
                  <section
                    key={date}
                    className="rounded-[30px] border p-4"
                    style={{
                      background:
                        "linear-gradient(180deg, color-mix(in srgb, var(--panel-raised) 96%, transparent), color-mix(in srgb, var(--panel) 96%, transparent))",
                      borderColor: "var(--border)",
                    }}
                  >
                    <div className="mb-4 flex items-baseline justify-between">
                      <h2 className="text-sm font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--text-soft)" }}>
                        {formatDayLabel(date)}
                      </h2>
                      <span className="text-xs" style={{ color: "var(--muted)" }}>
                        {daySlots.length} {i18n("option14eb14e")}{daySlots.length === 1 ? "" : i18n("sa0f1490")}
                      </span>
                    </div>

                    {daySlots.length === 0 ? (
                      <div className="rounded-2xl border border-dashed px-4 py-8 text-center text-sm" style={{ borderColor: "color-mix(in srgb, var(--border-strong) 90%, transparent)", color: "var(--muted)" }}>
                        {i18n("restDaye3a72d7")}
                      </div>
                    ) : (
                      <div className="space-y-4">
                        {daySlots.map((slot) => {
                          const options = slot.workout ? workoutOptionsById[slot.workout.id] ?? [] : [];

                          return (
                            <div
                              key={slot.id}
                              className="rounded-[26px] border p-4"
                              style={{
                                background: "color-mix(in srgb, var(--panel-muted) 90%, transparent)",
                                borderColor: "color-mix(in srgb, var(--border-strong) 90%, transparent)",
                              }}
                            >
                              <div className="flex items-center justify-between gap-3">
                                <div>
                                  <div className="text-sm font-semibold">
                                    {slot.workout?.title ?? i18n("untitledWorkout579b8a6")}
                                  </div>
                                  <div className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
                                    {formatTime(slot.scheduled_at)} · {slot.spots_remaining} {i18n("spotsLeftd65a24f")}
                                  </div>
                                </div>
                              </div>

                              <div className="mt-4 flex flex-wrap gap-2">
                                {options.length > 0 ? (
                                  options.map((option) => {
                                    const tone = scaleTone(option.label);

                                    return (
                                      <button
                                        key={(slot.id) + "-" + (option.slug ?? "base")}
                                        onClick={() => selectWorkout(slot, option)}
                                        className="rounded-full border px-3 py-1.5 text-xs font-semibold transition-transform hover:-translate-y-0.5"
                                        style={{
                                          background: tone.background,
                                          borderColor: tone.border,
                                          color: tone.text,
                                        }}
                                      >
                                        {option.label}
                                      </button>
                                    );
                                  })
                                ) : (
                                  <span className="text-xs" style={{ color: "var(--muted)" }}>
                                    {loadingOptions ? i18n("loadingScaleBoxes8f8f4e0") : i18n("workoutOptionsUnavailable3c866ef")}
                                  </span>
                                )}
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </section>
                );
              })}
            </div>
          )}
        </div>
      </div>
    );
  }

  if (!selectedSlot?.workout || !selectedWorkout) return null;

  return (
    <div
      className="min-h-screen px-4 py-6"
      style={{ background: "var(--bg)", color: "var(--text)" }}
    >
      <div className="mx-auto max-w-4xl">
        <button
          onClick={() => setStep("week")}
          className="mb-5 text-sm"
          style={{ color: "var(--muted)" }}
        >
          {i18n("backToWeekView1d615a5")}
        </button>

        <div
          className="mb-6 rounded-[32px] border p-6"
          style={{
            background:
              "linear-gradient(145deg, color-mix(in srgb, var(--primary) 12%, var(--panel-raised)), color-mix(in srgb, var(--panel) 98%, transparent) 56%, color-mix(in srgb, var(--panel-muted) 98%, transparent))",
            borderColor: "color-mix(in srgb, var(--primary) 18%, transparent)",
          }}
        >
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <div className="text-xs uppercase tracking-[0.2em]" style={{ color: "var(--primary-strong)" }}>
                {selectedWorkout.scale_level?.label ?? i18n("base077fe9c")}
              </div>
              <h1 className="mt-2 text-3xl font-bold">{selectedWorkout.title}</h1>
              <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>
                {formatDayLabel(selectedSlot.scheduled_at.split("T")[0])} · {formatTime(selectedSlot.scheduled_at)}
              </p>
            </div>

            <button
              onClick={() => void launchExecution()}
              disabled={launching}
              className="rounded-full px-6 py-3 text-sm font-bold disabled:opacity-40"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {launching ? i18n("startinge5f5809") : i18n("startWorkoutd1072dd")}
            </button>
          </div>
        </div>

        {error && (
          <div
            className="mb-4 rounded-3xl border px-4 py-3 text-sm"
            style={{
              background: "color-mix(in srgb, var(--primary) 12%, transparent)",
              borderColor: "color-mix(in srgb, var(--primary) 35%, transparent)",
              color: "var(--primary-strong)",
            }}
          >
            {error}
          </div>
        )}

        {renderWorkoutPreview(selectedWorkout)}
      </div>
    </div>
  );
}

export default function WorkoutsPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["member", "admin"]}>
      <WorkoutsPageContent />
    </AuthGuard>
  );
}
