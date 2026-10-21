"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { NearbyEvents } from "@/components/around/Nearby";
import { HubCard, HubPage } from "@/components/member-app/HubParts";

import { EventList } from "./EventParts";
import { useClubsEvents } from "./use-events";

type Segment = "clubs" | "near";

/**
 * Events (board 8 Q5, mockup `eventsScreen`): «Τα clubs μου», upcoming
 * events of every club the member can see, and «Κοντά μου», open events
 * near them from Γύρω μου (ADR-154). Soonest first in both.
 */
export function EventsPage({ nearFirst = false }: { nearFirst?: boolean }) {
  const t = useTranslations("Events");
  const [segment, setSegment] = useState<Segment>(nearFirst ? "near" : "clubs");
  const events = useClubsEvents();

  return (
    <HubPage title={t("eventsTitle")}>
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
    </HubPage>
  );
}
