"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { checkInToClass, type ScheduleSlot } from "@/api/schedule";
import { clientErrorMessage } from "@/components/client/errors";
import { bookingCheckIn } from "@/components/member-app/box/today-training";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

/**
 * The next booking's check-in and live class timer (TD-105): «Check-in»
 * from 30 minutes before the class until it ends, «Checked in ✓» after, and
 * the class's live timer while it runs.
 */
export function NextBookingActions({ slot }: { slot: ScheduleSlot }) {
  const t = useTranslations("MemberApp");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const organizationSlug = useOrganizationSlug();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const now = useMinuteClock();
  const state = bookingCheckIn(slot, now);
  const booking = slot.current_user_booking;

  async function checkIn() {
    if (!tokens?.access_token || !booking) return;
    setPending(true);
    setError(null);
    try {
      await checkInToClass(tokens.access_token, booking.id);
      await queryClient.invalidateQueries({ queryKey: ["box", "schedule"] });
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
    } finally {
      setPending(false);
    }
  }

  if (!state.checkedIn && !state.canCheckIn && !state.live) return null;

  return (
    <div className="flex flex-col gap-2">
      <div className="flex gap-2">
        {state.checkedIn ? (
          <span
            className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
            style={{ color: "var(--success)", border: "1px solid var(--success)" }}
          >
            {t("checkedIn")}
          </span>
        ) : state.canCheckIn ? (
          <button
            type="button"
            onClick={() => void checkIn()}
            disabled={pending}
            className="min-h-11 flex-1 rounded-2xl px-4 text-sm font-bold disabled:opacity-60"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {pending ? t("checkingIn") : t("classCheckIn")}
          </button>
        ) : null}
        {state.live ? (
          <Link
            href={adminHref(`/class-timer/${slot.id}/display`, organizationSlug)}
            className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
            style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
          >
            {t("followClassTimer")}
          </Link>
        ) : null}
      </div>
      {error ? <p role="alert" className="text-xs" style={{ color: "var(--danger)" }}>{error}</p> : null}
    </div>
  );
}

/** The current time, refreshed every 30 seconds so the window opens and closes on its own. */
function useMinuteClock() {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 30_000);
    return () => window.clearInterval(timer);
  }, []);
  return now;
}
