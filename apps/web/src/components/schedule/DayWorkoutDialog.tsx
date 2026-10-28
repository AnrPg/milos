"use client";

import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { removeDayWorkout, setDayWorkout, type DayWorkout } from "@/api/day-workouts";
import type { ClassTypeRecord, ScheduleLocation, ScheduleSlot } from "@/api/schedule";
import {
  ALL_CLASSES,
  DayWorkoutPreviewNote,
  DayWorkoutScopeFields,
  scopeIsComplete,
  scopeRequest,
  type DayWorkoutScopeValue,
} from "@/components/schedule/DayWorkoutFields";
import { dayLabel, dayWorkoutScope, dayWorkoutsOn, inheritedFrom } from "@/components/schedule/day-workouts";
import { WodPicker } from "@/components/schedule/WodPicker";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { ContextualWorkoutCreator } from "@/components/workouts/creation/ContextualWorkoutCreator";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

type Editing = { rule: DayWorkout | null; workoutId: string | null; scope: DayWorkoutScopeValue; replaceOwn: boolean };

/**
 * ADR-224: the WOD of one day, opened from the day's strip in the schedule.
 * Lists the day's WODs (each for every class or for some class types) and
 * edits one: the WOD (suggestions, search, «+ Νέο WOD» that comes back
 * filled in), which classes it is for, and a preview of what it changes.
 */
