"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { apiRequest } from "@/api/client";
import type { EventScope } from "@/api/events";
import type { FacilityLocation } from "@/api/facility";
import { fetchPublicBox } from "@/api/social";
import { useSession } from "@/components/session-provider";

import type { EventForm } from "./events";
import { SegmentGrid } from "./wizard/fields";

export type EventLocation = { id: string; name: string };

/**
 * The box's locations an event can be at: the public page's when the box is
 * published, else staff's own list; none means a free address only.
 */
export function useEventLocations(slug: string | null | undefined) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: ["events", "locations", slug ?? null],
    enabled: Boolean(token && slug),
    staleTime: 5 * 60_000,
    queryFn: async (): Promise<EventLocation[]> => {
      try {
        const page = await fetchPublicBox(slug!);
        if (page.locations.length > 0) return page.locations.map((location) => ({ id: location.id, name: location.name }));
      } catch {
        // Not published: try the staff list below.
      }
      try {
        const data = await apiRequest<{ locations: FacilityLocation[] }>(`/org/${encodeURIComponent(slug!)}/admin/locations`, { token: token! });
        return data.locations.filter((location) => !location.archived_at).map((location) => ({ id: location.id, name: location.name }));
      } catch {
        return [];
      }
    },
  });
}

/** An empty form: next Saturday at 10:00 for an hour, at the box's first location. */
export function blankEventForm(locations: EventLocation[], now: Date = new Date()): EventForm {
  const day = new Date(now);
  day.setDate(day.getDate() + ((6 - day.getDay() + 7) % 7 || 7));
  const pad = (value: number) => String(value).padStart(2, "0");
  return {
    title: "",
    description: "",
    date: [day.getFullYear(), pad(day.getMonth() + 1), pad(day.getDate())].join("-"),
    time: "10:00",
    durationMinutes: 60,
    place: locations[0] ? { kind: "location", locationId: locations[0].id } : { kind: "address", name: "", address: "" },
    capacity: "",
    paid: false,
    price: "",
    openToAll: false,
    guestPass: false,
    guestsPerMember: 1,
    goodForFriends: false,
    repeatWeekly: false,
    repeatUntil: "",
    coverMediaId: null,
    timeZone: null,
    groupOnly: true,
  };
}

/** A weekly event's change: this one, or this and the following weeks. */
export function ScopePicker({ value, onChange }: { value: EventScope; onChange: (value: EventScope) => void }) {
  const t = useTranslations("Events");
  return (
    <fieldset className="flex flex-col gap-1">
      <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("scopeLabel")}</legend>
      <SegmentGrid
        label={t("scopeLabel")}
        value={value}
        onChange={onChange}
        options={[
          { value: "this", label: t("scopeThis") },
          { value: "following", label: t("scopeFollowing") },
        ]}
      />
    </fieldset>
  );
}
