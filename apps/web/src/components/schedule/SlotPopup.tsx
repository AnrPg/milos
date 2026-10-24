"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useState } from "react";
import { useLocale } from "next-intl";

import { ApiError } from "@/api/client";
import {
  cancelBooking,
  joinWaitlist,
  sendSlotMessage,
  type ScheduleBooking,
  type ScheduleLocation,
  type ScheduleSlot,
} from "@/api/schedule";
import { downloadIcsEvent } from "@/lib/ics";
import { WorkoutPreviewDetail, type PreviewSection } from "@/components/workouts/WorkoutPreviewDetail";
import { WorkoutEditModal } from "@/components/workouts/WorkoutEditModal";
import { workoutTypeColor } from "@/lib/workout-colors";
import { ClassWorkoutNotice } from "@/components/schedule/ClassWorkoutNotice";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import Link from "next/link";
import {
  InjuryWarningBadge,
  MyInjuryWarningsPanel,
  RosterInjuryWarningsPanel,
  useSlotInjuryWarnings,
} from "@/components/wellbeing/InjuryWarnings";
import { warningLevelFor, warningLevelsByUser } from "@/lib/injury-warnings";
import { AdminSlotRoster } from "@/components/schedule/AdminSlotRoster";
import { FeltSummaryCard } from "@/components/wod-goals/FeltSummaryCard";
import { GuestBookingPanel } from "@/components/schedule/GuestBookingPanel";
import {
  isEventSlot,
  localizeMemberBookingError,
  memberSlotState,
  slotCreditCost,
  slotLocationName,
  waitlistPositionLabel,
} from "@/components/schedule/member-booking";
import { zonedText } from "@/lib/zoned-time";
import { YourTime } from "@/components/zoned-time";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

