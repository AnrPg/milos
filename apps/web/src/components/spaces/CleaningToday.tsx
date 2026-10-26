"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  deleteCleaningSchedule,
  fetchCleaningSchedules,
  fetchCleaningToday,
  putCleaningSchedule,
  type CleaningDue,
  type CleaningSchedule,
} from "@/api/spaces";
import { FloorPlanCanvas, type PlanArea } from "@/components/spaces/FloorPlanCanvas";
import { dueStatus, orderDue, parseTimes, progress, shortTime, type DueStatus } from "@/components/spaces/cleaning-today";
import { validArea } from "@/components/spaces/floor-plan";
import {
  StaffPanel,
  StatusText,
  Pill,
  captionClass,
  captionStyle,
  inputClass,
  inputStyle,
  secondaryButtonClass,
  secondaryButtonStyle,
} from "@/components/staff/staff-ui";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { localizeError } from "@/i18n/presentation";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";

export const CLEANING_TODAY_KEY = ["staff", "cleaning", "today"] as const;
export const CLEANING_SCHEDULES_KEY = ["staff", "cleaning", "schedules"] as const;

const TONES: Record<DueStatus, PlanArea["tone"]> = { done: "done", due: "due", in_progress: "busy" };
const WEEKDAYS = [1, 2, 3, 4, 5, 6, 7];

/** ISO weekday (1 = Monday) in the viewer's language. */
function weekdayName(day: number, locale: string) {
  // 2024-01-01 was a Monday.
  return new Intl.DateTimeFormat(locale, { weekday: "short", timeZone: "UTC" }).format(new Date(Date.UTC(2024, 0, day)));
}

/**
 * «Σήμερα» of the cleaning log (ADR-202): the spaces due today by their
 * cleaning schedule. On a floor plan the janitor taps a space to start it;
 * without one, a plain list. Finishing stays the existing flow.
 */
export function CleaningToday({ token, canRecord, onStart }: { token: string; canRecord: boolean; onStart: (spaceId: string) => void }) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const today = useQuery({ queryKey: CLEANING_TODAY_KEY, enabled: Boolean(token), queryFn: () => fetchCleaningToday(token) });

  if (today.isPending) return null;
  if (today.isError) return <StatusText tone="error">{localizeError(today.error, ui)}</StatusText>;

  const open = (today.data.open_entries ?? []).map((entry) => ({ id: entry.id, area_id: entry.area_id }));
  const rows = orderDue(today.data.due ?? [], open);
  const { done, total } = progress(rows);
  const plans = (today.data.floor_plans ?? []).filter((plan) => rows.some((row) => row.floor_plan_id === plan.id && validArea(row.area)));
  const offPlan = rows.filter((row) => !plans.some((plan) => plan.id === row.floor_plan_id) || !validArea(row.area));
  const tap = (row: CleaningDue) => {
    if (canRecord && dueStatus(row, open) === "due") onStart(row.space_id);
  };

  return (
    <StaffPanel
      labelledBy="cleaning-today"
      eyebrow={t("todayEyebrow")}
      title={t("todayTitle")}
      actions={total > 0 ? <Pill tone={done === total ? "success" : "warning"}>{t("todayProgress", { done, total })}</Pill> : null}
    >
      {total === 0 ? (
        <StatusText tone="muted">{t("todayNothing")}</StatusText>
      ) : (
        <div className="flex flex-col gap-5" data-testid="cleaning-today">
          {plans.map((plan) => (
            <div key={plan.id} className="flex flex-col gap-2">
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{plan.name}</p>
              <FloorPlanCanvas
                testId={`today-plan-${plan.id}`}
                imageUrl={plan.image_url}
                alt={t("planAlt", { name: plan.name })}
                areas={rows
                  .filter((row) => row.floor_plan_id === plan.id && validArea(row.area))
                  .map((row) => ({ id: row.space_id, label: row.name, points: row.area!.points, tone: TONES[dueStatus(row, open)] }))}
                onAreaClick={canRecord ? (id) => {
                  const row = rows.find((item) => item.space_id === id);
                  if (row) tap(row);
                } : undefined}
              />
              <p className="text-xs" style={{ color: "var(--dim)" }}>{t("todayPlanHint")}</p>
            </div>
          ))}
          {offPlan.length > 0 ? (
            <ul className="flex flex-col gap-2" data-testid="cleaning-today-list">
              {offPlan.map((row) => (
                <DueRow key={row.space_id} row={row} status={dueStatus(row, open)} canRecord={canRecord} onStart={() => tap(row)} />
              ))}
            </ul>
          ) : null}
        </div>
      )}
    </StaffPanel>
  );
}

