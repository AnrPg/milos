"use client";

import { useMemo, useState, type ReactNode } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchAssignedWorkoutWeek } from "@/api/assigned-workouts";
import { listMyExecutions } from "@/api/executions";
import { fetchSchedule, type ScheduleSlot } from "@/api/schedule";
import { fetchTrainingLogSources } from "@/api/training-log";
import { useWorkoutLauncher } from "@/components/client/use-workout-launcher";
import { HubButton, HubCard } from "@/components/member-app/HubParts";
import { NextBookingActions } from "@/components/member-app/box/NextBookingActions";
import {
  buildTodayTraining,
  defaultTodayItem,
  localIsoDate,
  logSourceFor,
  type TodayTrainingItem,
} from "@/components/member-app/box/today-training";
import { useSession } from "@/components/session-provider";
import {
  TRAINING_LOG_SOURCES_KEY,
  TrainingLogDialog,
  type TrainingLogDialogState,
} from "@/components/training-log/TrainingLog";
import { MyInjuryWarningsPanel } from "@/components/wellbeing/InjuryWarnings";
import { MyWorkoutScaling } from "@/components/scaling/MyWorkoutScaling";
import { WorkoutContentBlock } from "@/components/workouts/WorkoutContent";
import { WorkoutPreviewDetail } from "@/components/workouts/WorkoutPreviewDetail";
import { WodGoalsStrip } from "@/components/wod-goals/WodGoalsStrip";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { dateKeyInZone, formatInZone, zonedText } from "@/lib/zoned-time";
import { useOrganizationTimeZone } from "@/lib/organization-slug";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { SPARK_GO_STYLE } from "@/lib/spark";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

export function useBoxSchedule(token: string | null, now: Date) {
  const window = useMemo(() => {
    const start = new Date(now);
    start.setHours(0, 0, 0, 0);
    return { startAt: start.toISOString(), endAt: new Date(start.getTime() + WEEK_MS).toISOString() };
  }, [now]);
  return useQuery({
    queryKey: ["box", "schedule", window.startAt],
    enabled: Boolean(token),
    queryFn: () => fetchSchedule(token!, { ...window, days: 7, classTypeIds: [] }),
    staleTime: 60_000,
  });
}

/** The next class the member holds a place in, still running or upcoming. */
export function nextBooking(slots: ScheduleSlot[], now: Date) {
  return (
    slots
      .filter((slot) => ["approved", "pending", "waitlisted"].includes(slot.current_user_booking?.status ?? ""))
      .filter((slot) => new Date(slot.scheduled_at).getTime() + slot.duration_minutes * 60_000 > now.getTime())
      .sort((a, b) => a.scheduled_at.localeCompare(b.scheduled_at))[0] ?? null
  );
}

/**
 * Box's first two slots (brief §7.4, mockup 08): today's workout with
 * Καταγραφή / Έναρξη ▶, then the next booking. Both keep their place with an
 * empty state, so the screen never reflows (brief §4.2).
 */
