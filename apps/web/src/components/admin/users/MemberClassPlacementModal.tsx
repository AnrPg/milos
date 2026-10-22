"use client";

import { useEffect, useMemo, useState } from "react";

import { fetchAdminUserSchedule, placeAdminUserInClass } from "@/api/admin-users";
import { fetchSchedule, type ScheduleSlot } from "@/api/schedule";
import { localizeAdminAssignmentError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { Dialog } from "@/components/ui/Dialog";

type Props = {
  token: string;
  userId: string;
  nickname: string;
  onClose: () => void;
  onPlaced: () => void;
};

type MemberBooking = { bookingId: string; slotId: string; label: string };

const LOOKAHEAD_DAYS = 30;

function isoDate(date: Date) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 10);
}

function slotLabel(name: string, scheduledAt: string) {
  const when = new Intl.DateTimeFormat(undefined, { weekday: "short", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(new Date(scheduledAt));
  return `${when} · ${name}`;
}

export function MemberClassPlacementModal({ token, userId, nickname, onClose, onPlaced }: Props) {
  const i18n = useUiTranslations();
  const [bookings, setBookings] = useState<MemberBooking[]>([]);
  const [slots, setSlots] = useState<ScheduleSlot[]>([]);
  const [fromBookingId, setFromBookingId] = useState("");
  const [targetSlotId, setTargetSlotId] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const start = new Date();
    const end = new Date();
    end.setDate(end.getDate() + LOOKAHEAD_DAYS);

    void Promise.all([
      fetchAdminUserSchedule(token, userId, isoDate(start), isoDate(end)),
      fetchSchedule(token, { startAt: start.toISOString(), endAt: end.toISOString(), days: LOOKAHEAD_DAYS, classTypeIds: [] }),
    ])
      .then(([memberSchedule, window]) => {
        if (cancelled) return;
        const now = Date.now();
        setBookings(memberSchedule.items.flatMap((item) => {
          const booking = item.user_booking as { id?: unknown } | undefined;
          const scheduledAt = typeof item.scheduled_at === "string" ? item.scheduled_at : "";
          if (typeof booking?.id !== "string" || typeof item.id !== "string" || !scheduledAt || new Date(scheduledAt).getTime() <= now) return [];
          return [{ bookingId: booking.id, slotId: item.id, label: slotLabel(String(item.name ?? ""), scheduledAt) }];
        }));
        setSlots((window.slots ?? []).filter((slot) => new Date(slot.scheduled_at).getTime() > now));
      })
      .catch((reason) => {
        if (!cancelled) setError(localizeAdminAssignmentError(reason, i18n));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [i18n, token, userId]);

  useEffect(() => {
    function handleKey(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [onClose]);

  const bookedSlotIds = useMemo(() => new Set(bookings.map((booking) => booking.slotId)), [bookings]);
  const targetSlots = slots.filter((slot) => !bookedSlotIds.has(slot.id));

  async function submit() {
    if (!targetSlotId) return;
    setSaving(true);
    setError(null);
    try {
      await placeAdminUserInClass(token, userId, { slot_id: targetSlotId, from_booking_id: fromBookingId || null });
      onPlaced();
      onClose();
    } catch (reason) {
      setError(localizeAdminAssignmentError(reason, i18n));
    } finally {
      setSaving(false);
    }
  }

  const fieldStyle = { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" };

  return (
    <Dialog
      onClose={onClose}
      eyebrow={i18n("featureMoveToClassAction")}
      title={<span className="block truncate">{nickname}</span>}
      titleId="member-class-placement-title"
      size="lg"
      variant="center"
      onSubmit={(event) => {
        event.preventDefault();
        void submit();
      }}
      footer={
        <>
          <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }} onClick={onClose}>
            {i18n("cancel77dfd21")}
          </button>
          <button type="submit" disabled={!targetSlotId || saving || loading} className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
            {saving ? i18n("featureMovePlacing") : i18n("featureConfirmMove")}
          </button>
        </>
      }
    >
        <label className="block text-sm font-semibold" style={{ color: "var(--muted)" }}>
          {i18n("featureMoveFromBooking")}
          <select className="mt-2 w-full rounded-xl px-3 py-2 text-sm" style={fieldStyle} value={fromBookingId} disabled={loading} onChange={(event) => setFromBookingId(event.target.value)}>
            <option value="">{i18n("featureNoCurrentBooking")}</option>
            {bookings.map((booking) => <option key={booking.bookingId} value={booking.bookingId}>{booking.label}</option>)}
          </select>
        </label>

        <label className="mt-4 block text-sm font-semibold" style={{ color: "var(--muted)" }}>
          {i18n("featureTargetClass")}
          <select className="mt-2 w-full rounded-xl px-3 py-2 text-sm" style={fieldStyle} value={targetSlotId} disabled={loading} onChange={(event) => setTargetSlotId(event.target.value)}>
            <option value="">{i18n("featureChooseClass")}</option>
            {targetSlots.map((slot) => (
              <option key={slot.id} value={slot.id} disabled={slot.spots_remaining <= 0}>
                {slotLabel(slot.name, slot.scheduled_at)} · {i18n("featureSpotsLeft", { count: Math.max(slot.spots_remaining, 0) })}
              </option>
            ))}
          </select>
        </label>

        {!loading && targetSlots.length === 0 ? (
          <p className="mt-3 text-sm" style={{ color: "var(--dim)" }}>{i18n("featureNoUpcomingClasses")}</p>
        ) : null}
        {error ? <p className="mt-3 text-sm" style={{ color: "var(--danger)" }}>{error}</p> : null}

    </Dialog>
  );
}
