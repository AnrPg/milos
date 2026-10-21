"use client";

import Link from "next/link";
import { useState } from "react";
import { useLocale, useTranslations } from "next-intl";

import type { CommunityEvent } from "@/api/events";
import { clientErrorMessage } from "@/components/client/errors";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

import { dateBlock, eventErrorKey, formatPrice, formatTime, isLateCancel, placeName, rsvpState } from "./events";
import { useRsvp } from "./use-events";

/** An event API error in words: the events' own copy, else the shared error map. */
export function useEventError() {
  const t = useTranslations("Events");
  const tUi = useUiTranslations();
  return (error: unknown) => {
    if (!error) return null;
    const key = eventErrorKey(error);
    return key ? t(key) : clientErrorMessage(error, tUi);
  };
}

/** The date block of the mockup's event rows: «ΣΑΒ» over «25». */
export function DateBlock({ iso, size = "md" }: { iso: string; size?: "md" | "lg" }) {
  const locale = useLocale();
  const { weekday, day } = dateBlock(iso, locale);
  return (
    <span
      aria-hidden="true"
      className={`flex shrink-0 flex-col items-center justify-center rounded-xl text-center font-bold leading-tight ${size === "lg" ? "h-16 w-16" : "h-12 w-12"}`}
      style={{ background: "var(--panel-raised)", color: "var(--dim)", fontSize: size === "lg" ? 12 : 10 }}
    >
      {weekday}
      <b className="font-mono tabular-nums" style={{ color: "var(--text)", fontSize: size === "lg" ? 22 : 17 }}>{day}</b>
    </span>
  );
}

/** «€15», or «Δωρεάν». */
export function usePriceLabel() {
  const t = useTranslations("Events");
  const locale = useLocale();
  return (event: Pick<CommunityEvent, "price_cents" | "currency">) => formatPrice(event.price_cents, event.currency, locale) ?? t("free");
}

/** «12 πάνε», or «18/30» when the event has a limit. */
export function useGoingLabel() {
  const t = useTranslations("Events");
  return (event: Pick<CommunityEvent, "going_count" | "capacity">) =>
    event.capacity ? t("goingOfCapacity", { going: event.going_count, capacity: event.capacity }) : t("goingCount", { count: event.going_count });
}

/**
 * One event in a list (mockup `ev`): the date block, the title, a line with
 * where it comes from or who may come, the time and how many go, and a pill
 * with the price or where the reader stands. Opens the event page.
 */
export function EventRow({ event, lead }: { event: CommunityEvent; lead?: string }) {
  const t = useTranslations("Events");
  const locale = useLocale();
  const price = usePriceLabel();
  const going = useGoingLabel();
  const status = event.my?.status;
  const pill = event.cancelled
    ? t("pillCancelled")
    : status === "going"
      ? t("pillGoing")
      : status === "waitlisted"
        ? t("pillWaitlisted")
        : price(event);
  const line = [lead ?? event.group?.name ?? event.club.name, formatTime(event.starts_at, locale), placeName(event.place), going(event)]
    .filter(Boolean)
    .join(" · ");

  return (
    <li>
      <Link href={`/events/${event.id}`} className="grid min-h-16 grid-cols-[3rem_minmax(0,1fr)_auto] items-center gap-3 py-2">
        <DateBlock iso={event.starts_at} />
        <span className="min-w-0">
          <span className="block truncate font-bold" style={{ color: "var(--text)", textDecoration: event.cancelled ? "line-through" : undefined }}>
            {event.title}
          </span>
          <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>{line}</span>
        </span>
        <span
          className="shrink-0 rounded-full px-2.5 py-1 text-xs font-bold"
          style={{
            background: status === "going" ? "var(--primary)" : "color-mix(in srgb, var(--primary) 16%, transparent)",
            color: status === "going" ? "var(--bg)" : "var(--primary-strong, var(--primary))",
          }}
        >
          {pill}
        </span>
      </Link>
    </li>
  );
}

export function EventList({ events, lead }: { events: CommunityEvent[]; lead?: (event: CommunityEvent) => string | undefined }) {
  return (
    <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
      {events.map((event) => (
        <EventRow key={event.id} event={event} lead={lead?.(event)} />
      ))}
    </ul>
  );
}

