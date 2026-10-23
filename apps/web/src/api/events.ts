import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Club events from the member's personal session (ADR-153): a club's
 * upcoming and past events, upcoming events across their clubs, their own
 * events at any box, a box page's open events, the event page (with a guest
 * pass link), «Θα έρθω» and, for whoever runs the club's events or a member
 * group, creating, editing and cancelling.
 */
export type CommunityEvent = components["schemas"]["CommunityEvent"];
export type EventMine = NonNullable<CommunityEvent["my"]>;
export type EventPlace = CommunityEvent["place"];
export type EventInvitation = NonNullable<CommunityEvent["invitation"]>;
export type EventDraft = components["schemas"]["CommunityEventRequest"];
export type EventUpdate = components["schemas"]["CommunityEventUpdateRequest"];
export type EventScope = NonNullable<EventUpdate["scope"]>;
export type EventInvite = components["schemas"]["CommunityEventInviteResponse"];
export type EventListScope = "upcoming" | "past";

export const EVENTS_KEY = ["events"] as const;
export const eventKey = (id: string, invite: string | null = null) => ["events", "event", id, invite] as const;
export const clubEventsKey = (clubId: string, scope: EventListScope) => ["events", "club", clubId, scope] as const;
export const MY_EVENTS_KEY = ["events", "mine"] as const;
export const CLUBS_EVENTS_KEY = ["events", "clubs"] as const;
export const boxEventsKey = (slug: string) => ["events", "box", slug] as const;

const id = (value: string) => encodeURIComponent(value);

export async function fetchClubEvents(token: string, clubId: string, scope: EventListScope) {
  const data = await apiRequest<{ events: CommunityEvent[] }>(`/me/community/clubs/${id(clubId)}/events?scope=${scope}`, {
    token,
  });
  return data.events ?? [];
}

/** Creates an event (or a weekly run with `repeat_until`) in a club; `channel_id` makes it a member group's. */
/** ADR-185: an address in `cohost_slugs` the API could not ask (no published box); the event was still made. */
export type EventCohostFailure = components["schemas"]["CommunityEventCohostFailure"];
type EventCreated = { event: CommunityEvent; occurrences: number; cohost_failures?: EventCohostFailure[] };

export function createClubEvent(token: string, clubId: string, draft: EventDraft) {
  return apiRequest<EventCreated>(`/me/community/clubs/${id(clubId)}/events`, {
    method: "POST",
    token,
    body: draft,
  });
}

export async function fetchClubsEvents(token: string) {
  const data = await apiRequest<{ events: CommunityEvent[] }>("/me/community/events", { token });
  return data.events ?? [];
}

export async function fetchMyEvents(token: string) {
  const data = await apiRequest<{ events: CommunityEvent[] }>("/me/events", { token });
  return data.events ?? [];
}

export async function fetchBoxEvents(token: string, slug: string) {
  const data = await apiRequest<{ events: CommunityEvent[] }>(`/boxes/${id(slug)}/events`, { token });
  return data.events ?? [];
}

/** The event page; with a guest pass token it also says who invited and whether a place is left. */
export async function fetchEvent(token: string, eventId: string, invite: string | null = null) {
  const query = invite ? `?${new URLSearchParams({ invite }).toString()}` : "";
  const data = await apiRequest<{ event: CommunityEvent }>(`/me/events/${id(eventId)}${query}`, { token });
  return data.event;
}

/** «Θα έρθω» (a place, or the waitlist when full) or «Δεν θα έρθω». */
export async function rsvpEvent(token: string, eventId: string, going: boolean, inviteToken: string | null = null) {
  const data = await apiRequest<{ event: CommunityEvent }>(`/me/events/${id(eventId)}/rsvp`, {
    method: "PUT",
    token,
    body: inviteToken ? { going, invite_token: inviteToken } : { going },
  });
  return data.event;
}

/** A guest pass link for an event the member is going to. */
export function createEventInvite(token: string, eventId: string) {
  return apiRequest<EventInvite>(`/me/events/${id(eventId)}/invites`, { method: "POST", token });
}

export async function updateEvent(token: string, eventId: string, update: EventUpdate) {
  const data = await apiRequest<{ event: CommunityEvent }>(`/me/events/${id(eventId)}`, {
    method: "PATCH",
    token,
    body: update,
  });
  return data.event;
}

export async function cancelEvent(token: string, eventId: string, reason: string | null, scope: EventScope) {
  const data = await apiRequest<{ event: CommunityEvent }>(`/me/events/${id(eventId)}/cancel`, {
    method: "POST",
    token,
    body: { reason, scope },
  });
  return data.event;
}

/** ADR-185: counts an open of the event page (once a day per person; hosts aren't counted). */
export function recordEventView(token: string, eventId: string) {
  return apiRequest<{ counted: boolean }>(`/me/events/${id(eventId)}/views`, { method: "POST", token });
}

export type EventHostChoice = components["schemas"]["CommunityEventHostChoice"];
export type HostedEventDraft = components["schemas"]["CommunityEventHostedRequest"];
export const EVENT_HOSTS_KEY = ["events", "hosts"] as const;

/** «Διοργάνωση ως»: «Ως εγώ» and each business where the person runs events. */
export async function fetchEventHosts(token: string) {
  const data = await apiRequest<{ hosts: EventHostChoice[] }>("/me/event-hosts", { token });
  return data.hosts ?? [];
}

/** Creates an event as yourself (`host: "self"`) or as a business (its organisation id). */
export function createHostedEvent(token: string, draft: HostedEventDraft) {
  return apiRequest<EventCreated>("/me/events", { method: "POST", token, body: draft });
}