function DueRow({ row, status, canRecord, onStart }: { row: CleaningDue; status: DueStatus; canRecord: boolean; onStart: () => void }) {
  const t = useTranslations("Spaces");
  return (
    <li
      data-testid={`due-${row.space_id}`}
      data-status={status}
      className="flex flex-wrap items-center justify-between gap-3 rounded-2xl px-4 py-3"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <span className="flex flex-col">
        <span className="font-semibold" style={{ color: "var(--text)", textDecoration: status === "done" ? "line-through" : undefined }}>{row.name}</span>
        <span className="text-xs" style={{ color: "var(--dim)" }}>
          {row.times.length > 0 ? row.times.map(shortTime).join(" · ") : t("todayAnyTime")}
          {row.cleanings_due > 1 ? ` · ${t("todayCount", { done: row.cleanings_done, due: row.cleanings_due })}` : ""}
        </span>
        {row.comment ? <span className="text-xs" style={{ color: "var(--muted)" }}>{row.comment}</span> : null}
      </span>
      {status === "done" ? (
        <Pill tone="success">{t("todayDone")}</Pill>
      ) : status === "in_progress" ? (
        <Pill tone="primary">{t("todayInProgress")}</Pill>
      ) : canRecord ? (
        <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={onStart}>
          {t("todayStart")}
        </button>
      ) : (
        <Pill tone="warning">{t("todayDue")}</Pill>
      )}
    </li>
  );
}

/** The cleaning schedule of each space: which days, at what times, with a comment (ADR-202). */
export function CleaningSchedules({ token, spaces }: { token: string; spaces: { id: string; name: string }[] }) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const [editing, setEditing] = useState<{ id: string; name: string } | null>(null);
  const schedules = useQuery({ queryKey: CLEANING_SCHEDULES_KEY, enabled: Boolean(token), queryFn: () => fetchCleaningSchedules(token) });
  const bySpace = new Map((schedules.data ?? []).map((schedule) => [schedule.space_id, schedule]));

  return (
    <StaffPanel labelledBy="cleaning-schedules" title={t("scheduleTitle")}>
      <p className="mb-3 text-sm" style={{ color: "var(--muted)" }}>{t("scheduleIntro")}</p>
      {schedules.isError ? <StatusText tone="error">{localizeError(schedules.error, ui)}</StatusText> : null}
      {spaces.length === 0 ? (
        <StatusText tone="muted">{t("empty")}</StatusText>
      ) : (
        <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }} data-testid="cleaning-schedules">
          {spaces.map((space) => {
            const schedule = bySpace.get(space.id);
            return (
              <li key={space.id} className="flex flex-wrap items-center justify-between gap-3 py-3 text-sm">
                <span className="flex flex-col">
                  <span className="font-semibold" style={{ color: "var(--text)" }}>{space.name}</span>
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {schedule
                      ? [schedule.weekdays.map((day) => weekdayName(day, locale)).join(" "), schedule.times.map(shortTime).join(" · ")].filter(Boolean).join(" · ")
                      : t("scheduleNone")}
                  </span>
                </span>
                <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} data-testid={`schedule-edit-${space.id}`} onClick={() => setEditing(space)}>
                  {schedule ? t("edit") : t("scheduleAdd")}
                </button>
              </li>
            );
          })}
        </ul>
      )}
      {editing ? <ScheduleForm token={token} space={editing} schedule={bySpace.get(editing.id) ?? null} onClose={() => setEditing(null)} /> : null}
    </StaffPanel>
  );
}

