"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  approveBooking,
  createBooking,
  createScheduleSlot,
  deleteScheduleSlot,
  fetchSchedule,
  rejectBooking,
  updateScheduleSlot,
  type ScheduleBooking,
  type ClassTypeRecord,
  type ScheduleSlot,
  type ScheduleSlotPayload,
} from "@/api/schedule";
import { listAdminWorkouts, type WorkoutRecord } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";
import { ViewModeSelector } from "@/components/calendar/ViewModeSelector";
import { BookingModal } from "@/components/schedule/BookingModal";
import { CalendarView } from "@/components/schedule/CalendarView";
import { buildScheduleWindow } from "@/components/schedule/calendar-window";
import { SlotPopup } from "@/components/schedule/SlotPopup";
import { TypeFilterChips } from "@/components/schedule/TypeFilterChips";
import { subscribeToTopic } from "@/lib/realtime";
import { useScheduleStore } from "@/stores/schedule";

type SlotEditorState = {
  slotId: string | null;
  values: ScheduleSlotPayload;
};

function formatDateTimeLocal(isoString: string) {
  const date = new Date(isoString);
  const tzOffset = date.getTimezoneOffset();
  const local = new Date(date.getTime() - tzOffset * 60_000);
  return local.toISOString().slice(0, 16);
}

function toIsoDateTime(localValue: string) {
  return new Date(localValue).toISOString();
}

function defaultSlotValues(
  isoDate: string,
  workouts: WorkoutRecord[],
  classTypes: ClassTypeRecord[],
): ScheduleSlotPayload {
  const date = new Date(`${isoDate}T09:00:00`);

  return {
    master_workout_id: workouts[0]?.id ?? "",
    class_type_id: classTypes.find((type) => !type.archived_at)?.id ?? "",
    scheduled_at: date.toISOString(),
    capacity: 12,
    auto_approve: false,
    booking_timeout_minutes: 60,
  };
}

