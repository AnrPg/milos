"use client";

import { useState } from "react";

import { ApiError } from "@/api/client";
import { cancelBooking, sendSlotMessage, type ScheduleBooking, type ScheduleSlot, type TrainingType } from "@/api/schedule";
import { WorkoutPreviewDetail } from "@/components/workouts/WorkoutPreviewDetail";
import { WorkoutEditModal } from "@/components/workouts/WorkoutEditModal";
import { workoutTypeColor } from "@/lib/workout-colors";

function formatDateTime(isoString: string) {
  return new Intl.DateTimeFormat("en-US", {
    weekday: "long",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(isoString));
}

function formatDeadline(scheduledAt: string, timeoutMinutes: number) {
  const deadline = new Date(new Date(scheduledAt).getTime() - timeoutMinutes * 60 * 1000);
  const relative = `${timeoutMinutes >= 60 ? `${timeoutMinutes / 60}h` : `${timeoutMinutes}m`} before start`;
  const exact = new Intl.DateTimeFormat("en-GB", {
    weekday: "short",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(deadline);
  return { relative, exact };
}

type SlotPopupProps = {
  slot: ScheduleSlot;
  isAdmin: boolean;
  accessToken: string;
  onClose: () => void;
  onBook: () => void;
  onEdit: () => void;
  onApproveBooking: (booking: ScheduleBooking) => void;
  onRejectBooking: (booking: ScheduleBooking) => void;
  onCancelBooking?: () => void;
};

export function SlotPopup({
  slot,
  isAdmin,
  accessToken,
  onClose,
  onBook,
  onEdit,
  onApproveBooking,
  onRejectBooking,
  onCancelBooking,
}: SlotPopupProps) {
  const isPast = new Date(slot.scheduled_at) <= new Date();
  const canBook = !isAdmin && !slot.current_user_booking && slot.spots_remaining > 0 && !isPast;
  const [messageText, setMessageText] = useState("");
  const [messageSending, setMessageSending] = useState(false);
  const [messageSent, setMessageSent] = useState(false);
  const [messageError, setMessageError] = useState<string | null>(null);
  const [cancelling, setCancelling] = useState(false);
  const [cancelError, setCancelError] = useState<string | null>(null);
  const [editWorkoutOpen, setEditWorkoutOpen] = useState(false);

  async function handleSendMessage() {
    if (!messageText.trim()) return;
    setMessageSending(true);
    setMessageError(null);
    try {
      await sendSlotMessage(accessToken, slot.id, messageText.trim());
      setMessageSent(true);
      setMessageText("");
    } catch (err) {
      setMessageError(err instanceof Error ? err.message : "Failed to send message.");
    } finally {
      setMessageSending(false);
    }
  }

  async function handleCancelBooking() {
    if (!slot.current_user_booking) return;
    if (!window.confirm("Cancel your booking for this class?")) return;
    setCancelling(true);
    setCancelError(null);
    try {
      await cancelBooking(accessToken, slot.current_user_booking.id);
      onCancelBooking?.();
      onClose();
    } catch (err) {
      if (err instanceof ApiError && err.status === 422) {
        setCancelError("This booking can no longer be cancelled.");
      } else {
        setCancelError(err instanceof Error ? err.message : "Failed to cancel booking.");
      }
    } finally {
      setCancelling(false);
    }
  }

  const unavailableReason = canBook
    ? null
    : slot.current_user_booking
      ? null
      : isPast
        ? "This class has already started."
        : slot.spots_remaining === 0
          ? "This class is currently full."
          : "Booking is unavailable for this slot.";

  const deadline = formatDeadline(slot.scheduled_at, slot.booking_timeout_minutes);
  const typeColor = workoutTypeColor(slot.training_type);

  return (
    <div
      className="fixed inset-0 z-30 flex justify-end"
      style={{ background: "rgba(0,0,0,0.55)" }}
      onClick={onClose}
      role="presentation"
    >
      <div
        className="h-full w-full max-w-xl overflow-y-auto"
        style={{ background: "#111118", borderLeft: "1px solid #1a1a28" }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Sticky header — clears the top nav bar */}
        <div
          className="sticky top-0 z-10 flex items-center justify-between gap-4 px-6 py-4"
          style={{ background: "#111118", borderBottom: "1px solid #1a1a28" }}
        >
          <p
            className="text-xs font-bold uppercase tracking-[0.24em]"
            style={{ color: typeColor }}
          >
            {slot.training_type}
          </p>
          <button
            className="shrink-0 rounded-full px-3 py-1.5 text-sm font-semibold transition-colors"
            style={{ background: "#1a1a28", color: "#c0c0d8" }}
            onClick={onClose}
            type="button"
          >
            Close ✕
          </button>
        </div>

        <div className="p-6">
          <h2 className="text-3xl font-semibold" style={{ color: "#F0EDF8" }}>
            {slot.workout?.title ?? "Scheduled class"}
          </h2>
          <p className="mt-2 text-sm" style={{ color: "#8888aa" }}>
            {formatDateTime(slot.scheduled_at)}
          </p>

          {/* Info boxes */}
          <div className="mt-6 grid gap-4 md:grid-cols-3">
            <div
              className="rounded-[1.4rem] p-4"
              style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}
            >
              <p
                className="text-xs font-semibold uppercase tracking-[0.22em]"
                style={{ color: "#55556a" }}
              >
                Capacity
              </p>
              <p className="mt-2 text-2xl font-semibold" style={{ color: "#F0EDF8" }}>
                {slot.approved_booking_count}/{slot.capacity}
              </p>
            </div>

            <div
              className="rounded-[1.4rem] p-4"
              style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}
            >
              <p
                className="text-xs font-semibold uppercase tracking-[0.22em]"
                style={{ color: "#55556a" }}
              >
                Participation approval
              </p>
              <p className="mt-2 text-base font-semibold" style={{ color: "#F0EDF8" }}>
                {slot.auto_approve ? "Auto-confirmed" : "By coach"}
              </p>
            </div>

            <div
              className="rounded-[1.4rem] p-4"
              style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}
            >
              <p
                className="text-xs font-semibold uppercase tracking-[0.22em]"
                style={{ color: "#55556a" }}
              >
                Deadline to book
              </p>
              <p className="mt-2 text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                {deadline.relative}
              </p>
              <p className="mt-1 text-xs" style={{ color: "#8888aa" }}>
                ({deadline.exact})
              </p>
            </div>
          </div>

          {/* Booking status */}
          {slot.current_user_booking ? (
            <div className="mt-6 space-y-3">
              <div
                className="rounded-[1.4rem] p-4 text-sm"
                style={{
                  background: "rgba(156,121,156,0.12)",
                  border: "1px solid rgba(156,121,156,0.2)",
                }}
              >
                Your booking is currently{" "}
                <span className="font-semibold" style={{ color: "#9c799c" }}>
                  {slot.current_user_booking.status}
                </span>
                .
                {slot.current_user_booking.admin_message
                  ? ` ${slot.current_user_booking.admin_message}`
                  : null}
              </div>

              {(slot.current_user_booking.status === "pending" ||
                slot.current_user_booking.status === "approved") ? (
                <div>
                  {cancelError ? (
                    <p className="mb-2 text-xs" style={{ color: "#e07a5f" }}>{cancelError}</p>
                  ) : null}
                  <button
                    className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                    style={{
                      background: "rgba(217,93,57,0.1)",
                      border: "1px solid rgba(217,93,57,0.2)",
                      color: "#d95d39",
                    }}
                    disabled={cancelling}
                    onClick={() => void handleCancelBooking()}
                    type="button"
                  >
                    {cancelling ? "Cancelling…" : "Cancel booking"}
                  </button>
                </div>
              ) : null}
            </div>
          ) : null}

          {/* Workout preview */}
          <section
            className="mt-8 rounded-[1.8rem] p-5"
            style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}
          >
            <div className="mb-4 flex items-center justify-between gap-3">
              <h3 className="text-lg font-semibold" style={{ color: "#F0EDF8" }}>
                Workout
              </h3>
              {isAdmin ? (
                <div className="flex gap-2">
                  <button
                    className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                    style={{ background: "#1a1a28", color: "#c0c0d8" }}
                    onClick={onEdit}
                    type="button"
                  >
                    Edit slot
                  </button>
                  {slot.workout ? (
                    <button
                      className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                      style={{ background: "#1a1a28", color: "#c0c0d8" }}
                      onClick={() => setEditWorkoutOpen(true)}
                      type="button"
                    >
                      Edit workout
                    </button>
                  ) : null}
                </div>
              ) : null}
            </div>

            {slot.workout ? (
              <WorkoutPreviewDetail sections={slot.workout.sections} />
            ) : (
              <p className="text-sm" style={{ color: "#3a3a55" }}>
                No workout assigned to this slot.
              </p>
            )}

            {canBook ? (
              <button
                className="mt-5 w-full rounded-full px-5 py-3 text-sm font-semibold"
                style={{ background: "#F0EDF8", color: "#0A0A0F" }}
                onClick={onBook}
                type="button"
              >
                Book this class
              </button>
            ) : unavailableReason ? (
              <p
                className="mt-5 rounded-[1.2rem] px-4 py-3 text-sm"
                style={{ background: "#1a1a28", color: "#55556a" }}
              >
                {unavailableReason}
              </p>
            ) : null}
          </section>

          {/* Message to coach (members only) */}
          {!isAdmin ? (
            <section
              className="mt-6 rounded-[1.8rem] p-5"
              style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}
            >
              <h3 className="mb-3 text-base font-semibold" style={{ color: "#F0EDF8" }}>
                Message your coach
              </h3>
              {messageSent ? (
                <p
                  className="rounded-[1.2rem] px-4 py-3 text-sm font-semibold"
                  style={{ background: "rgba(16,185,129,0.1)", border: "1px solid rgba(16,185,129,0.2)", color: "#34d399" }}
                >
                  Message sent to your coach.
                </p>
              ) : (
                <div className="space-y-2">
                  <textarea
                    className="w-full resize-none rounded-[1rem] px-4 py-3 text-sm outline-none"
                    style={{
                      background: "#111118",
                      border: "1px solid #1a1a28",
                      color: "#F0EDF8",
                      minHeight: "80px",
                    }}
                    placeholder="Ask a question or leave a note for this class..."
                    value={messageText}
                    onChange={(e) => setMessageText(e.target.value)}
                    maxLength={1000}
                  />
                  {messageError ? (
                    <p className="text-xs" style={{ color: "#e07a5f" }}>{messageError}</p>
                  ) : null}
                  <button
                    className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-40"
                    style={{ background: "#1a1a28", color: "#c0c0d8" }}
                    disabled={messageSending || !messageText.trim()}
                    onClick={() => void handleSendMessage()}
                    type="button"
                  >
                    {messageSending ? "Sending…" : "Send message"}
                  </button>
                </div>
              )}
            </section>
          ) : null}

          {/* Admin: bookings list */}
          {isAdmin ? (
            <section
              className="mt-8 rounded-[1.8rem] p-5"
              style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}
            >
              <h3 className="text-lg font-semibold" style={{ color: "#F0EDF8" }}>
                Bookings
              </h3>
              <div className="mt-4 space-y-3">
                {slot.bookings.length === 0 ? (
                  <p className="text-sm" style={{ color: "#3a3a55" }}>
                    No bookings yet.
                  </p>
                ) : null}
                {slot.bookings.map((booking) => (
                  <div
                    className="rounded-[1.2rem] p-4"
                    style={{ background: "#111118", border: "1px solid #1a1a28" }}
                    key={booking.id}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                          {booking.user_nickname ?? booking.user_id}
                        </p>
                        <p
                          className="mt-1 text-xs uppercase tracking-[0.18em]"
                          style={{ color: "#55556a" }}
                        >
                          {booking.status}
                        </p>
                        {booking.admin_message ? (
                          <p className="mt-2 text-sm" style={{ color: "#8888aa" }}>
                            {booking.admin_message}
                          </p>
                        ) : null}
                      </div>

                      {booking.status === "pending" ? (
                        <div className="flex gap-2">
                          <button
                            className="rounded-full px-3 py-2 text-xs font-semibold"
                            style={{ background: "#F0EDF8", color: "#0A0A0F" }}
                            onClick={() => onApproveBooking(booking)}
                            type="button"
                          >
                            Approve
                          </button>
                          <button
                            className="rounded-full px-3 py-2 text-xs font-semibold"
                            style={{
                              background: "rgba(217,93,57,0.12)",
                              border: "1px solid rgba(217,93,57,0.25)",
                              color: "#d95d39",
                            }}
                            onClick={() => onRejectBooking(booking)}
                            type="button"
                          >
                            Reject
                          </button>
                        </div>
                      ) : null}
                    </div>
                  </div>
                ))}
              </div>
            </section>
          ) : null}
        </div>
      </div>

      {editWorkoutOpen && slot.workout && isAdmin ? (
        <WorkoutEditModal
          workoutId={slot.workout.id}
          workoutTitle={slot.workout.title}
          accessToken={accessToken}
          context={{ kind: "slot", sourceId: slot.id, sourceLabel: `class on ${slot.scheduled_at}` }}
          onClose={() => setEditWorkoutOpen(false)}
        />
      ) : null}
    </div>
  );
}
