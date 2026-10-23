"use client";

import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { createHostedEvent, EVENT_HOSTS_KEY, fetchEventHosts, type CommunityEvent, type EventHostChoice } from "@/api/events";
import { Field, inputStyle } from "@/components/community/ProposeGroupSheet";
import { useSession } from "@/components/session-provider";
import { Select } from "@/components/ui/Select";

import { blankEventForm, EventEditorSheet, useEventLocations } from "./EventEditorSheet";
import { invalidateEvents } from "./use-events";

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
 * «Νέο event» from Events (ADR-185 §1): the host picker («Ως εγώ» or a
 * business), then the usual form. As yourself the event is yours, for
 * everyone (Γύρω μου, your followers) or by your invitation; as a business
 * it goes in the club you pick there.
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

  const picker =
    choices.length > 1 ? (
      <Field label={t("hostAs")}>
        <Select
          value={host?.id ?? "self"}
          onValueChange={(value) => {
            setHostId(String(value));
            setClubId(null);
          }}
          className="min-h-11 rounded-2xl px-3 text-sm font-normal"
          style={inputStyle}
        >
          {choices.map((choice) => (
            <option key={choice.id} value={choice.id}>
              {choice.kind === "self" ? t("hostSelf") : (choice.name ?? choice.slug ?? "?")}
            </option>
          ))}
        </Select>
      </Field>
    ) : null;

  return (
    <EventEditorSheet
      key={self ? "self" : (host?.id ?? "self")}
      title={t("newEventTitle")}
      eyebrow={self ? t("hostSelf") : (host?.name ?? undefined)}
      initial={{ ...blankEventForm(locations.data ?? []), openToAll: self }}
      mode={self ? "self" : "club"}
      hostPicker={
        <>
          {picker}
          {self ? <p className="-mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("hostSelfHint")}</p> : null}
        </>
      }
      locations={locations.data ?? []}
      clubs={self ? undefined : clubs.map((entry) => ({ id: entry.id, name: entry.name ?? "" }))}
      clubId={club?.id}
      onClubChange={setClubId}
      gymSlug={self ? null : (host?.slug ?? null)}
      onSubmit={async (body) => {
        const created = await createHostedEvent(tokens!.access_token, {
          ...body,
          host: self ? "self" : host!.id,
          ...(self || !club ? {} : { club_id: club.id }),
        });
        await Promise.all([invalidateEvents(queryClient), queryClient.invalidateQueries({ queryKey: EVENT_HOSTS_KEY })]);
        onCreated?.(created.event);
      }}
      onClose={onClose}
    />
  );
}
