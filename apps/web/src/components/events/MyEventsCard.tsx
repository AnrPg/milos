"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { HubCard } from "@/components/member-app/HubParts";

import { EventList } from "./EventParts";
import { useMyEvents } from "./use-events";

const SHOWN = 3;

/**
 * «Τα events μου» on Αρχική (board 8 Q5): the next events the member is going
 * to or waiting for, at any box, and the way to every club's events. The slot
 * stays when there are none.
 */
export function MyEventsCard() {
  const t = useTranslations("Events");
  const events = useMyEvents();
  const list = (events.data ?? []).slice(0, SHOWN);

  return (
    <HubCard eyebrow={t("myEvents")}>
      {events.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : list.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("myEventsEmpty")}</p>
      ) : (
        <EventList events={list} />
      )}
      <Link href="/events" className="mt-2 flex min-h-11 items-center text-sm font-bold" style={{ color: "var(--primary-strong, var(--primary))" }}>
        {t("allEventsLink")}
      </Link>
    </HubCard>
  );
}
