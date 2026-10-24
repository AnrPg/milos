"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  cancelBooking,
  joinWaitlist,
  sendSlotMessage,
  type ScheduleLocation,
  type ScheduleSlot,
  type WorkoutPreview,
} from "@/api/schedule";
import { GuestBookingPanel } from "@/components/schedule/GuestBookingPanel";
import {
  isEventSlot,
  localizeMemberBookingError,
  memberSlotState,
  slotCreditCost,
  slotLocationName,
  waitlistPositionLabel,
} from "@/components/schedule/member-booking";
import { MyInjuryWarningsPanel } from "@/components/wellbeing/InjuryWarnings";
import { WodGoalsStrip } from "@/components/wod-goals/WodGoalsStrip";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { downloadIcsEvent } from "@/lib/ics";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { dateKeyInZone, formatInZone, zonedText } from "@/lib/zoned-time";
import { YourTime } from "@/components/zoned-time";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/** The WOD as the sheet shows it (board 2, Q7): each part with its movement names. */
export function wodOutline(workout: WorkoutPreview) {
  return [...workout.sections]
    .sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
    .map((section) => ({
      id: section.id,
      name: section.name,
      movements: [...section.exercises].sort((a, b) => a.order - b.order).map((exercise) => exercise.name),
    }))
    .filter((section) => section.movements.length > 0 || section.name);
}

/**
 * Tapping a class in Πρόγραμμα (plan §5a decision 7): a bottom sheet with the
 * class facts on top, the WOD as movement names, and the one action the member
 * can take fixed at the bottom (board 2, Q5–Q8).
 */
