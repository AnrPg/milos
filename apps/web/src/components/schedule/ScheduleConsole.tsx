"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";

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
  type ScheduleSlot,
  type ScheduleSlotPayload,
  type TrainingType,
} from "@/api/schedule";
import { listAdminWorkouts, type WorkoutRecord } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
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

const TRAINING_TYPE_OPTIONS: Array<{ value: TrainingType; label: string }> = [
  { value: "crossfit", label: "CrossFit" },
  { value: "strength", label: "Strength" },
  { value: "gymnastics", label: "Gymnastics" },
  { value: "aerobics", label: "Aerobics" },
  { value: "flexibility", label: "Flexibility" },
  { value: "recovery", label: "Recovery" },
];

function formatDateTimeLocal(isoString: string) {
  const date = new Date(isoString);
  const tzOffset = date.getTimezoneOffset();
  const local = new Date(date.getTime() - tzOffset * 60_000);
  return local.toISOString().slice(0, 16);
}

function toIsoDateTime(localValue: string) {
  return new Date(localValue).toISOString();
}

function defaultSlotValues(isoDate: string, workouts: WorkoutRecord[]): ScheduleSlotPayload {
  const date = new Date(`${isoDate}T09:00:00`);
  const defaultTrainingType = normalizeTrainingType(workouts[0]?.type);

  return {
    master_workout_id: workouts[0]?.id ?? "",
    training_type: defaultTrainingType ?? "crossfit",
    scheduled_at: date.toISOString(),
    capacity: 12,
    auto_approve: false,
    booking_timeout_minutes: 60,
  };
}

function normalizeTrainingType(value: string | undefined): TrainingType | null {
  if (value === "crossfit" || value === "strength" || value === "gymnastics" || value === "aerobics" || value === "flexibility" || value === "recovery") {
    return value;
  }

  return null;
}