export function BoxToday({
  nextSession,
  emptyAction,
}: {
  /** ADR-170: an independent coach's Box shows the next session, not a class. */
  nextSession?: ReactNode;
  emptyAction?: { href: string; label: string };
} = {}) {
  const t = useTranslations("MemberApp");
  const tCheckIn = useTranslations("CheckIn");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const now = useMemo(() => new Date(), []);
  const gymZone = useOrganizationTimeZone();
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [logDialog, setLogDialog] = useState<TrainingLogDialogState>({ mode: "closed" });
  const launcher = useWorkoutLauncher();

  const schedule = useBoxSchedule(token, now);
  const assignments = useQuery({
    queryKey: ["box", "assignments", localIsoDate(now)],
    enabled: Boolean(token),
    queryFn: () => fetchAssignedWorkoutWeek(token!, localIsoDate(now)),
    staleTime: 60_000,
  });
  const executions = useQuery({
    queryKey: ["executions", "mine"],
    enabled: Boolean(token),
    queryFn: () => listMyExecutions(token!),
    staleTime: 30_000,
  });
  const logSources = useQuery({
    queryKey: TRAINING_LOG_SOURCES_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchTrainingLogSources(token!),
    staleTime: 60_000,
  });

  const today = useMemo(
    () =>
      buildTodayTraining({
        now,
        scheduleSlots: schedule.data?.slots ?? [],
        assignments: assignments.data?.assignments ?? [],
        executions: executions.data ?? [],
      }),
    [now, schedule.data, assignments.data, executions.data],
  );
  const selected =
    today.items.find((item) => item.key === selectedKey) ?? defaultTodayItem(today.items);
  const loading = schedule.isPending || assignments.isPending;
  const booking = nextBooking(schedule.data?.slots ?? [], now);
  // ADR-179: class times on the gym's clock.
  const time = (iso: string) => zonedText(iso, gymZone, locale, "time");
  const day = (iso: string) =>
    dateKeyInZone(iso, gymZone) === dateKeyInZone(now, gymZone)
      ? t("todayLabel")
      : formatInZone(iso, gymZone, locale, { weekday: "long", day: "numeric", month: "short" });

  function chipLabel(item: TodayTrainingItem) {
    return item.kind === "class" && item.scheduledAt
      ? t("classChip", { time: time(item.scheduledAt) })
      : item.seasonTitle
        ? t("seasonChip", { title: item.sourceName, season: item.seasonTitle })
        : t("programmeChip", { title: item.sourceName });
  }

  function openLog(item: TodayTrainingItem) {
    const source = logSourceFor(item, logSources.data);
    setLogDialog(source ? { mode: "create", source } : { mode: "pick" });
  }

  function start(item: TodayTrainingItem) {
    if (today.resumeExecutionId) return launcher.resume(today.resumeExecutionId);
    return launcher.launch({
      key: item.key,
      masterWorkoutId: item.workout.id,
      source: item.execution.source,
      sourceReferenceId: item.execution.referenceId,
    });
  }

  return (
    <>
      <HubCard eyebrow={t("todayWorkout")} highlighted>
        {loading ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : !selected ? (
          <div className="flex flex-col gap-3">
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("todayEmpty")}</p>
            <div className="flex gap-2">
              <HubButton href={emptyAction?.href ?? "/box/schedule"}>{emptyAction?.label ?? t("bookClass")}</HubButton>
              {today.resumeExecutionId ? (
                <button
                  type="button"
                  className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                  onClick={() => launcher.resume(today.resumeExecutionId!)}
                >
                  {t("resumeWorkout")} ▶
                </button>
              ) : null}
            </div>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {today.items.length > 1 ? (
              <SegmentPicker
                ariaLabel={t("todaySources")}
                value={selected.key}
                onChange={setSelectedKey}
                options={today.items.map((item) => ({ value: item.key, label: `${chipLabel(item)}${item.completed ? " ✓" : ""}` }))}
              />
            ) : (
              <p className="text-xs font-bold" style={{ color: "var(--primary-strong)" }}>{chipLabel(selected)}</p>
            )}

            <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{selected.workout.title}</h2>
            {selected.kind === "programme" && !selected.completed ? (
              <Link
                href={`/box/workouts?open_assignment=${encodeURIComponent(selected.execution.referenceId)}`}
                className="self-start text-sm font-semibold"
                style={{ color: "var(--primary-strong)" }}
              >
                {t("programmeManage")} ›
              </Link>
            ) : null}
            <WorkoutContentBlock entries={selected.workout.content} lead={selected.instructions} />
            <WorkoutPreviewDetail
              sections={selected.workout.sections as Parameters<typeof WorkoutPreviewDetail>[0]["sections"]}
              initiallyExpanded={false}
              authoringMode={selected.workout.authoring_mode}
              freeTextBody={selected.workout.free_text_body}
              freeTextDocument={selected.workout.free_text_document}
            />
            <WodGoalsStrip workoutId={selected.workout.id} />

            {token ? (
              <MyInjuryWarningsPanel
                accessToken={token}
                workoutId={selected.workout.id}
                surface={selected.injuryContext.surface}
                sourceContextId={selected.injuryContext.id}
              />
            ) : null}
            {token ? <MyWorkoutScaling token={token} workoutId={selected.workout.id} /> : null}

            {launcher.error ? (
              <ErrorNotice>{localizeError(launcher.error, i18n)}</ErrorNotice>
            ) : null}

            <div className="flex gap-2">
              <button
                type="button"
                className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
                style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
                onClick={() => openLog(selected)}
                disabled={selected.completed}
              >
                {selected.completed ? t("logged") : t("logWorkout")}
              </button>
              <button
                type="button"
                className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold disabled:opacity-60"
                style={SPARK_GO_STYLE}
                onClick={() => void start(selected)}
                disabled={launcher.pendingKey !== null}
              >
                {today.resumeExecutionId ? t("resumeWorkout") : t("startWorkout")} ▶
              </button>
            </div>
          </div>
        )}
      </HubCard>

      {nextSession ?? (
      <HubCard eyebrow={t("nextSession")}>
        {schedule.isPending ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : booking ? (
          <div className="flex flex-col gap-3">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="truncate text-lg font-extrabold" style={{ color: "var(--text)" }}>
                  {day(booking.scheduled_at)} {time(booking.scheduled_at)} · {booking.name || booking.class_type?.name}
                </p>
                <p className="truncate text-sm" style={{ color: "var(--dim)" }}>{booking.workout?.title ?? ""}</p>
              </div>
              <span
                className="shrink-0 rounded-full px-3 py-1 text-xs font-bold"
                style={{ background: "color-mix(in srgb, var(--success) 16%, transparent)", color: "var(--success)" }}
              >
                {t(`bookingStatus.${booking.current_user_booking?.status ?? "approved"}`)}
              </span>
            </div>
            <NextBookingActions slot={booking} />
            <div className="flex gap-2">
              <Link
                href={`/box/schedule?open_slot=${encodeURIComponent(booking.id)}`}
                className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
                style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
              >
                {t("manageBooking")}
              </Link>
              <Link
                href="/box/check-in"
                className="flex min-h-11 flex-1 items-center justify-center gap-2 rounded-2xl px-4 text-sm font-bold"
                style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
              >
                <QrGlyph />
                {tCheckIn("qrCheckIn")}
              </Link>
            </div>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("noBooking")}</p>
            <HubButton href="/box/schedule">{t("bookClass")}</HubButton>
          </div>
        )}
      </HubCard>
      )}

      {logDialog.mode !== "closed" && token ? (
        <TrainingLogDialog
          state={logDialog}
          token={token}
          onNavigate={setLogDialog}
          onClose={() => setLogDialog({ mode: "closed" })}
        />
      ) : null}
    </>
  );
}

/** The QR glyph on «QR check-in» (ADR-155). */
function QrGlyph() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <rect x="3" y="3" width="7" height="7" rx="1" />
      <rect x="14" y="3" width="7" height="7" rx="1" />
      <rect x="3" y="14" width="7" height="7" rx="1" />
      <path d="M14 14h3v3M21 14v.01M14 21h3M21 18v3h-3" />
    </svg>
  );
}