export function ClassSheet({
  slot,
  timeZone = null,
  coachName,
  locations,
  accessToken,
  guestsIncluded,
  busy,
  error,
  onBook,
  onClose,
  onChanged,
  onCancelled,
}: {
  slot: ScheduleSlot;
  /** ADR-179: the gym's zone; the class shows on its clock. */
  timeZone?: string | null;
  coachName: string | null;
  locations: ScheduleLocation[];
  accessToken: string;
  guestsIncluded: boolean;
  busy: boolean;
  error: string | null;
  onBook: () => void;
  onClose: () => void;
  /** A waitlist or guest change; the sheet stays open. */
  onChanged: () => void;
  /** The member withdrew their booking; the sheet closes. */
  onCancelled: (result: { lateCancellation: boolean }) => void;
}) {
  const t = useTranslations("BoxSchedule");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const organizationSlug = useOrganizationSlug();
  const state = memberSlotState(slot);
  const [actionBusy, setActionBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [messageOpen, setMessageOpen] = useState(false);
  const [messageText, setMessageText] = useState("");
  const [messageState, setMessageState] = useState<"idle" | "sending" | "sent">("idle");
  const [messageError, setMessageError] = useState<string | null>(null);

  const start = new Date(slot.scheduled_at);
  const when = formatInZone(start, timeZone, locale, { weekday: "long", day: "numeric", month: "long" });
  const clock = { format: (at: Date) => zonedText(at, timeZone, locale, "time") };
  const location = slotLocationName(slot, locations);
  const credits = slotCreditCost(slot);
  const level = slot.class_type.level;
  const focus = slot.workout?.focus ?? [];
  const ownBooking = state.kind === "booked";
  const cancelUntil = slot.cancel_free_until ? new Date(slot.cancel_free_until) : null;
  const cancelUntilText = cancelUntil
    ? zonedText(cancelUntil, timeZone, locale, {
        weekday: dateKeyInZone(cancelUntil, timeZone) === dateKeyInZone(start, timeZone) ? undefined : "short",
        hour: "2-digit",
        minute: "2-digit",
      })
    : null;

  async function run(action: () => Promise<void>, kind: "waitlist" | "withdraw") {
    setActionBusy(true);
    setActionError(null);
    try {
      await action();
    } catch (err) {
      setActionError(
        kind === "withdraw" && err instanceof ApiError && err.status === 422
          ? i18n("thisBookingCanNoLongerBeCancelled0dbc8ac")
          : localizeMemberBookingError(err, i18n, locale, kind),
      );
    } finally {
      setActionBusy(false);
    }
  }

  function withdraw() {
    const booking = slot.current_user_booking;
    if (!booking || !window.confirm(i18n("cancelYourBookingForThisClass0c2112f"))) return;
    void run(async () => {
      onCancelled(await cancelBooking(accessToken, booking.id));
    }, "withdraw");
  }

  function leaveWaitlist() {
    const booking = slot.current_user_booking;
    if (!booking || !window.confirm(i18n("mbLeaveWaitlistConfirm"))) return;
    void run(async () => {
      await cancelBooking(accessToken, booking.id);
      onChanged();
    }, "waitlist");
  }

  function enterWaitlist() {
    void run(async () => {
      await joinWaitlist(accessToken, slot.id);
      onChanged();
    }, "waitlist");
  }

  async function sendMessage() {
    const text = messageText.trim();
    if (!text) return;
    setMessageState("sending");
    setMessageError(null);
    try {
      await sendSlotMessage(accessToken, slot.id, text);
      setMessageState("sent");
      setMessageText("");
    } catch (err) {
      setMessageState("idle");
      setMessageError(err instanceof Error ? localizeError(err, i18n) : i18n("failedToSendMessage0f22ccd"));
    }
  }

  const primary = "min-h-12 w-full rounded-2xl text-base font-bold disabled:opacity-50";
  const quiet = "min-h-12 w-full rounded-2xl text-sm font-bold disabled:opacity-50";
  let footer: ReactNode = null;
  if (state.kind === "bookable") {
    footer = (
      <button
        type="button"
        onClick={onBook}
        disabled={busy}
        className={primary}
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        {t("book")}
      </button>
    );
  } else if (state.kind === "waitlist_open") {
    footer = (
      <button
        type="button"
        onClick={enterWaitlist}
        disabled={actionBusy}
        className={primary}
        style={{ background: "var(--text)", color: "var(--bg)" }}
      >
        {i18n("mbJoinWaitlist")}
      </button>
    );
  } else if (state.kind === "booked") {
    footer = (
      <button
        type="button"
        onClick={withdraw}
        disabled={actionBusy}
        className={quiet}
        style={{
          background: "color-mix(in srgb, var(--danger) 10%, transparent)",
          border: "1px solid color-mix(in srgb, var(--danger) 28%, transparent)",
          color: "var(--danger)",
        }}
      >
        {actionBusy ? i18n("cancellingcee1848") : i18n("cancelBookingc6085eb")}
      </button>
    );
  } else if (state.kind === "waitlisted") {
    footer = (
      <button
        type="button"
        onClick={leaveWaitlist}
        disabled={actionBusy}
        className={quiet}
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
      >
        {i18n("mbLeaveWaitlist")}
      </button>
    );
  } else {
    footer = (
      <p className="py-3 text-center text-sm" style={{ color: "var(--dim)" }}>
        {state.kind === "past" ? i18n("thisClassHasAlreadyStarteda7aa12f") : i18n("bookingIsUnavailableForThisSlot8a07037")}
      </p>
    );
  }

  const shownError = error ?? actionError;

  return (
    <Dialog
      onClose={onClose}
      title={slot.name}
      titleId="class-sheet-title"
      description={
        <span className="block font-semibold first-letter:uppercase">
          {when} · {clock.format(start)} · {t("minutes", { count: slot.duration_minutes })}
          <YourTime at={start} zone={timeZone} format="day-time" />
        </span>
      }
      size="xl"
      headerActions={
        <button
          type="button"
          onClick={() =>
            downloadIcsEvent({
              title: slot.name,
              date: slot.scheduled_at.slice(0, 10),
              datetime: slot.scheduled_at,
              durationMinutes: slot.duration_minutes,
            })
          }
          aria-label={i18n("addToCalendar33cead7")}
          className="grid h-10 w-10 place-items-center rounded-full"
          style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }}
        >
          <span aria-hidden="true">📅</span>
        </button>
      }
      footer={
        <div className="flex w-full flex-col gap-2">
          {shownError ? (
            <ErrorNotice>{shownError}</ErrorNotice>
          ) : null}
          {footer}
        </div>
      }
    >
          <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
            {coachName ? <Fact label={t("coach")}>{coachName}</Fact> : null}
            {slot.friends_going && slot.friends_going.length > 0 ? (
              <Fact label={t("friendsLabel")}>{slot.friends_going.map((friend) => friend.nickname ?? "?").join(", ")}</Fact>
            ) : null}
            <Fact label={t("chipSpots")}>
              {slot.spots_remaining > 0 ? t("spotsLeft", { count: slot.spots_remaining }) : t("statusFull")}
            </Fact>
            {level ? <Fact label={t("chipLevel")}>{t(`level_${level}`)}</Fact> : null}
            {focus.length > 0 ? (
              <Fact label={t("focus")}>{focus.map((value) => t(`focus_${value}`)).join(" · ")}</Fact>
            ) : null}
            {slot.waitlist_count ? (
              <Fact label={t("waitlist")}>{i18n("mbWaitlistCount", { count: slot.waitlist_count })}</Fact>
            ) : null}
            {state.kind !== "past" ? (
              <Fact label={t("cancelTitle")}>
                {cancelUntilText ? t("cancelFreeUntil", { when: cancelUntilText }) : t("cancelAnytime")}
              </Fact>
            ) : null}
            {slot.covered_by_package !== undefined ? (
              <Fact label={t("package")} tone={slot.covered_by_package ? undefined : "var(--warning)"}>
                {slot.covered_by_package ? t("inPackage") : t("outsidePackage")}
              </Fact>
            ) : null}
            {credits ? <Fact label={t("cost")}>{i18n("mbUsesVisits", { count: credits })}</Fact> : null}
            {location ? <Fact label={t("location")}>{location}</Fact> : null}
          </dl>

          {isEventSlot(slot) || !slot.auto_approve ? (
            <div className="mt-3 flex flex-wrap gap-1.5">
              {isEventSlot(slot) ? <Tag>{i18n("mbEventMarker")}</Tag> : null}
              {slot.auto_approve ? null : <Tag tone="var(--warning)">{i18n("requiresApproval4ecb6f5")}</Tag>}
            </div>
          ) : null}

          {state.kind === "booked" ? (
            <Banner tone={state.status === "pending" ? "var(--warning)" : "var(--success)"}>
              <p className="font-bold">
                {state.status === "pending" ? i18n("waitingForCoachApproval123b28c") : i18n("youReConfirmed433ef6b")}
              </p>
              {state.status === "approved" && slot.current_user_booking?.admin_message ? (
                <p className="mt-1" style={{ color: "var(--text-soft)" }}>
                  {slot.current_user_booking.admin_message}
                </p>
              ) : null}
              {state.status === "approved" ? (
                <Link
                  href={adminHref(`/class-timer/${slot.id}/display`, organizationSlug)}
                  className="mt-2 inline-block text-sm font-bold underline underline-offset-4"
                >
                  {i18n("classTimerFollowLink")}
                </Link>
              ) : null}
            </Banner>
          ) : null}
          {state.kind === "waitlisted" ? (
            <Banner tone="var(--info)">
              <p className="font-bold">{waitlistPositionLabel(state.position, i18n)}</p>
              <p className="mt-1" style={{ color: "var(--text-soft)" }}>
                {i18n("mbWaitlistExplainer")}
              </p>
            </Banner>
          ) : null}

          <section className="mt-5">
            <h3 className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
              {t("wod")}
            </h3>
            {slot.my_version ? (
              <p className="mt-2 text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>
                {i18n("memberProgrammingYourVersion")}: {slot.my_version.workout.title}
              </p>
            ) : null}
            {slot.workout ? <WodOutline workout={slot.workout} /> : (
              <p className="mt-2 text-sm" style={{ color: "var(--dim)" }}>
                {t("wodNotPosted")}
              </p>
            )}
            {slot.workout ? <WodGoalsStrip workoutId={slot.workout.id} className="mt-3" /> : null}
          </section>

          {slot.workout && ownBooking ? (
            <div className="mt-4">
              <MyInjuryWarningsPanel
                accessToken={accessToken}
                workoutId={slot.workout.id}
                surface="class_detail"
                sourceContextId={slot.id}
              />
            </div>
          ) : null}

          <GuestBookingPanel accessToken={accessToken} guestsIncluded={guestsIncluded} onChanged={onChanged} slot={slot} />

          <section className="mt-5">
            {messageState === "sent" ? (
              <p className="text-sm font-semibold" style={{ color: "var(--success)" }}>
                ✓ {i18n("messageSent9cf1b68")}
              </p>
            ) : messageOpen ? (
              <div className="flex flex-col gap-2">
                <textarea
                  value={messageText}
                  onChange={(event) => setMessageText(event.target.value)}
                  maxLength={1000}
                  rows={3}
                  aria-label={i18n("messageYourCoachc0c790e")}
                  placeholder={i18n("typeYourMessage6733d4f")}
                  className="w-full resize-none rounded-2xl p-3 text-sm outline-none"
                  style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
                />
                {messageError ? (
                  <ErrorNotice variant="field">{messageError}</ErrorNotice>
                ) : null}
                <button
                  type="button"
                  onClick={() => void sendMessage()}
                  disabled={messageState === "sending" || !messageText.trim()}
                  className="min-h-10 self-end rounded-full px-5 text-sm font-bold disabled:opacity-40"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                >
                  {i18n("send9bc2575")}
                </button>
              </div>
            ) : (
              <button
                type="button"
                onClick={() => setMessageOpen(true)}
                className="text-sm font-semibold underline-offset-4 hover:underline"
                style={{ color: "var(--text-soft)" }}
              >
                {i18n("messageYourCoachc0c790e")}
              </button>
            )}
          </section>
    </Dialog>
  );
}

