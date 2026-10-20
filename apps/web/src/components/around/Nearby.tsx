"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import type { AroundClubItem, AroundEventItem } from "@/api/around";
import { OpenClubRow } from "@/components/community/FindPage";
import { ErrorLine } from "@/components/community/Sheet";
import { EventList } from "@/components/events/EventParts";
import { HubCard } from "@/components/member-app/HubParts";

import { parseFilter } from "./around";
import { useAroundError } from "./AreaPicker";
import { useKm } from "./AroundFilters";
import { needsOrigin, useAroundKind, useSavedAroundFilters } from "./use-around";

/** The person's remembered Γύρω μου filter narrowed to one kind, once it is known. */
function useRememberedFilter(kind: "events" | "clubs") {
  const saved = useSavedAroundFilters();
  const filter = parseFilter(saved.data?.last_used ?? null);
  return { filter: { ...filter, kinds: [kind] }, ready: saved.isSuccess || saved.isError };
}

function NearbyState({ error, empty }: { error: unknown; empty: boolean }) {
  const t = useTranslations("Around");
  const aroundError = useAroundError();
  if (needsOrigin(error)) {
    return (
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {t("needArea")}{" "}
        <Link href="/around" className="font-semibold underline" style={{ color: "var(--text)" }}>{t("chooseArea")}</Link>
      </p>
    );
  }
  if (error) return <ErrorLine message={aroundError(error)} />;
  return empty ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("nearbyEmpty")}</p> : null;
}

/** Events › «Κοντά μου» (board 8 Q5, with M6): open events near you, soonest first. */
export function NearbyEvents() {
  const t = useTranslations("Around");
  const km = useKm();
  const { filter, ready } = useRememberedFilter("events");
  const list = useAroundKind("events", { filter, enabled: ready, limit: 20 });
  const items = (list.data?.pages ?? []).flatMap((page) => page.items as AroundEventItem[]);
  const distances = new Map(items.map((item) => [item.event.id, item.distance_km]));

  return (
    <HubCard eyebrow={t("nearMe")}>
      {list.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : items.length > 0 ? (
        <EventList
          events={items.map((item) => item.event)}
          lead={(event) => {
            const distance = distances.get(event.id);
            return [event.group?.name ?? event.club.name, distance != null ? km(distance) : null].filter(Boolean).join(" · ");
          }}
        />
      ) : (
        <NearbyState error={list.error} empty />
      )}
      <Link href="/around/events" className="mt-2 flex min-h-11 items-center text-sm font-bold" style={{ color: "var(--primary-strong, var(--primary))" }}>
        {t("seeAllAround")}
      </Link>
    </HubCard>
  );
}

/** «+ Βρες» › «Κοντά μου»: open clubs near you, with «Μπες». */
export function NearbyClubs() {
  const t = useTranslations("Around");
  const km = useKm();
  const { filter, ready } = useRememberedFilter("clubs");
  const list = useAroundKind("clubs", { filter, enabled: ready, limit: 5 });
  const items = (list.data?.pages[0]?.items ?? []) as AroundClubItem[];

  return (
    <HubCard eyebrow={t("nearMe")}>
      {list.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : items.length > 0 ? (
        <ul className="flex flex-col gap-3">
          {items.map((item) => (
            <OpenClubRow key={item.club.id} club={item.club} detail={item.distance_km !== null ? km(item.distance_km) : undefined} />
          ))}
        </ul>
      ) : (
        <NearbyState error={list.error} empty />
      )}
      <Link href="/around/clubs" className="mt-2 flex min-h-11 items-center text-sm font-bold" style={{ color: "var(--primary-strong, var(--primary))" }}>
        {t("seeAllAround")}
      </Link>
    </HubCard>
  );
}