export function DayWorkoutDialog({
  token,
  date,
  timeZone,
  dayWorkouts,
  slots,
  classTypes,
  locations = [],
  onClose,
  onChanged,
}: {
  token: string;
  /** The gym's date, YYYY-MM-DD. */
  date: string;
  timeZone: string | null;
  dayWorkouts: DayWorkout[];
  /** The schedule's classes (to count what each day WOD reaches). */
  slots: ScheduleSlot[];
  classTypes: ClassTypeRecord[];
  locations?: ScheduleLocation[];
  onClose: () => void;
  onChanged: () => void;
}) {
  const t = useTranslations("Schedule");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const queryClient = useQueryClient();
  const rules = dayWorkoutsOn(dayWorkouts, date, classTypes);
  const [editing, setEditing] = useState<Editing | null>(() =>
    rules.length ? null : { rule: null, workoutId: null, scope: ALL_CLASSES, replaceOwn: false },
  );
  const [confirmRemove, setConfirmRemove] = useState<string | null>(null);
  const [creatingWod, setCreatingWod] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const dateLabel = dayLabel(date, locale);
  const scopeName = (rule: Pick<DayWorkout, "class_type_id" | "location_id">) =>
    dayWorkoutScope(rule, {
      allClasses: t("dayWodScopeAll"),
      classType: (id) => classTypes.find((type) => type.id === id)?.name,
      location: (id) => locations.find((location) => location.id === id)?.name,
    });

  const request =
    editing?.workoutId && scopeIsComplete(editing.scope)
      ? { date, master_workout_id: editing.workoutId, ...scopeRequest(editing.scope) }
      : null;

  function edit(rule: DayWorkout) {
    setError(null);
    setEditing({
      rule,
      workoutId: rule.master_workout_id,
      scope: {
        mode: rule.class_type_id ? "types" : "all",
        classTypeIds: rule.class_type_id ? [rule.class_type_id] : [],
        locationId: rule.location_id,
      },
      replaceOwn: false,
    });
  }

  async function done() {
    await queryClient.invalidateQueries({ queryKey: ["day-workout-preview"] });
    onChanged();
  }

  async function save() {
    if (!request || !editing) return;
    setBusy(true);
    setError(null);
    try {
      await setDayWorkout(token, { ...request, replace_own: editing.replaceOwn });
      await done();
      onClose();
    } catch (saveError) {
      setError(localizeError(saveError, i18n));
    } finally {
      setBusy(false);
    }
  }

  async function remove(rule: DayWorkout) {
    setBusy(true);
    setError(null);
    try {
      await removeDayWorkout(token, rule.id);
      setConfirmRemove(null);
      await done();
      if (rules.length <= 1) onClose();
    } catch (removeError) {
      setError(localizeError(removeError, i18n));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Dialog
        onClose={onClose}
        dismissible={!busy}
        eyebrow={dateLabel}
        title={t("dayWodTitle")}
        description={t("dayWodIntro")}
        size="lg"
        variant="center"
        testId="day-wod-dialog"
        footer={
          editing ? (
            <>
              <DialogButton tone="ghost" onClick={() => (rules.length ? setEditing(null) : onClose())} disabled={busy}>
                {rules.length ? t("dayWodBackToList") : i18n("cancel77dfd21")}
              </DialogButton>
              <DialogButton tone="primary" onClick={() => void save()} disabled={busy || !request} testId="day-wod-save">
                {t("dayWodSave")}
              </DialogButton>
            </>
          ) : (
            <>
              <DialogButton tone="ghost" onClick={onClose} disabled={busy}>
                {i18n("closefeb3e25")}
              </DialogButton>
              <DialogButton
                tone="secondary"
                onClick={() => setEditing({ rule: null, workoutId: null, scope: { ...ALL_CLASSES, mode: "types" }, replaceOwn: false })}
                disabled={busy}
              >
                {t("dayWodAddScope")}
              </DialogButton>
            </>
          )
        }
      >
        <div className="space-y-4">
          {editing ? (
            <>
              <WodPicker
                label={editing.rule ? `${t("dayWodWorkoutLabel")} · ${scopeName(editing.rule)}` : t("dayWodWorkoutLabel")}
                token={token}
                value={editing.workoutId}
                onChange={(workoutId) => setEditing((current) => (current ? { ...current, workoutId } : current))}
                onCreateNew={() => setCreatingWod(true)}
                date={date}
                classTypeId={editing.scope.mode === "types" ? editing.scope.classTypeIds[0] ?? null : null}
              />
              {editing.rule ? null : (
                <DayWorkoutScopeFields
                  value={editing.scope}
                  onChange={(scope) => setEditing((current) => (current ? { ...current, scope } : current))}
                  classTypes={classTypes}
                  locations={locations}
                  disabled={busy}
                />
              )}
              <DayWorkoutPreviewNote
                token={token}
                request={request}
                replaceOwn={editing.replaceOwn}
                onReplaceOwnChange={(replaceOwn) => setEditing((current) => (current ? { ...current, replaceOwn } : current))}
                timeZone={timeZone}
              />
            </>
          ) : (
            <ul className="space-y-2" data-testid="day-wod-list">
              {rules.map((rule) => {
                const count = inheritedFrom(rule, slots).length;
                return (
                  <li
                    key={rule.id}
                    className="rounded-2xl px-4 py-3"
                    style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
                          {scopeName(rule)}
                        </p>
                        <p className="mt-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                          {rule.workout?.title ?? "WOD"}
                        </p>
                        <p className="mt-0.5 text-xs" style={{ color: "var(--muted)" }}>
                          {t("dayWodInheritedCount", { count })}
                        </p>
                      </div>
                      <div className="flex shrink-0 gap-2">
                        <button
                          type="button"
                          className="rounded-full px-3 py-1.5 text-xs font-semibold"
                          style={{ background: "var(--card)", color: "var(--text-soft)" }}
                          onClick={() => edit(rule)}
                          disabled={busy}
                        >
                          {t("dayWodChange")}
                        </button>
                        <button
                          type="button"
                          className="rounded-full px-3 py-1.5 text-xs font-semibold"
                          style={{ background: "color-mix(in srgb, var(--danger) 10%, transparent)", color: "var(--danger)" }}
                          onClick={() => setConfirmRemove(rule.id)}
                          disabled={busy}
                        >
                          {t("dayWodRemove")}
                        </button>
                      </div>
                    </div>
                    {confirmRemove === rule.id ? (
                      <div className="mt-3 flex flex-wrap items-center gap-2 text-xs" style={{ color: "var(--text-soft)" }}>
                        <span className="flex-1">{t("dayWodRemoveConfirm", { count })}</span>
                        <button
                          type="button"
                          className="rounded-full px-3 py-1.5 font-semibold"
                          style={{ background: "var(--danger)", color: "var(--primary-contrast)" }}
                          onClick={() => void remove(rule)}
                          disabled={busy}
                        >
                          {t("dayWodRemoveYes")}
                        </button>
                        <button
                          type="button"
                          className="rounded-full px-3 py-1.5 font-semibold"
                          style={{ background: "var(--card)", color: "var(--text-soft)" }}
                          onClick={() => setConfirmRemove(null)}
                          disabled={busy}
                        >
                          {i18n("cancel77dfd21")}
                        </button>
                      </div>
                    ) : null}
                  </li>
                );
              })}
            </ul>
          )}

          {error ? <ErrorNotice>{error}</ErrorNotice> : null}
        </div>
      </Dialog>

      {creatingWod ? (
        <ContextualWorkoutCreator
          target={t("dayWodNewTarget", { date: dateLabel })}
          onPublished={(workoutId) => setEditing((current) => (current ? { ...current, workoutId } : current))}
          onClose={() => setCreatingWod(false)}
        />
      ) : null}
    </>
  );
}