function ScheduleForm({ token, space, schedule, onClose }: { token: string; space: { id: string; name: string }; schedule: CleaningSchedule | null; onClose: () => void }) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const [weekdays, setWeekdays] = useState<number[]>(schedule?.weekdays ?? [1, 2, 3, 4, 5]);
  const [times, setTimes] = useState((schedule?.times ?? []).map(shortTime).join(", "));
  const [comment, setComment] = useState(schedule?.comment ?? "");
  const parsed = parseTimes(times);
  const ready = weekdays.length > 0 && parsed !== null;
  const refresh = async () => {
    await Promise.all([queryClient.invalidateQueries({ queryKey: CLEANING_SCHEDULES_KEY }), queryClient.invalidateQueries({ queryKey: CLEANING_TODAY_KEY })]);
    onClose();
  };
  const save = useMutation({
    mutationFn: () => putCleaningSchedule(token, space.id, { weekdays: [...weekdays].sort(), times: parsed ?? [], comment: comment.trim() || null }),
    onSuccess: refresh,
  });
  const remove = useMutation({ mutationFn: () => deleteCleaningSchedule(token, space.id), onSuccess: refresh });

  return (
    <Dialog
      title={t("scheduleFor", { name: space.name })}
      size="md"
      testId="schedule-form"
      onClose={onClose}
      onSubmit={() => {
        if (ready) save.mutate();
      }}
      footerStart={
        schedule ? (
          <DialogButton tone="danger" disabled={remove.isPending} onClick={() => remove.mutate()}>
            {t("scheduleRemove")}
          </DialogButton>
        ) : null
      }
      footer={
        <>
          <DialogButton onClick={onClose}>{t("cancel")}</DialogButton>
          <DialogButton type="submit" tone="primary" testId="schedule-save" disabled={!ready || save.isPending}>
            {t("save")}
          </DialogButton>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <fieldset>
          <legend className={captionClass} style={captionStyle}>{t("scheduleDays")}</legend>
          <div className="mt-2 flex flex-wrap gap-2">
            {WEEKDAYS.map((day) => {
              const on = weekdays.includes(day);
              return (
                <button
                  key={day}
                  type="button"
                  aria-pressed={on}
                  data-testid={`weekday-${day}`}
                  className="min-h-11 min-w-11 rounded-full px-3 text-sm font-semibold"
                  style={on ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { background: "var(--panel-muted)", color: "var(--text)", border: "1px solid var(--border)" }}
                  onClick={() => setWeekdays((current) => (on ? current.filter((item) => item !== day) : [...current, day]))}
                >
                  {weekdayName(day, locale)}
                </button>
              );
            })}
          </div>
        </fieldset>
        <label className="block">
          <span className={captionClass} style={captionStyle}>{t("scheduleTimes")}</span>
          <input className={inputClass} style={inputStyle} value={times} inputMode="numeric" placeholder={t("scheduleTimesPlaceholder")} data-testid="schedule-times" onChange={(event) => setTimes(event.target.value)} />
          <span className="mt-1 block text-xs" style={{ color: parsed === null ? "var(--danger)" : "var(--dim)" }}>
            {parsed === null ? t("scheduleTimesInvalid") : t("scheduleTimesHint")}
          </span>
        </label>
        <label className="block">
          <span className={captionClass} style={captionStyle}>{t("scheduleComment")}</span>
          <textarea className={inputClass} style={inputStyle} rows={2} maxLength={500} value={comment} data-testid="schedule-comment" onChange={(event) => setComment(event.target.value)} />
        </label>
        {save.isError ? <StatusText tone="error">{localizeError(save.error, ui)}</StatusText> : null}
        {remove.isError ? <StatusText tone="error">{localizeError(remove.error, ui)}</StatusText> : null}
      </div>
    </Dialog>
  );
}
