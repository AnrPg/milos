"use client";

import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  bookAppointment,
  bookingSlot,
  cancelAppointment,
  fetchMyAppointments,
  fetchOfferedSlots,
  type AppointmentBooking,
  type OfferedSlot,
} from "@/api/appointments";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { groupSlotsByDay, isLateCancellation, splitAppointments } from "@/components/client/appointments";
import { ClientCard, ClientPage, EmptyLine, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { allowanceRemaining, cancellationCutoffHours, hasCapability } from "@/components/client/entitlement";
import { clientErrorMessage } from "@/components/client/errors";
import { FeatureGate } from "@/components/client/FeatureGate";
import { formatDay, formatTime } from "@/components/client/format";
import { CLIENT_ENTITLEMENT_QUERY_KEY, useClientEntitlement } from "@/components/client/use-client-entitlement";
import { entryDay } from "@/components/client/vault";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";
import { useOrganizationTimeZone } from "@/lib/organization-slug";
import { YourTime } from "@/components/zoned-time";

const SLOTS_KEY = ["me", "appointments", "slots"] as const;
const MINE_KEY = ["me", "appointments", "mine"] as const;

type Translate = ReturnType<typeof useUiTranslations>;

/** Slot kind, or the booking's allowance when the slot is missing. */
function kindLabel(kind: string | undefined, i18n: Translate) {
  if (kind === "assessment" || kind === "assessments") return i18n("clApptKindAssessment");
  if (kind === "pt_session" || kind === "pt_sessions") return i18n("clApptKindPtSession");
  return "";
}

function formatLabel(format: string | undefined, i18n: Translate) {
  if (format === "semi_private") return i18n("clApptFormatSemiPrivate");
  if (format === "one_to_one") return i18n("clApptFormatOneToOne");
  return "";
}

/** `/box/appointments`: book PT sessions and assessments (ADR-098). */
export function AppointmentsConsole() {
  const i18n = useUiTranslations();
  return (
    <ClientPage title={i18n("clAppointmentsTitle")} intro={i18n("clAppointmentsIntro")}>
      <FeatureGate feature="appointments">
        <AppointmentsContent />
      </FeatureGate>
    </ClientPage>
  );
}

function AppointmentsContent() {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const { entitlement } = useClientEntitlement();
  const cutoffHours = cancellationCutoffHours(entitlement);
  const allowances = [
    hasCapability(entitlement, "book_pt_sessions")
      ? { key: "pt", label: i18n("clApptRemainingPt"), value: allowanceRemaining(entitlement, "pt_sessions") }
      : null,
    hasCapability(entitlement, "book_assessments")
      ? { key: "assessment", label: i18n("clApptRemainingAssessments"), value: allowanceRemaining(entitlement, "assessments") }
      : null,
  ].filter((item) => item?.value != null);

  const refresh = () => {
    void queryClient.invalidateQueries({ queryKey: SLOTS_KEY });
    void queryClient.invalidateQueries({ queryKey: MINE_KEY });
    void queryClient.invalidateQueries({ queryKey: CLIENT_ENTITLEMENT_QUERY_KEY });
  };
  const slots = useQuery({
    queryKey: SLOTS_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchOfferedSlots(tokens!.access_token),
  });
  const mine = useQuery({
    queryKey: MINE_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchMyAppointments(tokens!.access_token),
  });
  const book = useMutation({
    mutationFn: (slotId: string) => bookAppointment(tokens!.access_token, slotId),
    onSuccess: refresh,
  });
  const cancel = useMutation({
    mutationFn: (id: string) => cancelAppointment(tokens!.access_token, id),
    onSuccess: refresh,
  });

  return (
    <div className="flex flex-col gap-4">
      {allowances.length > 0 ? (
        <div className="flex flex-wrap gap-2">
          {allowances.map((item) =>
            item ? (
              <span key={item.key} className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
                {item.label}{" "}
                <strong style={{ color: "var(--text)" }}>
                  {item.value?.remaining === "unlimited" ? i18n("clUnlimited") : String(item.value?.remaining)}
                </strong>
              </span>
            ) : null,
          )}
        </div>
      ) : null}

      <p className="text-sm" style={{ color: "var(--muted)" }}>
        {cutoffHours ? i18n("clApptCutoffInfo", { hours: cutoffHours }) : i18n("clApptCutoffGeneric")}
      </p>

      <ClientCard title={i18n("clApptMine")}>
        {cancel.isError ? (
          <p role="alert" className="mb-2 text-sm" style={{ color: "var(--danger)" }}>
            {clientErrorMessage(cancel.error, i18n)}
          </p>
        ) : null}
        {mine.isPending ? (
          <LoadingLine />
        ) : mine.isError ? (
          <QueryProblem error={mine.error} onRetry={() => void mine.refetch()} />
        ) : (
          <MyAppointments
            bookings={mine.data}
            cutoffHours={cutoffHours}
            cancellingId={cancel.isPending ? (cancel.variables ?? null) : null}
            onCancel={(id) => cancel.mutate(id)}
          />
        )}
      </ClientCard>

      <ClientCard title={i18n("clApptAvailable")}>
        {book.isError ? (
          <p role="alert" className="mb-2 text-sm" style={{ color: "var(--danger)" }}>
            {clientErrorMessage(book.error, i18n)}
          </p>
        ) : null}
        {slots.isPending ? (
          <LoadingLine />
        ) : slots.isError ? (
          <QueryProblem error={slots.error} onRetry={() => void slots.refetch()} />
        ) : (
          <OfferedSlots
            slots={slots.data}
            bookingId={book.isPending ? (book.variables ?? null) : null}
            onBook={(id) => book.mutate(id)}
          />
        )}
      </ClientCard>
    </div>
  );
}

function OfferedSlots({
  slots,
  bookingId,
  onBook,
}: {
  slots: OfferedSlot[];
  bookingId: string | null;
  onBook: (slotId: string) => void;
}) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  // ADR-179: the practice's days and clock, wherever the client is.
  const zone = useOrganizationTimeZone();
  const days = useMemo(() => groupSlotsByDay(slots, zone ?? undefined), [slots, zone]);
  if (days.length === 0) return <EmptyLine>{i18n("clApptNoSlots")}</EmptyLine>;

  return (
    <ol className="flex flex-col gap-4">
      {days.map((day) => (
        <li key={day.day}>
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            <time dateTime={day.day}>{formatDay(day.day, locale)}</time>
          </h3>
          <ul className="flex flex-col gap-2">
            {day.slots.map((slot) => (
              <li
                key={slot.id}
                className="flex flex-col gap-2 rounded-xl p-3 sm:flex-row sm:items-center sm:justify-between"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
              >
                <div className="min-w-0">
                  <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                    <time dateTime={slot.starts_at}>{formatTime(slot.starts_at, locale, zone)}</time>
                    {" · "}
                    {kindLabel(slot.kind, i18n)}
                  </p>
                  <p className="mt-0.5 flex flex-wrap gap-x-2 text-xs" style={{ color: "var(--dim)" }}>
                    <span>{formatLabel(slot.format, i18n)}</span>
                    <span>{i18n("clMinutesShort", { count: slot.duration_minutes })}</span>
                    {slot.coach_nickname ? <span>{i18n("clApptWithCoach", { coach: slot.coach_nickname })}</span> : null}
                    {typeof slot.spots_remaining === "number" && slot.format === "semi_private" ? (
                      <span>{i18n("clApptSpotsLeft", { count: slot.spots_remaining })}</span>
                    ) : null}
                  </p>
                  {slot.notes ? (
                    <p className="mt-1 break-words text-xs" style={{ color: "var(--muted)" }}>{slot.notes}</p>
                  ) : null}
                </div>
                {slot.booked_by_me ? (
                  <span className="self-start rounded-full px-3 py-1 text-xs font-semibold sm:self-auto" style={{ background: "color-mix(in srgb, var(--success) 14%, transparent)", color: "var(--success)" }}>
                    {i18n("clApptBooked")}
                  </span>
                ) : (
                  <button
                    type="button"
                    onClick={() => onBook(slot.id)}
                    disabled={Boolean(bookingId) || (slot.spots_remaining ?? 1) <= 0}
                    className="self-start rounded-full px-4 py-1.5 text-sm font-semibold disabled:opacity-50 sm:self-auto"
                    style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                  >
                    {bookingId === slot.id ? i18n("clApptBooking") : i18n("clApptBook")}
                  </button>
                )}
              </li>
            ))}
          </ul>
        </li>
      ))}
    </ol>
  );
}

