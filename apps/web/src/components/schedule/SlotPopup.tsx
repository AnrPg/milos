"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useState } from "react";
import { useLocale } from "next-intl";

import { ApiError } from "@/api/client";
import { cancelBooking, sendSlotMessage, type ScheduleBooking, type ScheduleSlot } from "@/api/schedule";
import { downloadIcsEvent } from "@/lib/ics";
import { WorkoutPreviewDetail } from "@/components/workouts/WorkoutPreviewDetail";
import { WorkoutEditModal } from "@/components/workouts/WorkoutEditModal";
import { workoutTypeColor } from "@/lib/workout-colors";
import { SemanticLabel } from "@/components/semantic-label";

function formatDateTime(locale: string, isoString: string) {
  return new Intl.DateTimeFormat(locale, {
    weekday: "long",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(isoString));
}

function formatDeadline(locale: string, scheduledAt: string, timeoutMinutes: number) {
  const deadline = new Date(new Date(scheduledAt).getTime() - timeoutMinutes * 60 * 1000);
  const exact = new Intl.DateTimeFormat(locale, {
    weekday: "short",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(deadline);
  return { exact };
}

function timeoutMinutesLabel(timeoutMinutes: number) {
  return timeoutMinutes >= 60 ? `${timeoutMinutes / 60}h` : `${timeoutMinutes}m`;
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
  const i18n = useUiTranslations();
  const locale = useLocale();
  const isPast = new Date(slot.scheduled_at) <= new Date();
  const canBook = !isAdmin && !slot.current_user_booking && slot.spots_remaining > 0 && !isPast;
  const [messageText, setMessageText] = useState("");
  const [messageSending, setMessageSending] = useState(false);
  const [messageSent, setMessageSent] = useState(false);
  const [messageError, setMessageError] = useState<string | null>(null);
  const [cancelling, setCancelling] = useState(false);
  const [cancelError, setCancelError] = useState<string | null>(null);
  const [editWorkoutOpen, setEditWorkoutOpen] = useState(false);
  const [activeScale, setActiveScale] = useState<string | null>(null);

  const allScales = (() => {
    const seen = new Map<string, { slug: string; label: string; sortOrder: number }>();
    for (const section of slot.workout?.sections ?? []) {
      for (const ex of section.exercises) {
        for (const v of ex.variations ?? []) {
          const slug = v.scale_level?.slug;
          if (slug && !seen.has(slug)) {
            seen.set(slug, {
              slug,
              label: v.scale_level?.label ?? slug,
              sortOrder: v.scale_level?.sort_order ?? 0,
            });
          }
        }
      }
    }
    return Array.from(seen.values()).sort((a, b) =>
      a.sortOrder !== b.sortOrder ? a.sortOrder - b.sortOrder : a.label.localeCompare(b.label),
    );
  })();

  async function handleSendMessage() {
    if (!messageText.trim()) return;
    setMessageSending(true);
    setMessageError(null);
    try {
      await sendSlotMessage(accessToken, slot.id, messageText.trim());
      setMessageSent(true);
      setMessageText("");
    } catch (err) {
      setMessageError(err instanceof Error ? localizeError(err, i18n) : i18n("failedToSendMessage0f22ccd"));
    } finally {
      setMessageSending(false);
    }
  }

  async function handleCancelBooking() {
    if (!slot.current_user_booking) return;
    if (!window.confirm(i18n("cancelYourBookingForThisClass0c2112f"))) return;
    setCancelling(true);
    setCancelError(null);
    try {
      await cancelBooking(accessToken, slot.current_user_booking.id);
      onCancelBooking?.();
      onClose();
    } catch (err) {
      if (err instanceof ApiError && err.status === 422) {
        setCancelError(i18n("thisBookingCanNoLongerBeCancelled0dbc8ac"));
      } else {
        setCancelError(err instanceof Error ? localizeError(err, i18n) : i18n("failedToCancelBooking2cd9432"));
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
        ? i18n("thisClassHasAlreadyStarteda7aa12f")
        : slot.spots_remaining === 0
          ? i18n("thisClassIsCurrentlyFullfc75983")
          : i18n("bookingIsUnavailableForThisSlot8a07037");

  const deadline = formatDeadline(locale, slot.scheduled_at, slot.booking_timeout_minutes);
  const deadlineRelative = i18n("beforeStart", {
    duration: timeoutMinutesLabel(slot.booking_timeout_minutes),
  });
  const typeColor = workoutTypeColor(slot.class_type.slug);

  return (
    <div
      className="fixed inset-0 z-30 flex justify-end"
      style={{ background: "rgba(0,0,0,0.55)" }}
      onClick={onClose}
      role="presentation"
    >
      <div
        className="h-full w-full max-w-xl overflow-y-auto"
        style={{ background: "var(--panel)", borderInlineStart: "1px solid var(--border)", paddingTop: "3.25rem" }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Sticky header — clears the top nav bar */}
        <div
          className="sticky top-0 z-10 flex items-center justify-between gap-4 px-6 py-4"
          style={{ background: "var(--panel)", borderBottom: "1px solid var(--border)" }}
        >
          <p
            className="text-xs font-bold uppercase tracking-[0.24em]"
            style={{ color: typeColor }}
          >
            {slot.class_type.name}
          </p>
          <button
            className="shrink-0 rounded-full px-3 py-1.5 text-sm font-semibold transition-colors"
            style={{ background: "var(--card)", color: "var(--text-soft)" }}
            onClick={onClose}
            type="button"
          >
            {i18n("closefeb3e25")}
          </button>
        </div>

        <div className="p-6">
          <div className="flex items-start justify-between gap-4">
            <div className="min-w-0">
              <h2 className="text-3xl font-semibold" style={{ color: "var(--text)" }}>
                {slot.workout?.title ?? i18n("scheduledClass571cba0")}
              </h2>
              <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>
                {formatDateTime(locale, slot.scheduled_at)}
              </p>
            </div>
            <button
              className="mt-1 shrink-0 rounded-full px-4 py-2 text-xs font-semibold transition-colors"
              style={{
                background: "color-mix(in srgb, var(--primary) 18%, transparent)",
                color: "var(--primary-strong)",
                border: "1px solid color-mix(in srgb, var(--primary) 45%, transparent)",
              }}
              onClick={() =>
                downloadIcsEvent({
                  title: slot.workout?.title ?? i18n("scheduledClass571cba0"),
                  date: slot.scheduled_at.slice(0, 10),
                  datetime: slot.scheduled_at,
                  durationMinutes: 60,
                })
              }
              type="button"
            >
              {i18n("addToCalendar33cead7")}
            </button>
          </div>

          {/* Compact info strip (admin sees full detail; members get a summary) */}
          {isAdmin ? (
            <div className="mt-6 grid gap-4 md:grid-cols-3">
              <div
                className="rounded-[1.4rem] p-4"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
              >
                <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
                  {i18n("capacity45bd908")}
                </p>
                <p className="mt-2 text-2xl font-semibold" style={{ color: "var(--text)" }}>
                  {slot.approved_booking_count}/{slot.capacity}
                </p>
              </div>
              <div
                className="rounded-[1.4rem] p-4"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
              >
                <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
                  {i18n("approval8cc047a")}
                </p>
                <p className="mt-2 text-base font-semibold" style={{ color: "var(--text)" }}>
                  {slot.auto_approve ? i18n("autoc614ba7") : i18n("manual4e836fd")}
                </p>
              </div>
              <div
                className="rounded-[1.4rem] p-4"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
              >
                <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
                  {i18n("bookByb152b3b")}
                </p>
                <p className="mt-2 text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {deadlineRelative}
                </p>
                <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>({deadline.exact})</p>
              </div>
            </div>
          ) : (
            <div className="mt-4 flex flex-wrap gap-2">
              <span
                className="rounded-full px-3 py-1 text-xs font-semibold"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--muted)" }}
              >
                {slot.spots_remaining} {i18n("spot9f4b527")}{slot.spots_remaining !== 1 ? i18n("sa0f1490") : ""} {i18n("left12c0f1f")}
              </span>
              <span
                className="rounded-full px-3 py-1 text-xs font-semibold"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--muted)" }}
              >
                {i18n("bookByb152b3b")} {deadlineRelative}
              </span>
              {slot.auto_approve ? null : (
                <span
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={{ background: "color-mix(in srgb, var(--warning) 14%, transparent)", border: "1px solid color-mix(in srgb, var(--warning) 30%, transparent)", color: "var(--warning)" }}
                >
                  {i18n("requiresApproval4ecb6f5")}
                </span>
              )}
            </div>
          )}

          {/* Pending-approval banner */}
          {slot.current_user_booking?.status === "pending" && !isAdmin ? (
            <div
              className="mt-5 rounded-[1.4rem] px-5 py-4 text-sm"
              style={{
                background: "color-mix(in srgb, var(--warning) 12%, transparent)",
                border: "1px solid color-mix(in srgb, var(--warning) 30%, transparent)",
              }}
            >
              <p className="font-semibold" style={{ color: "var(--warning)" }}>
                {i18n("waitingForCoachApproval123b28c")}
              </p>
              <p className="mt-1" style={{ color: "var(--muted)" }}>
                {i18n("yourSpotIsReservedYouLlGetA5f8a9e3")}
              </p>
            </div>
          ) : null}

          {/* Approved booking confirmation */}
          {slot.current_user_booking?.status === "approved" && !isAdmin ? (
            <div
              className="mt-5 rounded-[1.4rem] px-5 py-4 text-sm"
              style={{
                background: "color-mix(in srgb, var(--success) 12%, transparent)",
                border: "1px solid color-mix(in srgb, var(--success) 30%, transparent)",
              }}
            >
              <p className="font-semibold" style={{ color: "var(--success)" }}>{i18n("youReConfirmed433ef6b")}</p>
              {slot.current_user_booking.admin_message ? (
                <p className="mt-1" style={{ color: "var(--muted)" }}>
                  {slot.current_user_booking.admin_message}
                </p>
              ) : null}
            </div>
          ) : null}

          {/* Cancel booking action */}
          {slot.current_user_booking &&
            (slot.current_user_booking.status === "pending" || slot.current_user_booking.status === "approved") &&
            !isAdmin ? (
            <div className="mt-3">
              {cancelError ? (
                <p className="mb-2 text-xs" style={{ color: "var(--danger)" }}>{cancelError}</p>
              ) : null}
              <button
                className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                style={{
                  background: "color-mix(in srgb, var(--danger) 10%, transparent)",
                  border: "1px solid color-mix(in srgb, var(--danger) 24%, transparent)",
                  color: "var(--danger)",
                }}
                disabled={cancelling}
                onClick={() => void handleCancelBooking()}
                type="button"
              >
                {cancelling ? i18n("cancellingcee1848") : i18n("cancelBookingc6085eb")}
              </button>
            </div>
          ) : null}

          {/* Workout preview */}
          <section
            className="mt-8 rounded-[1.8rem] p-5"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <div className="mb-4 flex items-center justify-between gap-3">
              <h3 className="text-lg font-semibold" style={{ color: "var(--text)" }}>
                {i18n("workout39463a5")}
              </h3>
              {isAdmin ? (
                <div className="flex gap-2">
                  <button
                    className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                    style={{ background: "var(--card)", color: "var(--text-soft)" }}
                    onClick={onEdit}
                    type="button"
                  >
                    {i18n("editSlot4754d1f")}
                  </button>
                  {slot.workout ? (
                    <button
                      className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                      style={{ background: "var(--card)", color: "var(--text-soft)" }}
                      onClick={() => setEditWorkoutOpen(true)}
                      type="button"
                    >
                      {i18n("editWorkoutd299ce5")}
                    </button>
                  ) : null}
                </div>
              ) : null}
            </div>

            {/* Scale chips — member-facing global scale selector */}
            {!isAdmin && allScales.length > 0 ? (
              <div className="mb-4 flex flex-wrap gap-1.5">
                <button
                  type="button"
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={{
                    background: activeScale === null ? "var(--primary)" : "var(--card)",
                    color: activeScale === null ? "var(--primary-contrast)" : "var(--text-soft)",
                    border: activeScale === null ? "1px solid var(--primary)" : "1px solid var(--border-strong)",
                  }}
                  onClick={() => setActiveScale(null)}
                >
                  {i18n("base077fe9c")}
                </button>
                {allScales.map((scale) => (
                  <button
                    key={scale.slug}
                    type="button"
                    className="rounded-full px-3 py-1 text-xs font-semibold"
                    style={{
                      background: activeScale === scale.slug ? "var(--primary)" : "var(--card)",
                      color: activeScale === scale.slug ? "var(--primary-contrast)" : "var(--text-soft)",
                      border: activeScale === scale.slug ? "1px solid var(--primary)" : "1px solid var(--border-strong)",
                    }}
                    onClick={() => setActiveScale(scale.slug)}
                  >
                    {scale.label}
                  </button>
                ))}
              </div>
            ) : null}

            {slot.workout ? (
              <WorkoutPreviewDetail
                sections={slot.workout.sections}
                activeScaleOverride={!isAdmin ? activeScale : undefined}
                hideScaleChips={!isAdmin}
              />
            ) : (
              <p className="text-sm" style={{ color: "var(--dim)" }}>
                {i18n("noWorkoutAssignedToThisSlotac3ec23")}
              </p>
            )}

            {canBook ? (
              <button
                className="mt-5 w-full rounded-full px-5 py-3 text-sm font-semibold"
                style={{ background: "var(--text)", color: "var(--bg)" }}
                onClick={onBook}
                type="button"
              >
                {i18n("bookThisClass4d08b11")}
              </button>
            ) : unavailableReason ? (
              <p
                className="mt-5 rounded-[1.2rem] px-4 py-3 text-sm"
                style={{ background: "var(--card)", color: "var(--dim)" }}
              >
                {unavailableReason}
              </p>
            ) : null}
          </section>

          {/* Chat section (members only) */}
          {!isAdmin ? (
            <section
              className="mt-6 rounded-[1.8rem] p-5"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
            >
              <h3 className="mb-1 text-base font-semibold" style={{ color: "var(--text)" }}>
                {i18n("messageYourCoachc0c790e")}
              </h3>
              <p className="mb-4 text-xs" style={{ color: "var(--dim)" }}>
                {i18n("askAQuestionOrLeaveANoteAbout63a1bde")}
              </p>
              {messageSent ? (
                <div
                  className="flex items-start gap-3 rounded-[1.2rem] px-4 py-3"
                  style={{
                    background: "color-mix(in srgb, var(--success) 10%, transparent)",
                    border: "1px solid color-mix(in srgb, var(--success) 24%, transparent)",
                  }}
                >
                  <span style={{ color: "var(--success)" }}>✓</span>
                  <div>
                    <p className="text-sm font-semibold" style={{ color: "var(--success)" }}>
                      {i18n("messageSent9cf1b68")}
                    </p>
                    <p className="mt-0.5 text-xs" style={{ color: "var(--muted)" }}>
                      {i18n("yourCoachWillSeeItBeforeTheClassa812936")}
                    </p>
                  </div>
                </div>
              ) : (
                <div className="space-y-2">
                  <div
                    className="flex gap-3 rounded-[1.4rem] p-3"
                    style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                  >
                    <textarea
                      className="flex-1 resize-none bg-transparent text-sm outline-none"
                      style={{ color: "var(--text)", minHeight: "64px" }}
                      placeholder={i18n("typeYourMessage6733d4f")}
                      value={messageText}
                      onChange={(e) => setMessageText(e.target.value)}
                      maxLength={1000}
                    />
                    <button
                      className="self-end shrink-0 rounded-2xl px-4 py-2 text-sm font-semibold disabled:opacity-40"
                      style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                      disabled={messageSending || !messageText.trim()}
                      onClick={() => void handleSendMessage()}
                      type="button"
                    >
                      {messageSending ? "…" : i18n("send9bc2575")}
                    </button>
                  </div>
                  {messageError ? (
                    <p className="text-xs" style={{ color: "var(--danger)" }}>{messageError}</p>
                  ) : null}
                </div>
              )}
            </section>
          ) : null}

          {/* Admin: bookings list */}
          {isAdmin ? (
            <section
              className="mt-8 rounded-[1.8rem] p-5"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
            >
              <h3 className="text-lg font-semibold" style={{ color: "var(--text)" }}>
                {i18n("bookings135229c")}
              </h3>
              <div className="mt-4 space-y-3">
                {slot.bookings.length === 0 ? (
                  <p className="text-sm" style={{ color: "var(--dim)" }}>
                    {i18n("noBookingsYetdb81e7a")}
                  </p>
                ) : null}
                {slot.bookings.map((booking) => (
                  <div
                    className="rounded-[1.2rem] p-4"
                    style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                    key={booking.id}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                          {booking.user_nickname ?? booking.user_id}
                        </p>
                        <p
                          className="mt-1 text-xs uppercase tracking-[0.18em]"
                          style={{ color: "var(--dim)" }}
                        >
                          <SemanticLabel value={booking.status} />
                        </p>
                        {booking.admin_message ? (
                          <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>
                            {booking.admin_message}
                          </p>
                        ) : null}
                      </div>

                      {booking.status === "pending" ? (
                        <div className="flex gap-2">
                          <button
                            className="rounded-full px-3 py-2 text-xs font-semibold"
                            style={{ background: "var(--text)", color: "var(--bg)" }}
                            onClick={() => onApproveBooking(booking)}
                            type="button"
                          >
                            {i18n("approve7b2c7f1")}
                          </button>
                          <button
                            className="rounded-full px-3 py-2 text-xs font-semibold"
                            style={{
                              background: "color-mix(in srgb, var(--danger) 12%, transparent)",
                              border: "1px solid color-mix(in srgb, var(--danger) 25%, transparent)",
                              color: "var(--danger)",
                            }}
                            onClick={() => onRejectBooking(booking)}
                            type="button"
                          >
                            {i18n("reject2b03b59")}
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
          context={{ kind: "slot", sourceId: slot.id, sourceLabel: i18n("classOn5e673bd") + (slot.scheduled_at) }}
          onClose={() => setEditWorkoutOpen(false)}
        />
      ) : null}
    </div>
  );
}