export function ScheduleConsole({
  initialOpenSlotId = null,
}: {
  initialOpenSlotId?: string | null;
} = {}) {
  const { tokens, currentUser } = useSession();
  const { days, setDays, shiftWindow, resetWindow, startDate, trainingType, setTrainingType } = useScheduleStore();
  const [schedule, setSchedule] = useState<ScheduleSlot[]>([]);
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

  const loadSchedule = useCallback(async () => {
    if (!tokens?.access_token) return null;

    setLoading(true);
    setError(null);

    try {
      const window = await fetchSchedule(tokens.access_token, {
        startAt: calendarWindow.queryStartAt,
        endAt: calendarWindow.queryEndAt,
        days,
        trainingType,
      });

      setSchedule(window.slots);
      return window.slots;
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Failed to load schedule.");
      return null;
    } finally {
      setLoading(false);
    }
  }, [calendarWindow.queryEndAt, calendarWindow.queryStartAt, days, tokens, trainingType]);

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
      setSelectedSlot(slot);
      initialOpenHandledRef.current = true;
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
      setError(requestError instanceof Error ? requestError.message : "Could not create booking.");
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
      setError(requestError instanceof Error ? requestError.message : "Could not resolve booking.");
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
      setError(requestError instanceof Error ? requestError.message : "Could not save slot.");
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
        requestError instanceof ApiError ? requestError.message : "Could not delete slot with existing bookings.";
      setError(message);
    } finally {
      setBusy(false);
    }
  }

  function openCreateEditor(isoDate: string) {
    if (!workouts.length) {
      setError("Create at least one published workout before adding schedule slots.");
      return;
    }

    setEditor({
      slotId: null,
      values: defaultSlotValues(isoDate, workouts),
    });
  }

  function openUpdateEditor(slot: ScheduleSlot) {
    setEditor({
      slotId: slot.id,
      values: {
        master_workout_id: slot.master_workout_id,
        training_type: slot.training_type,
        scheduled_at: slot.scheduled_at,
        capacity: slot.capacity,
        auto_approve: slot.auto_approve,
        booking_timeout_minutes: slot.booking_timeout_minutes,
      },
    });
  }

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "#0A0A0F" }}>
      <div className="mx-auto max-w-7xl space-y-8">
        <section className="rounded-[2.4rem] px-8 py-6" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
          <p className="text-sm font-semibold uppercase tracking-[0.28em] text-[#d95d39]">Class Schedule</p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight" style={{ color: "#F0EDF8" }}>Schedule</h1>
        </section>

        <section className="rounded-[2rem] p-6" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
          <div className="flex flex-col gap-5 xl:flex-row xl:items-center xl:justify-between">
            <TypeFilterChips value={trainingType} onChange={setTrainingType} />

            <div className="flex flex-wrap gap-3">
              <div className="flex rounded-full p-1" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
                {[3, 7, 30].map((value) => (
                  <button
                    className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                    style={
                      days === value
                        ? { background: "#F0EDF8", color: "#0A0A0F" }
                        : { color: "#55556a" }
                    }
                    key={value}
                    onClick={() => setDays(value as 3 | 7 | 30)}
                    type="button"
                  >
                    {value === 3 ? "3-day" : value === 7 ? "Week" : "Month"}
                  </button>
                ))}
              </div>

              <div className="flex gap-2">
                {(
                  [
                    ["Prev", () => shiftWindow(-1)],
                    ["Today", resetWindow],
                    ["Next", () => shiftWindow(1)],
                  ] as const
                ).map(([label, handler]) => (
                  <button
                    key={label}
                    className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                    style={{ background: "#111118", border: "1px solid #1a1a28", color: "#c0c0d8" }}
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
          <div className="rounded-[1.6rem] px-5 py-4 text-sm" style={{ background: "#d95d39]/10", border: "1px solid #d95d3930", color: "#e07a5f" }}>
            {error}
          </div>
        ) : null}

        {loading ? (
          <section className="rounded-[2rem] p-10 text-center text-sm font-semibold uppercase tracking-[0.24em]" style={{ background: "#111118", border: "1px solid #1a1a28", color: "#55556a" }}>
            Loading schedule...
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
          confirmLabel="Confirm booking"
          description={`Reserve ${bookingTarget.workout?.title ?? "this slot"} on ${new Intl.DateTimeFormat("en-US", {
            weekday: "long",
            month: "short",
            day: "numeric",
            hour: "numeric",
            minute: "2-digit",
          }).format(new Date(bookingTarget.scheduled_at))}.`}
          onCancel={() => setBookingTarget(null)}
          onConfirm={() => void handleBook()}
          title="Book class slot"
        />
      ) : null}

      {resolveTarget ? (
        <BookingModal
          busy={busy}
          confirmLabel={resolveTarget.action === "approve" ? "Approve booking" : "Reject booking"}
          description={`Update ${resolveTarget.booking.user_nickname ?? "this member"} to ${resolveTarget.action}.`}
          inputLabel="Admin message"
          inputPlaceholder="Optional note for the member"
          inputValue={resolveMessage}
          onCancel={() => {
            setResolveTarget(null);
            setResolveMessage("");
          }}
          onConfirm={() => void handleResolve()}
          onInputChange={setResolveMessage}
          title={resolveTarget.action === "approve" ? "Approve booking" : "Reject booking"}
        />
      ) : null}

      {editor ? (
        <div className="fixed inset-0 z-40 flex items-center justify-center px-4" style={{ background: "rgba(0,0,0,0.7)" }}>
          <div className="w-full max-w-2xl rounded-[2rem] p-6 shadow-[0_30px_90px_rgba(0,0,0,0.7)]" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-sm font-semibold uppercase tracking-[0.24em] text-[#d95d39]">Admin slot editor</p>
                <h3 className="mt-3 text-2xl font-semibold" style={{ color: "#F0EDF8" }}>
                  {editor.slotId ? "Edit scheduled class" : "Create scheduled class"}
                </h3>
              </div>
              <button
                className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                style={{ background: "#1a1a28", color: "#c0c0d8" }}
                onClick={() => setEditor(null)}
                type="button"
              >
                Close
              </button>
            </div>

            <div className="mt-6 grid gap-4 md:grid-cols-2">
              {[
                { label: "Workout", type: "select" as const },
                { label: "Training type", type: "select-type" as const },
                { label: "Scheduled at", type: "datetime" as const },
                { label: "Capacity", type: "number-cap" as const },
                { label: "Timeout minutes", type: "number-timeout" as const },
              ].map(({ label, type }) => (
                <label key={label} className="space-y-2 text-sm font-semibold" style={{ color: "#8888aa" }}>
                  <span>{label}</span>
                  {type === "select" ? (
                    <select
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={{ background: "#0d0d18", border: "1px solid #1a1a28", color: "#F0EDF8" }}
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
                      style={{ background: "#0d0d18", border: "1px solid #1a1a28", color: "#F0EDF8" }}
                      onChange={(event) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, training_type: event.target.value as TrainingType } } : current,
                        )
                      }
                      value={editor.values.training_type}
                    >
                      {TRAINING_TYPE_OPTIONS.map((option) => (
                        <option key={option.value} value={option.value}>{option.label}</option>
                      ))}
                    </select>
                  ) : type === "datetime" ? (
                    <input
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={{ background: "#0d0d18", border: "1px solid #1a1a28", color: "#F0EDF8" }}
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
                      style={{ background: "#0d0d18", border: "1px solid #1a1a28", color: "#F0EDF8" }}
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
                      style={{ background: "#0d0d18", border: "1px solid #1a1a28", color: "#F0EDF8" }}
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

            <label className="mt-4 flex items-center gap-3 text-sm font-semibold" style={{ color: "#8888aa" }}>
              <input
                checked={editor.values.auto_approve}
                onChange={(event) =>
                  setEditor((current) =>
                    current ? { ...current, values: { ...current.values, auto_approve: event.target.checked } } : current,
                  )
                }
                type="checkbox"
              />
              Auto-approve bookings for this slot
            </label>

            <div className="mt-6 flex flex-wrap justify-between gap-3">
              {editor.slotId ? (
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "rgba(217,93,57,0.12)", border: "1px solid rgba(217,93,57,0.25)", color: "#d95d39" }}
                  onClick={() => void removeEditedSlot()}
                  type="button"
                >
                  Delete slot
                </button>
              ) : <span />}

              <div className="flex gap-3">
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                  style={{ background: "#1a1a28", color: "#c0c0d8" }}
                  onClick={() => setEditor(null)}
                  type="button"
                >
                  Cancel
                </button>
                <button
                  className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
                  style={{ background: "#F0EDF8", color: "#0A0A0F" }}
                  disabled={busy || !editor.values.master_workout_id}
                  onClick={() => void saveSlot()}
                  type="button"
                >
                  {busy ? "Saving..." : editor.slotId ? "Save changes" : "Create slot"}
                </button>
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </main>
  );
}
