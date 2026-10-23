"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useTranslations } from "next-intl";

import { NearbyEvents } from "@/components/around/Nearby";
import { HubCard, HubPage } from "@/components/member-app/HubParts";

import { EventList } from "./EventParts";
import { HostedEventSheet, useEventHosts } from "./HostedEventSheet";
import { useClubsEvents } from "./use-events";

type Segment = "clubs" | "near";

/**
 * Events (board 8 Q5, mockup `eventsScreen`): «Τα clubs μου», upcoming
 * events of every club the member can see, and «Κοντά μου», open events
 * near them from Γύρω μου (ADR-154). Soonest first in both. ADR-185:
 * «Νέο event» as yourself or a business you run events for, and the
 * organiser console once you host.
 */
export function EventsPage({ nearFirst = false }: { nearFirst?: boolean }) {
  const t = useTranslations("Events");
  const [segment, setSegment] = useState<Segment>(nearFirst ? "near" : "clubs");
  const events = useClubsEvents();
  const router = useRouter();
  const hosts = useEventHosts();
  const hosting = (hosts.data ?? []).some((host) => Boolean(host.organization_id && host.slug));
  const [creating, setCreating] = useState(false);

  return (
    <HubPage
      title={t("eventsTitle")}
      actions={
        <button type="button" onClick={() => setCreating(true)} className="min-h-11 shrink-0 rounded-full px-4 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
          {t("newEvent")}
        </button>
      }
    >
      {hosting ? (
        <Link href="/events/hosting" className="flex min-h-11 items-center justify-between rounded-2xl px-4 text-sm font-semibold" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}>
          <span>{t("hostingConsole")}</span>
          <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
        </Link>
      ) : null}
      <div role="group" aria-label={t("eventsSegments")} className="flex gap-1 rounded-full p-1" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {(["clubs", "near"] as Segment[]).map((value) => (
          <button
            key={value}
            type="button"
            aria-pressed={segment === value}
            onClick={() => setSegment(value)}
            className="min-h-10 flex-1 rounded-full px-3 text-sm font-bold"
            style={{
              background: segment === value ? "var(--panel-raised)" : "transparent",
              color: segment === value ? "var(--text)" : "var(--dim)",
            }}
          >
            {value === "clubs" ? t("myClubs") : t("nearMe")}
          </button>
        ))}
      </div>
      {segment === "clubs" ? (
        <HubCard eyebrow={t("myClubs")}>
          {events.isPending ? (
            <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
          ) : (events.data ?? []).length === 0 ? (
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("emptyClubs")}</p>
          ) : (
            <EventList events={events.data ?? []} />
          )}
        </HubCard>
      ) : (
        <NearbyEvents />
      )}
      <p className="px-1 text-xs" style={{ color: "var(--dim)" }}>{t("trialOfferNote")}</p>
      {creating ? (
        <HostedEventSheet
          onCreated={(event) => router.push(`/events/${encodeURIComponent(event.id)}`)}
          onClose={() => setCreating(false)}
        />
      ) : null}
    </HubPage>
  );
}