function MyAppointments({
  bookings,
  cutoffHours,
  cancellingId,
  onCancel,
}: {
  bookings: AppointmentBooking[];
  cutoffHours: number | null;
  cancellingId: string | null;
  onCancel: (id: string) => void;
}) {
  const i18n = useUiTranslations();
  const [showPast, setShowPast] = useState(false);
  // Evaluated per render so the split follows the clock.
  const { upcoming, past } = splitAppointments(bookings, new Date());

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h3 className="mb-2 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {i18n("semanticUpcoming")}
        </h3>
        {upcoming.length === 0 ? (
          <EmptyLine>{i18n("clApptNoUpcoming")}</EmptyLine>
        ) : (
          <ul className="flex flex-col gap-2">
            {upcoming.map((booking) => (
              <AppointmentItem
                key={booking.id}
                booking={booking}
                cutoffHours={cutoffHours}
                cancelling={cancellingId === booking.id}
                onCancel={() => onCancel(booking.id)}
              />
            ))}
          </ul>
        )}
      </div>
      {past.length > 0 ? (
        <div>
          <button
            type="button"
            aria-expanded={showPast}
            onClick={() => setShowPast((value) => !value)}
            className="text-xs font-semibold uppercase tracking-[0.18em]"
            style={{ color: "var(--primary)" }}
          >
            {showPast ? i18n("clApptHidePast") : i18n("clApptShowPast", { count: past.length })}
          </button>
          {showPast ? (
            <ul className="mt-2 flex flex-col gap-2">
              {past.map((booking) => (
                <AppointmentItem key={booking.id} booking={booking} cutoffHours={cutoffHours} />
              ))}
            </ul>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

function AppointmentItem({
  booking,
  cutoffHours,
  cancelling = false,
  onCancel,
}: {
  booking: AppointmentBooking;
  cutoffHours: number | null;
  cancelling?: boolean;
  onCancel?: () => void;
}) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const zone = useOrganizationTimeZone();
  const [confirming, setConfirming] = useState(false);
  const slot = bookingSlot(booking);
  const startsAt = slot?.starts_at ?? null;
  const late = confirming ? isLateCancellation(startsAt, cutoffHours, new Date()) : null;

  return (
    <li className="rounded-xl p-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {startsAt ? (
              <>
              <time dateTime={startsAt}>
                {formatDay(entryDay(startsAt, zone), locale, { weekday: "short", month: "short" })} · {formatTime(startsAt, locale, zone)}
              </time>
              <YourTime at={startsAt} zone={zone} format="day-time" />
              </>
            ) : null}
          </p>
          <p className="mt-0.5 flex flex-wrap gap-x-2 text-xs" style={{ color: "var(--dim)" }}>
            <span>{kindLabel(slot?.kind ?? booking.allowance, i18n)}</span>
            {slot?.format ? <span>{formatLabel(slot.format, i18n)}</span> : null}
            {slot?.duration_minutes ? <span>{i18n("clMinutesShort", { count: slot.duration_minutes })}</span> : null}
            {slot?.coach_nickname ? <span>{i18n("clApptWithCoach", { coach: slot.coach_nickname })}</span> : null}
          </p>
        </div>
        <span className="rounded-full px-2 py-0.5 text-[11px] font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }}>
          {booking.status === "booked" ? i18n("clApptBooked") : booking.late_cancellation ? i18n("clApptLateCancelled") : <SemanticLabel value={booking.status} />}
        </span>
      </div>

      {onCancel && booking.status === "booked" ? (
        confirming ? (
          <div className="mt-3 rounded-lg p-3" role="alertdialog" aria-label={i18n("clApptCancelConfirm")} style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("clApptCancelConfirm")}</p>
            <p className="mt-1 text-xs" style={{ color: late ? "var(--warning)" : "var(--muted)" }}>
              {late && cutoffHours
                ? i18n("clApptLateWarning", { hours: cutoffHours })
                : late === false
                  ? i18n("clApptFreeCancel")
                  : i18n("clApptCutoffGeneric")}
            </p>
            <div className="mt-2 flex flex-wrap gap-2">
              <button
                type="button"
                onClick={() => {
                  onCancel();
                  setConfirming(false);
                }}
                disabled={cancelling}
                className="rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50"
                style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
              >
                {i18n("clApptConfirmCancel")}
              </button>
              <button
                type="button"
                onClick={() => setConfirming(false)}
                className="rounded-full px-3 py-1 text-xs font-semibold"
                style={{ background: "var(--border)", color: "var(--text)" }}
              >
                {i18n("clApptKeep")}
              </button>
            </div>
          </div>
        ) : (
          <button
            type="button"
            onClick={() => setConfirming(true)}
            disabled={cancelling}
            className="mt-2 rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50"
            style={{ border: "1px solid var(--border)", color: "var(--danger)" }}
          >
            {cancelling ? i18n("clCancelling") : i18n("clApptCancel")}
          </button>
        )
      ) : null}
    </li>
  );
}
