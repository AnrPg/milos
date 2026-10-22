"use client";

import { useLocale, useTranslations } from "next-intl";

import type { ScheduleSlot } from "@/api/schedule";
import { memberSlotState, waitlistPositionLabel } from "@/components/schedule/member-booking";
import { useUiTranslations } from "@/i18n/ui";
import { zonedText } from "@/lib/zoned-time";

/**
 * One class in the day view (plan §5a decision 8): time with a subtle
 * duration, name, coach, and the member's state or the spots left. The
 * location shows only when several locations are listed together. Classes
 * outside the package are dimmed with «Εκτός πακέτου» (decision 4).
 */
export function ClassRow({
  slot,
  timeZone = null,
  coachName,
  locationName,
  onOpen,
}: {
  slot: ScheduleSlot;
  /** ADR-177: the gym's zone; the class shows on its clock. */
  timeZone?: string | null;
  coachName: string | null;
  locationName: string | null;
  onOpen: () => void;
}) {
  const t = useTranslations("BoxSchedule");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const state = memberSlotState(slot);
  const time = zonedText(slot.scheduled_at, timeZone, locale, "time");
  const outside = slot.covered_by_package === false;
  const detail = [coachName, locationName].filter(Boolean).join(" · ");
  const friends = slot.friends_going ?? [];

  let status: { text: string; color: string };
  switch (state.kind) {
    case "booked":
      status = {
        text: state.status === "pending" ? t("statusPending") : t("statusBooked"),
        color: "var(--success)",
      };
      break;
    case "waitlisted":
      status = { text: waitlistPositionLabel(state.position, i18n), color: "var(--warning)" };
      break;
    case "waitlist_open":
      status = { text: t("statusFull"), color: "var(--dim)" };
      break;
    case "past":
      status = { text: t("statusPast"), color: "var(--dim)" };
      break;
    case "unavailable":
      status = { text: t("statusFull"), color: "var(--dim)" };
      break;
    default:
      status = { text: t("spotsLeft", { count: slot.spots_remaining }), color: "var(--success)" };
  }

  return (
    <button
      type="button"
      onClick={onOpen}
      className="grid min-h-16 w-full grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 rounded-2xl px-4 py-3 text-left"
      style={{
        background: "var(--panel)",
        border: "1px solid var(--border)",
        opacity: outside && state.kind !== "booked" ? 0.55 : 1,
      }}
    >
      <span className="flex flex-col items-start">
        <span className="font-mono text-sm font-bold" style={{ color: "var(--text-soft)" }}>
          {time}
        </span>
        <span className="text-[11px]" style={{ color: "var(--dim)" }}>
          {t("minutes", { count: slot.duration_minutes })}
        </span>
      </span>
      <span className="flex min-w-0 flex-col">
        <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>
          {slot.name}
        </span>
        {detail ? (
          <span className="truncate text-xs" style={{ color: "var(--dim)" }}>
            {detail}
          </span>
        ) : null}
        {friends.length > 0 ? (
          <span className="truncate text-xs font-semibold" style={{ color: "var(--primary-strong)" }}>
            {t("friendsGoing", { name: friends[0].nickname ?? "?", others: friends.length - 1 })}
          </span>
        ) : null}
      </span>
      <span className="flex flex-col items-end gap-1">
        {outside ? (
          <span
            className="rounded-full px-2 py-0.5 text-[10px] font-bold"
            style={{ background: "color-mix(in srgb, var(--warning) 16%, transparent)", color: "var(--warning)" }}
          >
            {t("outsidePackage")}
          </span>
        ) : null}
        <span className="text-xs font-bold" style={{ color: status.color }}>
          {status.text}
        </span>
      </span>
    </button>
  );
}
