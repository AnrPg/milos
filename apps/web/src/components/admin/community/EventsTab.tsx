"use client";

import Link from "next/link";
import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { createStaffEvent, fetchStaffEvents, staffEventsKey, type StaffEventRow } from "@/api/admin-events";
import type { EventListScope } from "@/api/events";
import { useMyClubs } from "@/components/community/use-community";
import { blankEventForm, EventEditorSheet, useEventLocations } from "@/components/events/EventEditorSheet";
import { DateBlock, useGoingLabel, usePriceLabel } from "@/components/events/EventParts";
import { formatTime, placeName } from "@/components/events/events";
import { invalidateEvents } from "@/components/events/use-events";
import { useSession } from "@/components/session-provider";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref } from "@/lib/organization-slug";
import { can } from "@/lib/role-navigation";

const SCOPES: EventListScope[] = ["upcoming", "past"];

/**
 * Κοινότητα › Events (board 8 Q6): the box's upcoming or past events with
 * their numbers, each opening its attendee list, and «+ Νέο event» in any of
 * the box's clubs for whoever runs events.
 */
export function EventsTab() {
  const t = useTranslations("EventsAdmin");
  const tEvents = useTranslations("Events");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const { membership, selectedOrganizationSlug } = useSelectedMembershipRole();
  const [scope, setScope] = useState<EventListScope>("upcoming");
  const [creating, setCreating] = useState(false);
  const events = useQuery({ queryKey: staffEventsKey(scope), enabled: Boolean(token), queryFn: () => fetchStaffEvents(token, scope) });
  const manage = can(membership, "manage_events");
  const clubs = useMyClubs();
  const boxClubs = (clubs.data ?? []).filter((club) => club.organization_slug === selectedOrganizationSlug && club.role === "staff");
  const [clubId, setClubId] = useState<string | null>(null);
  const chosenClub = clubId ?? boxClubs.find((club) => club.kind === "gym")?.id ?? boxClubs[0]?.id ?? null;
  const locations = useEventLocations(manage ? selectedOrganizationSlug : null);

  return (
    <>
      <div className="flex items-center gap-2">
        <div role="tablist" aria-label={tEvents("scopeAria")} className="flex grow gap-2">
          {SCOPES.map((value) => (
            <button
              key={value}
              type="button"
              role="tab"
              aria-selected={scope === value}
              onClick={() => setScope(value)}
              className="min-h-11 flex-1 rounded-full px-3 text-sm font-semibold"
              style={{
                background: scope === value ? "var(--panel-raised)" : "transparent",
                color: scope === value ? "var(--text)" : "var(--dim)",
                border: "1px solid var(--border)",
              }}
            >
              {value === "upcoming" ? tEvents("upcoming") : tEvents("past")}
            </button>
          ))}
        </div>
        {manage && chosenClub ? (
          <button type="button" onClick={() => setCreating(true)} className="min-h-11 shrink-0 rounded-full px-4 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--bg)" }}>
            {tEvents("newEvent")}
          </button>
        ) : null}
      </div>
      <section className="flex flex-col gap-2 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {!events.data ? (
          <p style={{ color: "var(--dim)" }}>{tEvents("loading")}</p>
        ) : events.data.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{scope === "upcoming" ? t("emptyUpcoming") : t("emptyPast")}</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {events.data.map((event) => (
              <StaffEventItem key={event.id} event={event} past={scope === "past"} href={adminHref(`/admin/community/events/${event.id}`, selectedOrganizationSlug)} />
            ))}
          </ul>
        )}
      </section>
      {creating && chosenClub ? (
        <EventEditorSheet
          title={tEvents("newEventTitle")}
          initial={blankEventForm(locations.data ?? [])}
          locations={locations.data ?? []}
          clubs={boxClubs.map((club) => ({ id: club.id, name: club.name }))}
          clubId={chosenClub}
          onClubChange={setClubId}
          coverSlug={can(membership, "manage_settings") ? selectedOrganizationSlug : null}
          onSubmit={async (body) => {
            await createStaffEvent(token, { ...body, club_id: chosenClub });
            setScope("upcoming");
            await invalidateEvents(queryClient);
          }}
          onClose={() => setCreating(false)}
        />
      ) : null}
    </>
  );
}

function StaffEventItem({ event, past, href }: { event: StaffEventRow; past: boolean; href: string }) {
  const t = useTranslations("EventsAdmin");
  const tEvents = useTranslations("Events");
  const locale = useLocale();
  const price = usePriceLabel();
  const going = useGoingLabel();
  const { stats } = event;
  const numbers = past
    ? [t("statCame", { count: stats.came }), t("statNoShows", { count: stats.no_shows }), t("statLateCancels", { count: stats.late_cancels })]
    : [going(event), stats.waitlisted ? t("statWaitlisted", { count: stats.waitlisted }) : null, event.price_cents > 0 ? t("statPaid", { count: stats.paid }) : null];
  if (stats.late_cancels && !past) numbers.push(t("statLateCancels", { count: stats.late_cancels }));

  return (
    <li>
      <Link href={href} className="flex items-center gap-3 rounded-2xl px-3 py-3" style={{ background: "var(--panel-raised)" }}>
        <DateBlock iso={event.starts_at} />
        <span className="min-w-0 grow">
          <span className="block truncate font-bold" style={{ color: "var(--text)", textDecoration: event.cancelled ? "line-through" : undefined }}>{event.title}</span>
          <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
            {[event.group?.name ?? event.club.name, formatTime(event.starts_at, locale), placeName(event.place), price(event)].filter(Boolean).join(" · ")}
          </span>
          <span className="block text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
            {event.cancelled ? tEvents("pillCancelled") : numbers.filter(Boolean).join(" · ")}
          </span>
        </span>
        <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
      </Link>
    </li>
  );
}
