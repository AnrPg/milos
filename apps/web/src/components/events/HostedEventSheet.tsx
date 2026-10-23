"use client";

import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { createHostedEvent, EVENT_HOSTS_KEY, fetchEventHosts, type CommunityEvent, type EventHostChoice } from "@/api/events";
import { useSession } from "@/components/session-provider";

import { blankEventForm, useEventLocations } from "./EventFormParts";
import { eventHostMode } from "./events";
import { invalidateEvents } from "./use-events";
import { EventWizard } from "./wizard/EventWizard";

/** «Διοργάνωση ως» (ADR-185): «Ως εγώ» first, then each business where the person runs events. */
export function useEventHosts(enabled = true) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: EVENT_HOSTS_KEY,
    enabled: Boolean(token) && enabled,
    staleTime: 60_000,
    queryFn: () => fetchEventHosts(token!),
  });
}

/**
 * «Νέο event» from Events (ADR-185 §1): the wizard's first step is the
 * host («Ως εγώ» or a business), then the usual steps. As yourself the
 * event is yours, for everyone (Γύρω μου, your followers) or by your
 * invitation; as a business it goes in the club you pick there, and the
 * business can ask co-hosts as it publishes. Each host keeps its own draft.
 */
export function HostedEventSheet({
  initialHost = null,
  onCreated,
  onClose,
}: {
  initialHost?: string | null;
  onCreated?: (event: CommunityEvent) => void;
  onClose: () => void;
}) {
  const t = useTranslations("Events");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const hosts = useEventHosts();
  const choices = hosts.data ?? [];
  const [hostId, setHostId] = useState<string>(initialHost ?? "self");
  const host: EventHostChoice | undefined = choices.find((choice) => choice.id === hostId) ?? choices[0];
  const self = !host || host.kind === "self";
  const [clubId, setClubId] = useState<string | null>(null);
  const clubs = host?.clubs ?? [];
  const club = clubs.find((entry) => entry.id === clubId) ?? clubs.find((entry) => entry.kind === "gym") ?? clubs[0];
  const locations = useEventLocations(self ? null : (host?.slug ?? null));
  const [initial] = useState(() => ({ ...blankEventForm([]), openToAll: self }));
  const businessSlug = self ? null : (host?.slug ?? null);

  return (
    <EventWizard
      title={t("newEventTitle")}
      eyebrow={self ? t("hostSelf") : (host?.name ?? undefined)}
      initial={initial}
      mode={eventHostMode({ own: self })}
      hosts={
        choices.length > 1
          ? {
              options: choices.map((choice) => ({
                id: choice.id,
                label: choice.kind === "self" ? t("hostSelf") : (choice.name ?? choice.slug ?? "?"),
              })),
              value: host?.id ?? "self",
              onChange: (id) => {
                setHostId(id);
                setClubId(null);
              },
            }
          : null
      }
      hostHint={self ? t("hostSelfHint") : null}
      clubs={self ? null : { options: clubs.map((entry) => ({ id: entry.id, name: entry.name ?? "" })), value: club?.id, onChange: setClubId }}
      locations={locations.data ?? []}
      gymSlug={businessSlug}
      draftKey={["hosted", self ? "self" : (host?.id ?? "self")].join(":")}
      cohosts={businessSlug ? { ownSlug: businessSlug } : null}
      onSubmit={async (body) => {
        const created = await createHostedEvent(token, {
          ...body,
          host: self ? "self" : host!.id,
          ...(self || !club ? {} : { club_id: club.id }),
        });
        await Promise.all([invalidateEvents(queryClient), queryClient.invalidateQueries({ queryKey: EVENT_HOSTS_KEY })]);
        onCreated?.(created.event);
        return { cohostFailures: created.cohost_failures ?? [] };
      }}
      onClose={onClose}
    />
  );
}