function Fact({ label, tone, children }: { label: string; tone?: string; children: ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="text-[11px] font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
        {label}
      </dt>
      <dd className="mt-0.5 font-semibold" style={{ color: tone ?? "var(--text)" }}>
        {children}
      </dd>
    </div>
  );
}

function Tag({ tone, children }: { tone?: string; children: ReactNode }) {
  const color = tone ?? "var(--primary-strong)";
  return (
    <span
      className="rounded-full px-2.5 py-0.5 text-xs font-bold"
      style={{ background: `color-mix(in srgb, ${color} 14%, transparent)`, color }}
    >
      {children}
    </span>
  );
}

function Banner({ tone, children }: { tone: string; children: ReactNode }) {
  return (
    <div
      className="mt-4 rounded-2xl px-4 py-3 text-sm"
      style={{
        background: `color-mix(in srgb, ${tone} 12%, transparent)`,
        border: `1px solid color-mix(in srgb, ${tone} 30%, transparent)`,
        color: tone,
      }}
    >
      {children}
    </div>
  );
}

function WodOutline({ workout }: { workout: WorkoutPreview }) {
  const outline = wodOutline(workout);
  if (outline.length === 0) {
    const text = workout.free_text_body?.trim();
    return text ? (
      <p className="mt-2 whitespace-pre-line text-sm" style={{ color: "var(--text)" }}>
        {text}
      </p>
    ) : null;
  }
  return (
    <ol className="mt-2 flex flex-col gap-2.5">
      {outline.map((section) => (
        <li key={section.id}>
          {section.name ? (
            <p className="text-sm font-bold" style={{ color: "var(--text)" }}>
              {section.name}
            </p>
          ) : null}
          {section.movements.length > 0 ? (
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>
              {section.movements.join(" · ")}
            </p>
          ) : null}
        </li>
      ))}
    </ol>
  );
}
