import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

import type { EventListScope, EventScope } from "./events";

/**
 * «Κοινότητα › Events» for staff (ADR-153): the box's events with their
 * numbers, an event's attendees («Ήρθε», «Πλήρωσε», freeing a place), the
 * message to everyone going, editing and cancelling, and the one trial offer
 * after the event. Calls go through the selected gym (`/admin`) unless a
 * `slug` names the organisation: the organiser console (ADR-185) runs any
 * host's events, a person's own included, from one place.
 */
export type StaffEventRow = components["schemas"]["StaffCommunityEventRow"];
export type StaffEvent = components["schemas"]["StaffCommunityEvent"];
export type StaffAttendee = components["schemas"]["CommunityEventAttendee"];
export type EventStats = components["schemas"]["CommunityEventStats"];
export type StaffEventDraft = components["schemas"]["StaffCommunityEventRequest"];
export type PaymentMethod = components["schemas"]["CommunityEventPaidRequest"]["payment_method"];
export type EventCohostRow = components["schemas"]["CommunityEventCohostRow"];
export type CohostRequest = components["schemas"]["CommunityEventCohostRequest"];
export type EventFinances = components["schemas"]["CommunityEventFinancesResponse"];
export type EventAnalytics = components["schemas"]["CommunityEventAnalyticsResponse"];
export type ConsoleScope = "all" | "upcoming" | "past";

export const PAYMENT_METHODS: PaymentMethod[] = ["cash", "card_manual", "bank_transfer", "other"];

export const STAFF_EVENTS_KEY = ["admin", "events"] as const;
export const staffEventsKey = (scope: EventListScope, slug: string | null = null) => ["admin", "events", "list", scope, slug] as const;
export const staffEventKey = (id: string) => ["admin", "events", "event", id] as const;
export const eventCohostsKey = (id: string) => ["admin", "events", "cohosts", id] as const;
export const cohostRequestsKey = (slug: string | null) => ["admin", "events", "cohost-requests", slug] as const;
export const eventFinancesKey = (slug: string | null, scope: ConsoleScope) => ["admin", "events", "finances", slug, scope] as const;
export const eventAnalyticsKey = (slug: string | null, scope: ConsoleScope) => ["admin", "events", "analytics", slug, scope] as const;

type Slug = string | null | undefined;

const community = (slug: Slug) => (slug ? `/org/${encodeURIComponent(slug)}/admin/community` : "/admin/community");
const events = (slug: Slug) => `${community(slug)}/events`;
const id = (value: string) => encodeURIComponent(value);

export async function fetchStaffEvents(token: string, scope: EventListScope, slug: Slug = null) {
  const data = await apiRequest<{ events: StaffEventRow[] }>(`${events(slug)}?scope=${scope}`, { token });
  return data.events ?? [];
}

export async function fetchStaffEvent(token: string, eventId: string, slug: Slug = null) {
  const data = await apiRequest<{ event: StaffEvent }>(`${events(slug)}/${id(eventId)}`, { token });
  return data.event;
}

export function createStaffEvent(token: string, draft: StaffEventDraft) {
  return apiRequest<{ event: StaffEvent; occurrences: number; cohost_failures?: components["schemas"]["CommunityEventCohostFailure"][] }>(
    events(null),
    { method: "POST", token, body: draft },
  );
}

export async function updateStaffEvent(
  token: string,
  eventId: string,
  update: components["schemas"]["CommunityEventUpdateRequest"],
  slug: Slug = null,
) {
  const data = await apiRequest<{ event: StaffEvent }>(`${events(slug)}/${id(eventId)}`, { method: "PATCH", token, body: update });
  return data.event;
}

export async function cancelStaffEvent(token: string, eventId: string, reason: string | null, scope: EventScope, slug: Slug = null) {
  const data = await apiRequest<{ event: StaffEvent }>(`${events(slug)}/${id(eventId)}/cancel`, {
    method: "POST",
    token,
    body: { reason, scope },
  });
  return data.event;
}

/** Frees someone's place; the first on the waitlist moves up. */
export async function removeAttendee(token: string, eventId: string, userId: string, slug: Slug = null) {
  const data = await apiRequest<{ event: StaffEvent }>(`${events(slug)}/${id(eventId)}/attendees/${id(userId)}`, {
    method: "DELETE",
    token,
  });
  return data.event;
}

