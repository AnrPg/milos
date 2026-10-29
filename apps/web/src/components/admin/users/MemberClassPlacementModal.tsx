"use client";

import { useEffect, useState } from "react";

import { fetchClassPlacementOptions, placeAdminUserInClass, type ClassPlacementOptions } from "@/api/admin-users";
import { ApiError } from "@/api/client";
import { localizeAdminAssignmentError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { zonedText } from "@/lib/zoned-time";
import { Dialog } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { placementBlocked, placementReasonKey } from "@/components/admin/users/class-placement";

type Props = {
  token: string;
  userId: string;
  nickname: string;
  onClose: () => void;
  onPlaced: () => void;
};

/**
 * ADR-232: staff book a member into a class, or move one of their upcoming
 * bookings to another class. The API lists what can be chosen and why a
 * class cannot take the member; times read on the box's clock (ADR-179).
 */
export function MemberClassPlacementModal({ token, userId, nickname, onClose, onPlaced }: Props) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const [options, setOptions] = useState<ClassPlacementOptions | null>(null);
  const [fromBookingId, setFromBookingId] = useState("");
  const [targetSlotId, setTargetSlotId] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const loading = options === null && error === null;
  const moving = fromBookingId !== "";

  useEffect(() => {
    let cancelled = false;
    fetchClassPlacementOptions(token, userId)
      .then((result) => {
        if (!cancelled) setOptions(result);
      })
      .catch((reason) => {
        if (!cancelled) setError(localizeAdminAssignmentError(reason, i18n));
      });
    return () => {
      cancelled = true;
    };
  }, [i18n, token, userId]);

  const when = (at: string) => zonedText(at, options?.timezone, locale, "day-time");
  const reason = (code: string | null | undefined) => {
    const key = placementReasonKey(code);
    return key ? i18n(key) : null;
  };
  const classes = options?.classes ?? [];
  const target = classes.find((option) => option.slot_id === targetSlotId) ?? null;

  function chooseFrom(bookingId: string) {
    setFromBookingId(bookingId);
    // A class that a move could take may not take a new booking.
    if (target && placementBlocked(target, bookingId !== "")) setTargetSlotId("");
  }

  async function submit() {
    if (!targetSlotId) return;
    setSaving(true);
    setError(null);
    try {
      await placeAdminUserInClass(token, userId, { slot_id: targetSlotId, from_booking_id: fromBookingId || null });
      onPlaced();
      onClose();
    } catch (failure) {
      const key = placementReasonKey(failure instanceof ApiError ? failure.payload.code : null);
      setError(key && key !== "placementReasonOther" ? i18n("placementRefused", { reason: i18n(key) }) : localizeAdminAssignmentError(failure, i18n));
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
            {saving ? i18n("featureMovePlacing") : moving ? i18n("placementConfirmMove") : i18n("featureConfirmMove")}
          </button>
        </>
      }
    >
        <label className="block text-sm font-semibold" style={{ color: "var(--muted)" }}>
          {i18n("featureMoveFromBooking")}
          <Select className="mt-2 w-full rounded-xl px-3 py-2 text-sm" style={fieldStyle} value={fromBookingId} disabled={loading} onValueChange={chooseFrom} data-testid="placement-from">
            <option value="">{i18n("featureNoCurrentBooking")}</option>
            {(options?.bookings ?? []).map((booking) => (
              <option key={booking.booking_id} value={booking.booking_id}>
                {when(booking.scheduled_at)} · {booking.name}
                {booking.status === "pending" ? ` · ${i18n("placementPendingBooking")}` : ""}
              </option>
            ))}
          </Select>
        </label>

        <label className="mt-4 block text-sm font-semibold" style={{ color: "var(--muted)" }}>
          {i18n("featureTargetClass")}
          <Select className="mt-2 w-full rounded-xl px-3 py-2 text-sm" style={fieldStyle} value={targetSlotId} disabled={loading} onValueChange={(value) => setTargetSlotId(value)} data-testid="placement-target">
            <option value="">{i18n("placementChooseClass")}</option>
            {classes.map((option) => {
              const blocked = placementBlocked(option, moving);
              const detail = blocked ? reason(option.blocked_reason) : i18n("featureSpotsLeft", { count: option.spots_remaining });
              return (
                <option key={option.slot_id} value={option.slot_id} disabled={blocked}>
                  {when(option.scheduled_at)} · {option.name} · {detail}
                </option>
              );
            })}
          </Select>
        </label>

        {moving ? (
          <p className="mt-3 text-sm" style={{ color: "var(--dim)" }}>{i18n("placementMoveNote")}</p>
        ) : null}
        {!loading && options && classes.length === 0 ? (
          <p className="mt-3 text-sm" style={{ color: "var(--dim)" }}>{i18n("featureNoUpcomingClasses", { days: options.lookahead_days })}</p>
        ) : null}
        {error ? <ErrorNotice className="mt-3">{error}</ErrorNotice> : null}

    </Dialog>
  );
}