/** Faces of who's going and «12 πάνε»; names only for people who can see the club. */
export function Goers({ event, max = 5 }: { event: CommunityEvent; max?: number }) {
  const going = useGoingLabel();
  const faces = (event.goers ?? []).slice(0, max);
  return (
    <div className="flex items-center gap-3">
      {faces.length > 0 ? (
        <span className="flex -space-x-2 rtl:space-x-reverse">
          {faces.map((person) => (
            <span key={person.id} className="rounded-full" style={{ boxShadow: "0 0 0 2px var(--panel)" }}>
              <PersonAvatar name={person.nickname} url={person.avatar_url} size={32} />
            </span>
          ))}
        </span>
      ) : null}
      <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{going(event)}</span>
    </div>
  );
}

/**
 * «Θα έρθω» (with the price on a paid event) takes a place, or the waitlist
 * when full; «Δεν θα έρθω» frees it, after a warning within 2 hours of the
 * start. `compact` is the feed card's single button: once answered it links
 * to the event page instead.
 */
export function RsvpButton({
  event,
  inviteToken = null,
  compact = false,
}: {
  event: CommunityEvent;
  inviteToken?: string | null;
  compact?: boolean;
}) {
  const t = useTranslations("Events");
  const locale = useLocale();
  const eventError = useEventError();
  const rsvp = useRsvp(event.id, inviteToken);
  const [confirmLate, setConfirmLate] = useState(false);
  const state = rsvpState(event);
  const price = formatPrice(event.price_cents, event.currency, locale);
  const pill = "flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold disabled:opacity-50";

  function giveUp() {
    if (isLateCancel(event)) setConfirmLate(true);
    else rsvp.mutate(false);
  }

  let control: React.ReactNode;
  if (state === "join" || state === "join_waitlist") {
    control = (
      <button
        type="button"
        disabled={rsvp.isPending}
        onClick={() => rsvp.mutate(true)}
        className={`${pill} ${compact ? "" : "flex-1"}`}
        style={
          state === "join"
            ? { background: "var(--primary)", color: "var(--bg)" }
            : { background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--primary)" }
        }
      >
        {state === "join_waitlist" ? t("joinWaitlist") : price ? t("goingPaid", { price }) : t("going")}
      </button>
    );
  } else if (compact && (state === "going" || state === "waitlisted")) {
    control = (
      <Link href={`/events/${event.id}`} className={pill} style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}>
        {state === "going" ? t("youreGoing") : t("youreWaitlisted")}
      </Link>
    );
  } else if (state === "going" || state === "waitlisted") {
    control = (
      <div className="flex w-full flex-col gap-2">
        <p className="rounded-2xl px-4 py-3 text-sm font-bold" style={{ background: "color-mix(in srgb, var(--primary) 14%, var(--panel))", color: "var(--text)" }}>
          {state === "going" ? t("youreGoing") : t("youreWaitlistedLong")}
        </p>
        <button
          type="button"
          disabled={rsvp.isPending}
          onClick={giveUp}
          className={pill}
          style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
        >
          {state === "going" ? t("notGoing") : t("leaveWaitlist")}
        </button>
      </div>
    );
  } else {
    const note = state === "cancelled" ? t("stateCancelled") : state === "over" ? t("stateOver") : t("stateClosed");
    control = compact ? null : <p className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>{note}</p>;
  }

  return (
    <>
      {control}
      {!compact || rsvp.error ? <ErrorLine message={eventError(rsvp.error)} /> : null}
      {confirmLate ? (
        <Sheet
          labelId={["late-cancel", event.id].join("-")}
          eyebrow={event.title}
          title={t("lateTitle")}
          onClose={() => setConfirmLate(false)}
          footer={
            <>
              <SheetButton onClick={() => setConfirmLate(false)}>{t("lateKeep")}</SheetButton>
              <SheetButton
                primary
                disabled={rsvp.isPending}
                onClick={() => {
                  setConfirmLate(false);
                  rsvp.mutate(false);
                }}
              >
                {t("notGoing")}
              </SheetButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("lateBody")}</p>
        </Sheet>
      ) : null}
    </>
  );
}
