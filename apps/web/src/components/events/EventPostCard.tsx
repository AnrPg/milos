"use client";

import Link from "next/link";
import { useLocale, useTranslations } from "next-intl";

import type { CommunityEvent } from "@/api/events";

import { formatPrice, formatTime, placeName } from "./events";
import { DateBlock, RsvpButton, useGoingLabel } from "./EventParts";

/**
 * An event's card in the feed (board 8 Q5, mockup `eventPost`): the date
 * block, the title, time · place · «N πάνε» · price, and «Θα έρθω» inline.
 */
export function EventPostCard({ event }: { event: CommunityEvent }) {
  const t = useTranslations("Events");
  const locale = useLocale();
  const going = useGoingLabel();
  const line = [
    formatTime(event.starts_at, locale, event.time_zone),
    placeName(event.place),
    going(event),
    formatPrice(event.price_cents, event.currency, locale) ?? t("free"),
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <div className="flex flex-wrap items-center gap-3 rounded-2xl p-3" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
      <DateBlock iso={event.starts_at} timeZone={event.time_zone} />
      <Link href={`/events/${event.id}`} className="min-w-0 grow basis-40">
        <span className="block truncate font-bold" style={{ color: "var(--text)", textDecoration: event.cancelled ? "line-through" : undefined }}>
          {event.title}
        </span>
        <span className="block text-xs" style={{ color: "var(--text-soft)" }}>
          {event.cancelled ? t("pillCancelled") : line}
        </span>
      </Link>
      <div className="shrink-0">
        <RsvpButton event={event} compact />
      </div>
    </div>
  );
}

/** A card whose event is gone or hidden from the reader: the snapshot's title only. */
export function EventSnapshotCard({ snapshot }: { snapshot: Record<string, unknown> }) {
  const t = useTranslations("Events");
  return (
    <div className="rounded-2xl p-3" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
      <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("eventTitle")}</p>
      <p className="font-bold" style={{ color: "var(--text)" }}>{typeof snapshot.title === "string" ? snapshot.title : t("eventTitle")}</p>
    </div>
  );
}
