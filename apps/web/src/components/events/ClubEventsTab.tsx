"use client";

import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import type { CommunityClub, CommunityGroup } from "@/api/community";
import { createClubEvent, type CommunityEvent, type EventListScope } from "@/api/events";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

import { blankEventForm, EventEditorSheet, useEventLocations } from "./EventEditorSheet";
import { EventList } from "./EventParts";
import { invalidateEvents, useClubEvents } from "./use-events";

const SCOPES: EventListScope[] = ["upcoming", "past"];

/**
 * A club's Events (board 8 Q1, Q5): Επερχόμενα and Περασμένα, and «+ Νέο
 * event» for staff and coaches who run the box's events. On a member group's
 * page it lists the group's events, and the group's admins create free,
 * members-only ones there.
 */
export function ClubEventsTab({ club, group = null }: { club: CommunityClub; group?: CommunityGroup | null }) {
  const t = useTranslations("Events");
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const { memberships } = useSelectedMembershipRole();
  const [scope, setScope] = useState<EventListScope>("upcoming");
  const [creating, setCreating] = useState(false);
  const events = useClubEvents(club.id, scope);
  const membership = memberships.find((entry) => entry.organization.slug === club.organization_slug) ?? null;
  const runsEvents = club.role === "staff" && can(membership, "manage_events");
  const canCreate = group ? group.status === "active" && (group.admin || runsEvents) : runsEvents;
  const locations = useEventLocations(canCreate ? club.organization_slug : null);
  const shown = (events.data ?? []).filter((event) => !group || event.channel_id === group.id);
  const lead = (event: CommunityEvent) =>
    group ? undefined : event.group?.name ?? (event.open_to_non_members ? t("leadOpen") : t("leadMembers"));

  return (
    <>
      <div className="flex items-center gap-2">
        <div role="tablist" aria-label={t("scopeAria")} className="flex grow gap-2">
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
              {value === "upcoming" ? t("upcoming") : t("past")}
            </button>
          ))}
        </div>
        {canCreate ? (
          <button
            type="button"
            onClick={() => setCreating(true)}
            className="min-h-11 shrink-0 rounded-full px-4 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("newEvent")}
          </button>
        ) : null}
      </div>
      <HubCard>
        {events.isPending ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : shown.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {scope === "upcoming" ? (canCreate ? t("emptyUpcomingCreate") : t("emptyUpcoming")) : t("emptyPast")}
          </p>
        ) : (
          <EventList events={shown} lead={lead} />
        )}
      </HubCard>
      {creating ? (
        <EventEditorSheet
          title={t("newEventTitle")}
          eyebrow={group?.name ?? club.name}
          initial={blankEventForm(locations.data ?? [])}
          group={Boolean(group)}
          locations={locations.data ?? []}
          coverSlug={runsEvents && can(membership, "manage_settings") ? club.organization_slug : null}
          onSubmit={async (body) => {
            await createClubEvent(tokens!.access_token, club.id, group ? { ...body, channel_id: group.id } : body);
            setScope("upcoming");
            await invalidateEvents(queryClient);
          }}
          onClose={() => setCreating(false)}
        />
      ) : null}
    </>
  );
}