export function ScheduleConsole({
  initialOpenSlotId = null,
  pageTitle,
  heroTimeoutMs,
}: {
  initialOpenSlotId?: string | null;
  pageTitle?: string;
  heroTimeoutMs?: number;
} = {}) {
  const t = useTranslations("Schedule");
  const common = useTranslations("Common");
  const locale = useLocale();
  const { tokens, currentUser } = useSession();
  const { days, setDays, shiftWindow, resetWindow, startDate, classTypeIds, setClassTypeIds } = useScheduleStore();
  const [schedule, setSchedule] = useState<ScheduleSlot[]>([]);
  const [classTypes, setClassTypes] = useState<ClassTypeRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedSlot, setSelectedSlot] = useState<ScheduleSlot | null>(null);
  const [bookingTarget, setBookingTarget] = useState<ScheduleSlot | null>(null);
  const [resolveTarget, setResolveTarget] = useState<{ booking: ScheduleBooking; action: "approve" | "reject" } | null>(
    null,
  );
  const [resolveMessage, setResolveMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [workouts, setWorkouts] = useState<WorkoutRecord[]>([]);
  const [editor, setEditor] = useState<SlotEditorState | null>(null);
  const appliedMobileDefault = useRef(false);
  const initialOpenHandledRef = useRef(false);

  const isAdmin = currentUser?.role === "admin";
  const calendarWindow = useMemo(() => buildScheduleWindow(startDate, days), [days, startDate]);
  const title = pageTitle ?? t("title");

  const loadSchedule = useCallback(async () => {
    if (!tokens?.access_token) return null;

    setLoading(true);
    setError(null);

    try {
      const window = await fetchSchedule(tokens.access_token, {
        startAt: calendarWindow.queryStartAt,
        endAt: calendarWindow.queryEndAt,
        days,
        classTypeIds,
      });

      setSchedule(window.slots);
      setClassTypes(window.class_types);
      return window.slots;
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : t("failedToLoadSchedule"));
      return null;
    } finally {
      setLoading(false);
    }
  }, [calendarWindow.queryEndAt, calendarWindow.queryStartAt, classTypeIds, days, t, tokens]);

  useEffect(() => {
    const frame = window.requestAnimationFrame(() => {
      void loadSchedule();
    });

    return () => window.cancelAnimationFrame(frame);
  }, [loadSchedule]);

  useEffect(() => {
    if (!tokens?.access_token) return;

    return subscribeToTopic(tokens.access_token, "schedule:lobby", {
      "schedule:refresh": () => {
        void loadSchedule();
      },
    });
  }, [loadSchedule, tokens?.access_token]);

  useEffect(() => {
    const accessToken = tokens?.access_token;

    if (!isAdmin || typeof accessToken !== "string") return;

    const token = accessToken;

    let cancelled = false;

    void listAdminWorkouts(token)
      .then((nextWorkouts) => {
        if (!cancelled) setWorkouts(nextWorkouts.filter((workout) => workout.status === "published"));
      })
      .catch(() => {
        if (!cancelled) setWorkouts([]);
      });

    return () => {
      cancelled = true;
    };
  }, [isAdmin, tokens?.access_token]);

  useEffect(() => {
    if (typeof window === "undefined") return;
    if (appliedMobileDefault.current) return;
    if (!window.matchMedia("(max-width: 767px)").matches || days !== 7) return;

    appliedMobileDefault.current = true;
    const frame = window.requestAnimationFrame(() => setDays(3));

    return () => window.cancelAnimationFrame(frame);
  }, [days, setDays]);

  useEffect(() => {
    if (!initialOpenSlotId || initialOpenHandledRef.current || schedule.length === 0) return;
    const slot = schedule.find((s) => s.id === initialOpenSlotId);
    if (slot) {
      initialOpenHandledRef.current = true;
      const frame = window.requestAnimationFrame(() => setSelectedSlot(slot));

      return () => window.cancelAnimationFrame(frame);
    }
  }, [initialOpenSlotId, schedule]);

  const editorDateValue = useMemo(() => {
    if (!editor) return "";
    return formatDateTimeLocal(editor.values.scheduled_at);
  }, [editor]);

  async function handleBook() {
    if (!tokens?.access_token || !bookingTarget) return;

    setBusy(true);

    try {
      await createBooking(tokens.access_token, bookingTarget.id);
      setBookingTarget(null);
      setSelectedSlot(null);
      await loadSchedule();
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : t("failedToCreateBooking"));
    } finally {
      setBusy(false);
    }
  }

  async function handleResolve() {
    if (!tokens?.access_token || !resolveTarget) return;

    setBusy(true);

    try {
      if (resolveTarget.action === "approve") {
        await approveBooking(tokens.access_token, resolveTarget.booking.id, resolveMessage.trim() || undefined);
      } else {
        await rejectBooking(tokens.access_token, resolveTarget.booking.id, resolveMessage.trim() || undefined);
      }

      const refreshedSlots = await loadSchedule();
      setResolveTarget(null);
      setResolveMessage("");

      if (selectedSlot && refreshedSlots) {
        const refreshed = refreshedSlots.find((slot) => slot.id === selectedSlot.id);
        if (refreshed) setSelectedSlot(refreshed);
      }
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : t("failedToResolveBooking"));
    } finally {
      setBusy(false);
    }
  }

  async function saveSlot() {
    if (!tokens?.access_token || !editor) return;

    setBusy(true);

    try {
      if (editor.slotId) {
        await updateScheduleSlot(tokens.access_token, editor.slotId, editor.values);
      } else {
        await createScheduleSlot(tokens.access_token, editor.values);
      }

      setEditor(null);
      await loadSchedule();
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : t("failedToSaveSlot"));
    } finally {
      setBusy(false);
    }
  }

  async function removeEditedSlot() {
    if (!tokens?.access_token || !editor?.slotId) return;

    setBusy(true);

    try {
      await deleteScheduleSlot(tokens.access_token, editor.slotId);
      const deletedSlotId = editor.slotId;
      setEditor(null);

      if (selectedSlot?.id === deletedSlotId) {
        setSelectedSlot(null);
      }

      await loadSchedule();
    } catch (requestError) {
      const message =
        requestError instanceof ApiError ? requestError.message : t("failedToDeleteSlot");
      setError(message);
    } finally {
      setBusy(false);
    }
  }

  function openCreateEditor(isoDate: string) {
    if (!workouts.length || !classTypes.some((type) => !type.archived_at)) {
      setError(t("createPrerequisites"));
      return;
    }

    setEditor({
      slotId: null,
      values: defaultSlotValues(isoDate, workouts, classTypes),
    });
  }

  function openUpdateEditor(slot: ScheduleSlot) {
    setEditor({
      slotId: slot.id,
      values: {
        master_workout_id: slot.master_workout_id,
        class_type_id: slot.class_type_id,
        scheduled_at: slot.scheduled_at,
        capacity: slot.capacity,
        auto_approve: slot.auto_approve,
        booking_timeout_minutes: slot.booking_timeout_minutes,
      },
    });
  }

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-7xl space-y-8">
        <TransientHero label={t("introduction")} showIntroLabel={t("showIntro")} timeoutMs={heroTimeoutMs}>
          <section className="rounded-[2rem] px-6 py-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-[var(--primary)]">{t("classSchedule")}</p>
            <h1 className="mt-1 text-2xl font-bold tracking-tight" style={{ color: "var(--text)" }}>{title}</h1>
          </section>
        </TransientHero>


        <section className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex flex-col gap-5 xl:flex-row xl:items-center xl:justify-between">
            <TypeFilterChips classTypes={classTypes} value={classTypeIds} onChange={setClassTypeIds} />

            <div className="flex flex-wrap gap-3">
              <ViewModeSelector
                ariaLabel={t("calendarView")}
                onChange={setDays}
                options={[
                  { value: 3, label: "3d", accessibleLabel: t("threeDayView") },
                  { value: 7, label: "7d", accessibleLabel: t("weekView") },
                  { value: 30, label: "Mo", accessibleLabel: t("monthView") },
                ]}
                value={days}
              />

              <div className="flex gap-2">
                {(
                  [
                    [t("previous"), () => shiftWindow(-1)],
                    [t("today"), resetWindow],
                    [t("next"), () => shiftWindow(1)],
                  ] as const
                ).map(([label, handler]) => (
                  <button
                    key={label}
                    className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                    style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
                    onClick={handler}
                    type="button"
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </section>

        {error ? (
          <div className="rounded-[1.6rem] px-5 py-4 text-sm" style={{ background: "var(--primary)]/10", border: "1px solid var(--primary)30", color: "var(--primary-strong)" }}>
            {error}
          </div>
        ) : null}

        {loading ? (
          <section className="rounded-[2rem] p-10 text-center text-sm font-semibold uppercase tracking-[0.24em]" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--dim)" }}>
            {t("loading")}
          </section>
        ) : (
          <CalendarView
            days={days}
            isAdmin={isAdmin}
            onCreateSlot={openCreateEditor}
            onSelectSlot={setSelectedSlot}
            slots={schedule}
            startDate={startDate}
          />
        )}
      </div>

      {selectedSlot ? (
        <SlotPopup
          key={selectedSlot.id}
          accessToken={tokens?.access_token ?? ""}
          isAdmin={isAdmin}
          onApproveBooking={(booking) => {
            setResolveMessage("");
            setResolveTarget({ booking, action: "approve" });
          }}
          onBook={() => setBookingTarget(selectedSlot)}
          onCancelBooking={() => void loadSchedule()}
          onClose={() => setSelectedSlot(null)}
          onEdit={() => openUpdateEditor(selectedSlot)}
          onRejectBooking={(booking) => {
            setResolveMessage("");
            setResolveTarget({ booking, action: "reject" });
          }}
          slot={selectedSlot}
        />
      ) : null}

      {bookingTarget ? (
        <BookingModal
          busy={busy}
          confirmLabel={t("confirmBooking")}
          description={t("bookClassDescription", {
            workoutTitle: bookingTarget.workout?.title ?? t("thisSlot"),
            scheduledAt: new Intl.DateTimeFormat(locale, {
              weekday: "long",
              month: "short",
              day: "numeric",
              hour: "numeric",
              minute: "2-digit",
            }).format(new Date(bookingTarget.scheduled_at)),
          })}
          onCancel={() => setBookingTarget(null)}
          onConfirm={() => void handleBook()}
          title={t("bookClassSlot")}
        />
      ) : null}

      {resolveTarget ? (
        <BookingModal
          busy={busy}
          confirmLabel={resolveTarget.action === "approve" ? t("approveBooking") : t("rejectBooking")}
          description={t("resolveBookingDescription", {
            memberName: resolveTarget.booking.user_nickname ?? t("thisMember"),
            action: resolveTarget.action === "approve" ? t("approve") : t("reject"),
          })}
          inputLabel={t("adminMessage")}
          inputPlaceholder={t("optionalNoteForMember")}
          inputValue={resolveMessage}
          onCancel={() => {
            setResolveTarget(null);
            setResolveMessage("");
          }}
          onConfirm={() => void handleResolve()}
          onInputChange={setResolveMessage}
          title={resolveTarget.action === "approve" ? t("approveBooking") : t("rejectBooking")}
        />
      ) : null}

      {editor ? (
        <div className="fixed inset-0 z-40 flex items-center justify-center px-4" style={{ background: "rgba(0,0,0,0.7)" }}>
          <div className="w-full max-w-2xl rounded-[2rem] p-6 shadow-[0_30px_90px_rgba(0,0,0,0.7)]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-sm font-semibold uppercase tracking-[0.24em] text-[var(--primary)]">{t("adminSlotEditor")}</p>
                <h3 className="mt-3 text-2xl font-semibold" style={{ color: "var(--text)" }}>
                  {editor.slotId ? t("editScheduledClass") : t("createScheduledClass")}
                </h3>
              </div>
              <button
                className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
                onClick={() => setEditor(null)}
                type="button"
              >
                {common("close")}
              </button>
            </div>

            <div className="mt-6 grid gap-4 md:grid-cols-2">
              {[
                { label: t("workout"), type: "select" as const },
                { label: t("classType"), type: "select-type" as const },
                { label: t("scheduledAt"), type: "datetime" as const },
                { label: t("capacity"), type: "number-cap" as const },
                { label: t("timeoutMinutes"), type: "number-timeout" as const },
              ].map(({ label, type }) => (
                <label key={label} className="space-y-2 text-sm font-semibold" style={{ color: "var(--muted)" }}>
                  <span>{label}</span>
                  {type === "select" ? (
                    <select
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                      onChange={(event) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, master_workout_id: event.target.value } } : current,
                        )
                      }
                      value={editor.values.master_workout_id}
                    >
                      {workouts.map((workout) => (
                        <option key={workout.id} value={workout.id}>{workout.title}</option>
                      ))}
                    </select>
                  ) : type === "select-type" ? (
                    <select
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                      onChange={(event) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, class_type_id: event.target.value } } : current,
                        )
                      }
                      value={editor.values.class_type_id}
                    >
                      {classTypes.filter((classType) => !classType.archived_at).map((option) => (
                        <option key={option.id} value={option.id}>{option.name}</option>
                      ))}
                    </select>
                  ) : type === "datetime" ? (
                    <input
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                      onChange={(event) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, scheduled_at: toIsoDateTime(event.target.value) } } : current,
                        )
                      }
                      type="datetime-local"
                      value={editorDateValue}
                    />
                  ) : type === "number-cap" ? (
                    <input
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                      min={1}
                      onChange={(event) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, capacity: Number(event.target.value) || 1 } } : current,
                        )
                      }
                      type="number"
                      value={editor.values.capacity}
                    />
                  ) : (
                    <input
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                      min={1}
                      onChange={(event) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, booking_timeout_minutes: Number(event.target.value) || 1 } } : current,
                        )
                      }
                      type="number"
                      value={editor.values.booking_timeout_minutes}
                    />
                  )}
                </label>
              ))}
            </div>

            <label className="mt-4 flex items-center gap-3 text-sm font-semibold" style={{ color: "var(--muted)" }}>
              <input
                checked={editor.values.auto_approve}
                onChange={(event) =>
                  setEditor((current) =>
                    current ? { ...current, values: { ...current.values, auto_approve: event.target.checked } } : current,
                  )
                }
                type="checkbox"
              />
              {t("autoApproveBookingsForThisSlot")}
            </label>

            <div className="mt-6 flex flex-wrap justify-between gap-3">
              {editor.slotId ? (
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 25%, transparent)", color: "var(--primary)" }}
                  onClick={() => void removeEditedSlot()}
                  type="button"
                >
                  {t("deleteSlot")}
                </button>
              ) : <span />}

              <div className="flex gap-3">
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                  style={{ background: "var(--border)", color: "var(--text-soft)" }}
                  onClick={() => setEditor(null)}
                  type="button"
                >
                  {common("cancel")}
                </button>
                <button
                  className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
                  style={{ background: "var(--text)", color: "var(--bg)" }}
                  disabled={busy || !editor.values.master_workout_id || !editor.values.class_type_id}
                  onClick={() => void saveSlot()}
                  type="button"
                >
                  {busy ? common("saving") : editor.slotId ? t("saveChanges") : t("createSlot")}
                </button>
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </main>
  );
}