export async function setCheckedIn(token: string, eventId: string, userId: string, checkedIn: boolean, slug: Slug = null) {
  const data = await apiRequest<{ event: StaffEvent }>(`${events(slug)}/${id(eventId)}/attendees/${id(userId)}/check-in`, {
    method: "PUT",
    token,
    body: { checked_in: checkedIn },
  });
  return data.event;
}

export async function markPaid(token: string, eventId: string, userId: string, method: PaymentMethod, slug: Slug = null) {
  const data = await apiRequest<{ event: StaffEvent }>(`${events(slug)}/${id(eventId)}/attendees/${id(userId)}/paid`, {
    method: "PUT",
    token,
    body: { payment_method: method },
  });
  return data.event;
}

/** ADR-185: records that a paid place was given back (all of it without an amount). */
export async function refundAttendee(token: string, eventId: string, userId: string, amountCents: number | null, slug: Slug = null) {
  const data = await apiRequest<{ event: StaffEvent }>(`${events(slug)}/${id(eventId)}/attendees/${id(userId)}/refund`, {
    method: "PUT",
    token,
    body: amountCents ? { amount_cents: amountCents } : {},
  });
  return data.event;
}

export async function messageAttendees(token: string, eventId: string, body: string, slug: Slug = null) {
  const data = await apiRequest<{ sent: number }>(`${events(slug)}/${id(eventId)}/message`, { method: "POST", token, body: { body } });
  return data.sent;
}

export async function sendTrialOffer(token: string, eventId: string, slug: Slug = null) {
  const data = await apiRequest<{ sent: number }>(`${events(slug)}/${id(eventId)}/trial-offer`, { method: "POST", token });
  return data.sent;
}

// ADR-185: co-hosting ----------------------------------------------------------

export async function fetchEventCohosts(token: string, eventId: string, slug: Slug = null) {
  const data = await apiRequest<{ cohosts?: EventCohostRow[] }>(`${events(slug)}/${id(eventId)}/cohosts`, { token });
  return data.cohosts ?? [];
}

/** Asks the box at that page address to co-host the event (and its later weeks). */
export async function inviteCohost(token: string, eventId: string, boxSlug: string, slug: Slug = null) {
  const data = await apiRequest<{ cohosts?: EventCohostRow[] }>(`${events(slug)}/${id(eventId)}/cohosts`, {
    method: "POST",
    token,
    body: { slug: boxSlug },
  });
  return data.cohosts ?? [];
}

export async function removeCohost(token: string, eventId: string, cohostId: string, slug: Slug = null) {
  const data = await apiRequest<{ cohosts?: EventCohostRow[] }>(`${events(slug)}/${id(eventId)}/cohosts/${id(cohostId)}`, {
    method: "DELETE",
    token,
  });
  return data.cohosts ?? [];
}

export async function fetchCohostRequests(token: string, slug: Slug = null) {
  const data = await apiRequest<{ requests?: CohostRequest[] }>(`${community(slug)}/cohost-requests`, { token });
  return data.requests ?? [];
}

export async function answerCohostRequest(token: string, requestId: string, answer: "accepted" | "declined" | "removed", slug: Slug = null) {
  const data = await apiRequest<{ requests?: CohostRequest[] }>(`${community(slug)}/cohost-requests/${id(requestId)}/answer`, {
    method: "POST",
    token,
    body: { answer },
  });
  return data.requests ?? [];
}

export async function sendCohostTrialOffer(token: string, requestId: string, slug: Slug = null) {
  const data = await apiRequest<{ sent: number }>(`${community(slug)}/cohost-requests/${id(requestId)}/trial-offer`, { method: "POST", token });
  return data.sent;
}

// ADR-185: the console's numbers -----------------------------------------------

export function fetchEventFinances(token: string, scope: ConsoleScope, slug: Slug = null) {
  return apiRequest<EventFinances>(`${community(slug)}/event-finances?scope=${scope}`, { token });
}

export function fetchEventAnalytics(token: string, scope: ConsoleScope, slug: Slug = null) {
  return apiRequest<EventAnalytics>(`${community(slug)}/event-analytics?scope=${scope}`, { token });
}
