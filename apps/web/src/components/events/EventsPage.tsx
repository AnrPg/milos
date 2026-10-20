"use client";

import { useTranslations } from "next-intl";

import { HubCard, HubPage } from "@/components/member-app/HubParts";

import { EventList } from "./EventParts";
import { useClubsEvents } from "./use-events";

/**
 * Events across the member's clubs (board 8 Q5, mockup `eventsScreen`):
 * upcoming events of every club they can see, soonest first. «Κοντά μου»
 * comes with Γύρω μου (M6), so only «Τα clubs μου» is here.
 */
export function EventsPage() {
  const t = useTranslations("Events");
  const events = useClubsEvents();

  return (
    <HubPage title={t("eventsTitle")}>
      <HubCard eyebrow={t("myClubs")}>
        {events.isPending ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : (events.data ?? []).length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("emptyClubs")}</p>
        ) : (
          <EventList events={events.data ?? []} />
        )}
      </HubCard>
      <p className="px-1 text-xs" style={{ color: "var(--dim)" }}>{t("trialOfferNote")}</p>
    </HubPage>
  );
}
