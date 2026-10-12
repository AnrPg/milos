"use client";

import type { ScheduleBooking, ScheduleSlot } from "@/api/schedule";
import { splitRoster } from "@/components/schedule/admin-roster";
import { SemanticLabel } from "@/components/semantic-label";
import { useUiTranslations } from "@/i18n/ui";

/** Admin class roster: booked members (guests marked with their host), then the waitlist in offer order. */
export function AdminSlotRoster({
  slot,
  onApproveBooking,
  onRejectBooking,
}: {
  slot: ScheduleSlot;
  onApproveBooking: (booking: ScheduleBooking) => void;
  onRejectBooking: (booking: ScheduleBooking) => void;
}) {
  const i18n = useUiTranslations();
  const { booked, waitlist } = splitRoster(slot.bookings);

  const personLabel = (booking: ScheduleBooking) => {
    const member = booking.user_nickname ?? booking.user_id;
    return booking.guest_name ? i18n("admRosterGuest", { name: booking.guest_name, member }) : member;
  };

  return (
    <section
      className="mt-8 rounded-[1.8rem] p-5"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <h3 className="text-lg font-semibold" style={{ color: "var(--text)" }}>
        {i18n("bookings135229c")}
      </h3>
      <div className="mt-4 space-y-3">
        {booked.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>
            {i18n("noBookingsYetdb81e7a")}
          </p>
        ) : null}
        {booked.map((booking) => (
          <div
            className="rounded-[1.2rem] p-4"
            style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            key={booking.id}
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {personLabel(booking)}
                </p>
                <p className="mt-1 text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
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

      {waitlist.length > 0 ? (
        <div className="mt-6">
          <h4 className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {i18n("admRosterWaitlist", { count: waitlist.length })}
          </h4>
          <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{i18n("admRosterWaitlistHint")}</p>
          <ol className="mt-3 space-y-2">
            {waitlist.map((booking, index) => (
              <li
                className="flex items-center gap-3 rounded-[1.2rem] px-4 py-3 text-sm"
                key={booking.id}
                style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
              >
                <span className="w-5 text-center font-semibold tabular-nums" style={{ color: "var(--dim)" }}>{index + 1}</span>
                <span className="min-w-0 flex-1 truncate font-semibold" style={{ color: "var(--text)" }}>{personLabel(booking)}</span>
                {(booking.waitlist_priority ?? 0) > 0 ? (
                  <span
                    className="rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider"
                    style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)" }}
                  >
                    {i18n("admRosterPriority")}
                  </span>
                ) : null}
              </li>
            ))}
          </ol>
        </div>
      ) : null}
    </section>
  );
}