// ADR-179: on the gym's clock (`zone`), its city added when the viewer's differs.
function formatDateTime(locale: string, isoString: string, zone: string | null) {
  return zonedText(isoString, zone, locale, {
    weekday: "long",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function formatDeadline(locale: string, scheduledAt: string, timeoutMinutes: number, zone: string | null) {
  const deadline = new Date(new Date(scheduledAt).getTime() - timeoutMinutes * 60 * 1000);
  const exact = zonedText(deadline, zone, locale, {
    weekday: "short",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
  return { exact };
}

function timeoutMinutesLabel(timeoutMinutes: number) {
  return timeoutMinutes >= 60 ? `${timeoutMinutes / 60}h` : `${timeoutMinutes}m`;
}

type SlotPopupProps = {
  slot: ScheduleSlot;
  /** ADR-179: the gym's zone; the class shows on its clock. */
  timeZone?: string | null;
  isAdmin: boolean;
  accessToken: string;
  onClose: () => void;
  onBook: () => void;
  onEdit: () => void;
  onDelete?: () => void;
  onApproveBooking: (booking: ScheduleBooking) => void;
  onRejectBooking: (booking: ScheduleBooking) => void;
  /** Called after the member withdraws their own booking (the popup closes). */
  onCancelBooking?: (result: { lateCancellation: boolean }) => void;
  /** Called after a waitlist or guest change; the popup stays open. */
  onSlotChanged?: () => void;
  locations?: ScheduleLocation[];
  /** The member's package includes guest passes (ADR-097). */
  guestsIncluded?: boolean;
  /** ADR-176: "+ New WOD" from the missing-WOD notice (writes one, comes back linked). */
  onCreateWorkout?: () => void;
};

export function SlotPopup({
  slot,
  timeZone = null,
  isAdmin,
  accessToken,
  onClose,
  onBook,
  onEdit,
  onDelete,
  onApproveBooking,
  onRejectBooking,
  onCancelBooking,
  onSlotChanged,
  locations,
  guestsIncluded = false,
  onCreateWorkout,
}: SlotPopupProps) {
  const i18n = useUiTranslations();
  const locale = useLocale();
  const organizationSlug = useOrganizationSlug();
  const isPast = new Date(slot.scheduled_at) <= new Date();
  const memberState = memberSlotState(slot);
  const canBook = !isAdmin && memberState.kind === "bookable";
  const canJoinWaitlist = !isAdmin && memberState.kind === "waitlist_open";
  const locationName = slotLocationName(slot, locations);
  const creditCost = slotCreditCost(slot);
  const [waitlistBusy, setWaitlistBusy] = useState(false);
  const [waitlistError, setWaitlistError] = useState<string | null>(null);
  const [messageText, setMessageText] = useState("");
  const [messageSending, setMessageSending] = useState(false);
  const [messageSent, setMessageSent] = useState(false);
  const [messageError, setMessageError] = useState<string | null>(null);
  const [cancelling, setCancelling] = useState(false);
  const [cancelError, setCancelError] = useState<string | null>(null);
  const [editWorkoutOpen, setEditWorkoutOpen] = useState(false);
  const [activeScale, setActiveScale] = useState<string | null>(null);
  // ADR-124: informational injury warnings for booked members (staff) and
  // for the member's own booking. Never blocks booking or attendance.
  const hasBookedMembers = slot.bookings.some(
    (booking) => booking.status === "approved" || booking.status === "pending",
  );
  const slotInjuryWarnings = useSlotInjuryWarnings(
    accessToken,
    slot.id,
    isAdmin && Boolean(slot.workout) && hasBookedMembers,
  );
  const injuryLevels = warningLevelsByUser(slotInjuryWarnings.data?.athletes ?? []);
  const bookingNames = new Map(
    slot.bookings.map((booking) => [booking.user_id, booking.user_nickname ?? booking.user_id]),
  );
  const ownBookingActive =
    slot.current_user_booking?.status === "approved" || slot.current_user_booking?.status === "pending";

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
      const result = await cancelBooking(accessToken, slot.current_user_booking.id);
      onCancelBooking?.(result);
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

  async function handleJoinWaitlist() {
    setWaitlistBusy(true);
    setWaitlistError(null);
    try {
      await joinWaitlist(accessToken, slot.id);
      onSlotChanged?.();
    } catch (err) {
      setWaitlistError(localizeMemberBookingError(err, i18n, locale, "waitlist"));
    } finally {
      setWaitlistBusy(false);
    }
  }

  async function handleLeaveWaitlist() {
    if (!slot.current_user_booking) return;
    if (!window.confirm(i18n("mbLeaveWaitlistConfirm"))) return;
    setWaitlistBusy(true);
    setWaitlistError(null);
    try {
      await cancelBooking(accessToken, slot.current_user_booking.id);
      onSlotChanged?.();
    } catch (err) {
      setWaitlistError(localizeMemberBookingError(err, i18n, locale, "withdraw"));
    } finally {
      setWaitlistBusy(false);
    }
  }

  const unavailableReason = canBook || canJoinWaitlist
    ? null
    : slot.current_user_booking
      ? null
      : isPast
        ? i18n("thisClassHasAlreadyStarteda7aa12f")
        : slot.spots_remaining === 0
          ? i18n("thisClassIsCurrentlyFullfc75983")
          : i18n("bookingIsUnavailableForThisSlot8a07037");

  const deadline = formatDeadline(locale, slot.scheduled_at, slot.booking_timeout_minutes, timeZone);
  const deadlineRelative = i18n("beforeStart", {
    duration: timeoutMinutesLabel(slot.booking_timeout_minutes),
  });
  const typeColor = workoutTypeColor(slot.class_type.slug);

  return (
    <>
      <Dialog
        onClose={onClose}
        bare
        variant="drawer"
        size="xl"
        ariaLabel={slot.class_type.name}
        panelClassName="overflow-y-auto"
      >
        {/* Sticky header */}
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
                {formatDateTime(locale, slot.scheduled_at, timeZone)}
                <YourTime at={slot.scheduled_at} zone={timeZone} format="day-time" />
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

          {isAdmin ? (
            <ClassWorkoutNotice slot={slot} accessToken={accessToken} timeZone={timeZone} onLinked={onSlotChanged} onCreateNew={onCreateWorkout} />
          ) : null}

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
                {i18n("value0SpotsLeft3ff0ef6", { value0: slot.spots_remaining })}
              </span>
              {slot.waitlist_count ? (
                <span
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--muted)" }}
                >
                  {i18n("mbWaitlistCount", { count: slot.waitlist_count })}
                </span>
              ) : null}
              {isEventSlot(slot) ? (
                <span
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={{ background: "color-mix(in srgb, var(--primary) 14%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 30%, transparent)", color: "var(--primary-strong)" }}
                >
                  {i18n("mbEventMarker")}
                </span>
              ) : null}
              {locationName ? (
                <span
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--muted)" }}
                >
                  {i18n("mbLocationAt", { location: locationName })}
                </span>
              ) : null}
              {creditCost ? (
                <span
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--muted)" }}
                >
                  {i18n("mbUsesVisits", { count: creditCost })}
                </span>
              ) : null}
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

          {/* Class timer: coach remote + wall display for staff, live clock for booked members */}
          {isAdmin || slot.current_user_booking?.status === "approved" ? (
            <div className="mt-4 flex flex-wrap gap-2" role="group" aria-label={i18n("classTimerLinksLabel")}>
              {isAdmin ? (
                <Link
                  href={adminHref(`/class-timer/${slot.id}/control`, organizationSlug)}
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                >
                  {i18n("classTimerRemoteLink")}
                </Link>
              ) : null}
              <Link
                href={adminHref(`/class-timer/${slot.id}/display`, organizationSlug)}
                target={isAdmin ? "_blank" : undefined}
                className="rounded-full px-4 py-2 text-sm font-semibold"
                style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
              >
                {isAdmin ? i18n("classTimerDisplayLink") : i18n("classTimerFollowLink")}
              </Link>
            </div>
          ) : null}

          {/* Waitlist place — never shown as a booking */}
          {memberState.kind === "waitlisted" && !isAdmin ? (
            <div
              className="mt-5 rounded-[1.4rem] px-5 py-4 text-sm"
              style={{
                background: "color-mix(in srgb, var(--info) 12%, transparent)",
                border: "1px solid color-mix(in srgb, var(--info) 30%, transparent)",
              }}
            >
              <p className="font-semibold" style={{ color: "var(--info)" }}>
                {waitlistPositionLabel(memberState.position, i18n)}
              </p>
              <p className="mt-1" style={{ color: "var(--muted)" }}>
                {i18n("mbWaitlistExplainer")}
              </p>
              {waitlistError ? (
                <ErrorNotice variant="field" className="mt-2">{waitlistError}</ErrorNotice>
              ) : null}
              <button
                className="mt-3 rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--card)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
                disabled={waitlistBusy}
                onClick={() => void handleLeaveWaitlist()}
                type="button"
              >
                {i18n("mbLeaveWaitlist")}
              </button>
            </div>
          ) : null}

          {!isAdmin ? (
            <GuestBookingPanel
              accessToken={accessToken}
              guestsIncluded={guestsIncluded}
              onChanged={() => onSlotChanged?.()}
              slot={slot}
            />
          ) : null}

          {/* Cancel booking action */}
          {slot.current_user_booking &&
            (slot.current_user_booking.status === "pending" || slot.current_user_booking.status === "approved") &&
            !isAdmin ? (
            <div className="mt-3">
              {cancelError ? (
                <ErrorNotice variant="field" className="mb-2">{cancelError}</ErrorNotice>
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

          {/* ADR-125: the member's own version of this class (only ever theirs).
              Informational only: members start it from My workouts, and staff
              program it from the user's profile - no class-view action. */}
          {!isAdmin && slot.my_version ? (
            <section
              className="mt-8 rounded-[1.8rem] p-5"
              style={{
                background: "color-mix(in srgb, var(--primary) 8%, var(--panel-muted))",
                border: "1px solid color-mix(in srgb, var(--primary) 30%, var(--border))",
              }}
            >
              <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--primary)" }}>
                    {i18n("memberProgrammingYourVersion")}
                  </p>
                  <h3 className="mt-1 text-lg font-semibold" style={{ color: "var(--text)" }}>
                    {slot.my_version.workout.title}
                  </h3>
                  <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
                    {i18n("memberProgrammingYourVersionHint")}
                  </p>
                </div>
                {slot.my_version.execution_status === "completed" ? (
                  <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "color-mix(in srgb, var(--success) 15%, transparent)", color: "var(--success)" }}>
                    {i18n("donea821d15")}
                  </span>
                ) : null}
              </div>
              <WorkoutPreviewDetail
                sections={slot.my_version.workout.sections as PreviewSection[]}
                content={slot.my_version.workout.content}
                authoringMode={slot.my_version.workout.authoring_mode}
                freeTextBody={slot.my_version.workout.free_text_body}
                freeTextDocument={slot.my_version.workout.free_text_document}
              />
            </section>
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
                  {onDelete ? (
                    <button
                      className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                      style={{ background: "color-mix(in srgb, var(--danger) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--danger) 24%, transparent)", color: "var(--danger)" }}
                      onClick={onDelete}
                      type="button"
                    >
                      {i18n("deletef6fdbe4")}
                    </button>
                  ) : null}
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
                content={slot.workout.content}
                activeScaleOverride={!isAdmin ? activeScale : undefined}
                hideScaleChips={!isAdmin}
                authoringMode={slot.workout.authoring_mode}
                freeTextBody={slot.workout.free_text_body}
                freeTextDocument={slot.workout.free_text_document}
              />
            ) : (
              <p className="text-sm" style={{ color: "var(--dim)" }}>
                {i18n("noWorkoutAssignedToThisSlotac3ec23")}
              </p>
            )}

            {!isAdmin && slot.workout && ownBookingActive ? (
              <div className="mt-5">
                <MyInjuryWarningsPanel
                  accessToken={accessToken}
                  workoutId={slot.workout.id}
                  surface="class_detail"
                  sourceContextId={slot.id}
                />
              </div>
            ) : null}

            {canBook ? (
              <button
                className="mt-5 w-full rounded-full px-5 py-3 text-sm font-semibold"
                style={{ background: "var(--text)", color: "var(--bg)" }}
                onClick={onBook}
                type="button"
              >
                {i18n("bookThisClass4d08b11")}
              </button>
            ) : canJoinWaitlist ? (
              <div className="mt-5">
                <p className="mb-2 text-sm" style={{ color: "var(--muted)" }}>
                  {i18n("mbClassFullWaitlistHint")}
                </p>
                {waitlistError ? (
                  <ErrorNotice variant="field" className="mb-2">{waitlistError}</ErrorNotice>
                ) : null}
                <button
                  className="w-full rounded-full px-5 py-3 text-sm font-semibold disabled:opacity-50"
                  style={{ background: "var(--text)", color: "var(--bg)" }}
                  disabled={waitlistBusy}
                  onClick={() => void handleJoinWaitlist()}
                  type="button"
                >
                  {i18n("mbJoinWaitlist")}
                </button>
              </div>
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
                    <ErrorNotice variant="field">{messageError}</ErrorNotice>
                  ) : null}
                </div>
              )}
            </section>
          ) : null}

          {/* Admin: what members felt in this class (WOD goals, ADR-163) */}
          {isAdmin && slot.workout && isPast ? <FeltSummaryCard source={{ kind: "slot", id: slot.id }} className="mt-4" /> : null}

          {/* Admin: bookings list */}
          {isAdmin ? (
            <AdminSlotRoster
              slot={slot}
              onApproveBooking={onApproveBooking}
              onRejectBooking={onRejectBooking}
              header={
                slotInjuryWarnings.data ? (
                  <RosterInjuryWarningsPanel
                    accessToken={accessToken}
                    slotId={slot.id}
                    workoutId={slotInjuryWarnings.data.workout_id}
                    athletes={slotInjuryWarnings.data.athletes}
                    level={slotInjuryWarnings.data.level}
                    nameFor={(userId) => bookingNames.get(userId) ?? i18n("injuryWarningUnknownPerson")}
                  />
                ) : slotInjuryWarnings.isError ? (
                  <ErrorNotice variant="field">
                    {i18n("injuryWarningLoadFailed")}
                  </ErrorNotice>
                ) : null
              }
              badgeFor={(booking) => <InjuryWarningBadge level={warningLevelFor(injuryLevels, booking.user_id)} />}
            />
          ) : null}
        </div>
      </Dialog>

      {editWorkoutOpen && slot.workout && isAdmin ? (
        <WorkoutEditModal
          workoutId={slot.workout.id}
          workoutTitle={slot.workout.title}
          accessToken={accessToken}
          context={{ kind: "slot", sourceId: slot.id, sourceLabel: i18n("classOn5e673bd") + (slot.scheduled_at) }}
          onClose={() => setEditWorkoutOpen(false)}
        />
      ) : null}
    </>
  );
}
