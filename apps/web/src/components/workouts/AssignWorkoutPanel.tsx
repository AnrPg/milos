"use client";





import { AssigneeRoleBadge } from "@/components/workouts/AssigneeRoleBadge";
import {useUiTranslations} from "@/i18n/ui";
import { localizeAdminAssignmentError, localizeError } from "@/i18n/presentation";
import { useEffect, useState } from "react";

import { ApiError } from "@/api/client";
import { assignWorkout, listAthletes, type AthleteOption } from "@/api/assigned-workouts";
import { fetchSchedule, listAdminClassTypes, updateScheduleSlot, type ClassTypeRecord, type ScheduleSlot } from "@/api/schedule";
import { setDayWorkout } from "@/api/day-workouts";
import {
  ALL_CLASSES,
  DayWorkoutPreviewNote,
  DayWorkoutScopeFields,
  scopeIsComplete,
  scopeRequest,
  type DayWorkoutScopeValue,
} from "@/components/schedule/DayWorkoutFields";
import { useOrganizationTimeZone } from "@/lib/organization-slug";
import { dateKeyInZone } from "@/lib/zoned-time";
import { useTranslations } from "next-intl";
import { fetchAdminWorkout, type WorkoutRecord } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { formatLocalDate } from "@/lib/local-date";
import { SemanticLabel } from "@/components/semantic-label";
import { WorkoutPreviewDetail } from "@/components/workouts/WorkoutPreviewDetail";
import { Dialog } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { DateInput } from "@/components/ui/DateInput";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

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
  const scheduleT = useTranslations("Schedule");
  // ADR-230: «Ημέρα» sets the WOD of a whole day (all classes or some types).
  const [mode, setMode] = useState<"athletes" | "class" | "day">("athletes");
  const gymZone = useOrganizationTimeZone();
  const [dayDate, setDayDate] = useState(() => dateKeyInZone(new Date(), gymZone));
  const [dayScope, setDayScope] = useState<DayWorkoutScopeValue>(ALL_CLASSES);
  const [dayReplaceOwn, setDayReplaceOwn] = useState(false);
  const [classTypes, setClassTypes] = useState<ClassTypeRecord[]>([]);
  const [query, setQuery] = useState("");
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [slots, setSlots] = useState<ScheduleSlot[]>([]);
  const [selectedSlotId, setSelectedSlotId] = useState("");
  const [scheduledFor, setScheduledFor] = useState(() => formatLocalDate(new Date()));
  const [instructions, setInstructions] = useState("");
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
      void listAthletes(tokens.access_token!, query, { includeMembers: true })
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

  useEffect(() => {
    if (!tokens?.access_token || mode !== "class") return;
    let cancelled = false;
    const start = new Date();
    const end = new Date();
    end.setDate(end.getDate() + 30);
    void fetchSchedule(tokens.access_token, {
      startAt: start.toISOString(),
      endAt: end.toISOString(),
      days: 30,
      classTypeIds: [],
    })
      .then((window) => {
        if (cancelled) return;
        setSlots(window.slots ?? []);
      })
      .catch(() => {
        if (!cancelled) setSlots([]);
      });
    return () => {
      cancelled = true;
    };
  }, [mode, tokens?.access_token]);

  useEffect(() => {
    if (!tokens?.access_token || mode !== "day") return;
    let cancelled = false;
    void listAdminClassTypes(tokens.access_token)
      .then((types) => {
        if (!cancelled) setClassTypes(types);
      })
      .catch(() => {
        if (!cancelled) setClassTypes([]);
      });
    return () => {
      cancelled = true;
    };
  }, [mode, tokens?.access_token]);

  const dayRequest =
    dayDate && scopeIsComplete(dayScope) ? { date: dayDate, master_workout_id: workoutId, ...scopeRequest(dayScope) } : null;

  async function submitDayAssignment() {
    if (!tokens?.access_token || !dayRequest) return;
    setSaving(true);
    setError(null);
    try {
      await setDayWorkout(tokens.access_token, { ...dayRequest, replace_own: dayReplaceOwn });
      onAssigned();
      onClose();
    } catch (requestError) {
      setError(localizeError(requestError, i18n));
    } finally {
      setSaving(false);
    }
  }

  async function submitAssignment() {
    if (!tokens?.access_token) return;

    setSaving(true);
    setError(null);

    try {
      await assignWorkout(tokens.access_token, {
        master_workout_id: workoutId,
        athlete_ids: selectedIds,
        scheduled_for: scheduledFor,
        instructions: instructions.trim() || undefined,
      });

      onAssigned();
      onClose();
    } catch (requestError) {
      setError(requestError instanceof Error ? localizeAdminAssignmentError(requestError, i18n) : i18n("couldNotAssignWorkout58ad222"));
    } finally {
      setSaving(false);
    }
  }

  async function submitClassAssignment() {
    if (!tokens?.access_token || !selectedSlotId) return;
    const slot = slots.find((item) => item.id === selectedSlotId);
    if (!slot) return;

    setSaving(true);
    setError(null);
    try {
      await updateScheduleSlot(tokens.access_token, selectedSlotId, {
        master_workout_id: workoutId,
        class_type_id: slot.class_type_id,
        name: slot.name,
        duration_minutes: slot.duration_minutes,
        scheduled_at: slot.scheduled_at,
        capacity: slot.capacity,
        auto_approve: slot.auto_approve,
        booking_timeout_minutes: slot.booking_timeout_minutes,
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
      {/* Panel */}
      <Dialog
        onClose={onClose}
        bare
        variant="drawer"
        layer="drawer"
        size="full"
        ariaLabel={i18n("assignWorkout3e28a99")}
        panelClassName="md:max-w-[480px]"
        panelStyle={{ background: "var(--bg)" }}
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
            <ErrorNotice>
              {error}
            </ErrorNotice>
          ) : null}

          {/* Workout summary */}
          {workout && !loading ? (
            <section
              className="rounded-[1.4rem] p-4"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--primary)]">
                <SemanticLabel value={workout.type} />
              </p>
              <div className="mt-3">
                <WorkoutPreviewDetail
                  sections={workout.sections}
                  content={workout.content}
                  initiallyExpanded
                  hideScaleChips
                  authoringMode={workout.authoring_mode}
                  freeTextBody={workout.free_text_body}
                  freeTextDocument={workout.free_text_document}
                />
              </div>
            </section>
          ) : null}

          <div className="flex rounded-full p-1" style={{ background: "var(--border)" }}>
            {([
              ["athletes", i18n("athletesda22204")],
              ["class", i18n("featureScheduledClass")],
              ["day", scheduleT("dayWodAssignMode")],
            ] as const).map(([nextMode, label]) => (
              <button
                key={nextMode}
                type="button"
                className="flex-1 rounded-full px-3 py-2 text-xs font-bold"
                style={mode === nextMode ? { background: "var(--text)", color: "var(--bg)" } : { color: "var(--dim)" }}
                onClick={() => setMode(nextMode)}
              >
                {label}
              </button>
            ))}
          </div>

          {mode === "athletes" ? (
            <>
              <label className="block">
                <span className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
                  {i18n("dateeb9a4bc")}
                </span>
                <DateInput
                  className="mt-2 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  onValueChange={(value) => setScheduledFor(value)}
                  value={scheduledFor}
                />
              </label>

              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
                  {i18n("athletesda22204")}
                  {selectedIds.length > 0 ? (
                    <span className="ms-2 rounded-full px-1.5 py-0.5 text-[10px]" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
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
                        style={selected ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
                        onClick={() =>
                          setSelectedIds((current) =>
                            current.includes(athlete.id) ? current.filter((id) => id !== athlete.id) : [...current, athlete.id],
                          )
                        }
                        type="button"
                      >
                        <span className="font-semibold">{athlete.nickname}<AssigneeRoleBadge role={athlete.role} /></span>
                        <span className="text-xs uppercase tracking-[0.18em]">
                          {selected ? i18n("selected9a976fc") : i18n("add61cc55a")}
                        </span>
                      </button>
                    );
                  })}
                  {!athletesLoading && athletes.length === 0 ? (
                    <p className="rounded-[1rem] px-4 py-4 text-sm" style={{ border: "1px dashed var(--border)", color: "var(--dim)" }}>
                      {i18n("noAthletesMatchedThatSearchd4f2c56")}
                    </p>
                  ) : null}
                </div>
              </div>
            </>
          ) : mode === "day" ? (
            <div className="space-y-4" data-testid="assign-day">
              <label className="block">
                <span className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
                  {i18n("dateeb9a4bc")}
                </span>
                <DateInput
                  className="mt-2 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  onValueChange={(value) => setDayDate(value)}
                  value={dayDate}
                />
              </label>
              <DayWorkoutScopeFields value={dayScope} onChange={setDayScope} classTypes={classTypes} disabled={saving} />
              <DayWorkoutPreviewNote
                token={tokens?.access_token ?? ""}
                request={dayRequest}
                replaceOwn={dayReplaceOwn}
                onReplaceOwnChange={setDayReplaceOwn}
                timeZone={gymZone}
              />
            </div>
          ) : (
            <label className="block">
              <span className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
                {i18n("featureScheduledClass")}
              </span>
              <Select
                className="mt-2 w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={selectedSlotId}
                onValueChange={(value) => setSelectedSlotId(value)}
              >
                <option value="">{i18n("featureChooseClass")}</option>
                {slots.map((slot) => (
                  <option key={slot.id} value={slot.id}>
                    {new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(new Date(slot.scheduled_at))} · {slot.name}
                  </option>
                ))}
              </Select>
            </label>
          )}

          {/* Admin notes */}
          {mode === "day" ? null : (
          <label className="block">
            <span className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
              {i18n("instructionsdff73a2")}
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
              onChange={(e) => setInstructions(e.target.value)}
              placeholder={i18n("optionalProgrammingContextOrCuesa25eaae")}
              value={instructions}
            />
          </label>
          )}
        </div>

        {/* Bottom CTA */}
        <div
          className="border-t px-5 py-4"
          style={{ borderColor: "var(--border)", background: "var(--bg)" }}
        >
          <button
            className="w-full rounded-full py-3 text-sm font-bold tracking-wide disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            disabled={
              saving ||
              loading ||
              isUnassignable ||
              (mode === "class" ? !selectedSlotId : mode === "day" ? !dayRequest : selectedIds.length === 0)
            }
            onClick={() =>
              void (mode === "class" ? submitClassAssignment() : mode === "day" ? submitDayAssignment() : submitAssignment())
            }
            type="button"
          >
            {saving
                ? i18n("assigning4d16a1a")
                : mode === "class"
                ? i18n("featureAssignToClass")
                : mode === "day"
                ? scheduleT("dayWodSave")
                : selectedIds.length === 0
                  ? i18n("selectAthletesToAssign1666500")
                  : i18n("assignToAthletes", {count: selectedIds.length})}
          </button>
        </div>
      </Dialog>
    </>
  );
}
