"use client";

import { useState } from "react";
import { useLocale, useTranslations } from "next-intl";

import { cancelBooking, createGuestBooking, type ScheduleSlot } from "@/api/schedule";
import { SemanticLabel } from "@/components/semantic-label";
import { canBringGuest, localizeMemberBookingError } from "@/components/schedule/member-booking";
import { useUiTranslations } from "@/i18n/ui";

const GUEST_NAME_MAX_LENGTH = 80;

/** Member's guest for a class on their guest passes (ADR-097): add, view, remove. */
export function GuestBookingPanel({
  slot,
  accessToken,
  guestsIncluded,
  onChanged,
}: {
  slot: ScheduleSlot;
  accessToken: string;
  guestsIncluded: boolean;
  onChanged: () => void;
}) {
  const i18n = useUiTranslations();
  const common = useTranslations("Common");
  const locale = useLocale();
  const [formOpen, setFormOpen] = useState(false);
  const [guestName, setGuestName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const guest = slot.current_user_guest;
  const isPast = new Date(slot.scheduled_at) <= new Date();

  if (!guest && !notice && !canBringGuest(slot, guestsIncluded)) return null;

  async function handleAdd() {
    const name = guestName.trim();
    if (name.length < 2) {
      setError(i18n("mbErrInvalidGuestName"));
      return;
    }
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      await createGuestBooking(accessToken, slot.id, name);
      setGuestName("");
      setFormOpen(false);
      onChanged();
    } catch (err) {
      setError(localizeMemberBookingError(err, i18n, locale, "guest"));
    } finally {
      setBusy(false);
    }
  }

  async function handleRemove() {
    if (!guest) return;
    if (!window.confirm(i18n("mbRemoveGuestConfirm", { name: guest.guest_name ?? "" }))) return;
    setBusy(true);
    setError(null);
    try {
      const result = await cancelBooking(accessToken, guest.id);
      if (result.lateCancellation) setNotice(i18n("mbGuestLateCancellationNotice"));
      onChanged();
    } catch (err) {
      setError(localizeMemberBookingError(err, i18n, locale, "withdraw"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div
      className="mt-3 rounded-[1.4rem] px-5 py-3 text-sm"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      {guest ? (
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="font-semibold" style={{ color: "var(--text)" }}>
              {i18n("mbGuestLabel", { name: guest.guest_name ?? "" })}
            </p>
            <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
              <SemanticLabel value={guest.status} />
            </p>
          </div>
          {!isPast && (guest.status === "pending" || guest.status === "approved" || guest.status === "waitlisted") ? (
            <button
              className="rounded-full px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
              style={{ background: "var(--card)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
              disabled={busy}
              onClick={() => void handleRemove()}
              type="button"
            >
              {i18n("mbRemoveGuest")}
            </button>
          ) : null}
        </div>
      ) : formOpen ? (
        <div className="space-y-2">
          <label className="block text-xs font-semibold" style={{ color: "var(--muted)" }}>
            {i18n("mbGuestNameLabel")}
            <input
              autoFocus
              className="mt-1 w-full rounded-xl px-3 py-2 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              maxLength={GUEST_NAME_MAX_LENGTH}
              onChange={(event) => setGuestName(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") {
                  event.preventDefault();
                  void handleAdd();
                }
              }}
              placeholder={i18n("mbGuestNamePlaceholder")}
              value={guestName}
            />
          </label>
          <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("mbGuestPassHint")}</p>
          <div className="flex gap-2">
            <button
              className="rounded-full px-4 py-1.5 text-xs font-semibold disabled:opacity-50"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              disabled={busy || guestName.trim().length < 2}
              onClick={() => void handleAdd()}
              type="button"
            >
              {i18n("mbAddGuest")}
            </button>
            <button
              className="rounded-full px-4 py-1.5 text-xs font-semibold"
              style={{ background: "var(--card)", color: "var(--text-soft)" }}
              onClick={() => {
                setFormOpen(false);
                setError(null);
              }}
              type="button"
            >
              {common("cancel")}
            </button>
          </div>
        </div>
      ) : canBringGuest(slot, guestsIncluded) ? (
        <button
          className="text-xs font-semibold"
          style={{ color: "var(--primary-strong)" }}
          onClick={() => {
            setFormOpen(true);
            setNotice(null);
          }}
          type="button"
        >
          {i18n("mbBringGuest")}
        </button>
      ) : null}
      {notice ? <p className="mt-2 text-xs" style={{ color: "var(--muted)" }}>{notice}</p> : null}
      {error ? <p className="mt-2 text-xs" style={{ color: "var(--danger)" }}>{error}</p> : null}
    </div>
  );
}
