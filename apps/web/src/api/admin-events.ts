import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

import type { EventListScope, EventScope } from "./events";

/**
 * «Κοινότητα › Events» for staff (ADR-153): the box's events with their
 * numbers, an event's attendees («Ήρθε», «Πλήρωσε», freeing a place), the
 * message to everyone going, editing and cancelling, and the one trial offer
 * after the event. Calls go through the selected gym (`/admin`).
 */
export type StaffEventRow = components["schemas"]["StaffCommunityEventRow"];
export type StaffEvent = components["schemas"]["StaffCommunityEvent"];
export type StaffAttendee = components["schemas"]["CommunityEventAttendee"];
export type EventStats = components["schemas"]["CommunityEventStats"];
export type StaffEventDraft = components["schemas"]["StaffCommunityEventRequest"];
export type PaymentMethod = components["schemas"]["CommunityEventPaidRequest"]["payment_method"];

export const PAYMENT_METHODS: PaymentMethod[] = ["cash", "card_manual", "bank_transfer", "other"];

export const STAFF_EVENTS_KEY = ["admin", "events"] as const;
export const staffEventsKey = (scope: EventListScope) => ["admin", "events", "list", scope] as const;
export const staffEventKey = (id: string) => ["admin", "events", "event", id] as const;

const BASE = "/admin/community/events";
const id = (value: string) => encodeURIComponent(value);

export async function fetchStaffEvents(token: string, scope: EventListScope) {
  const data = await apiRequest<{ events: StaffEventRow[] }>(`${BASE}?scope=${scope}`, { token });
  return data.events;
}

export async function fetchStaffEvent(token: string, eventId: string) {
  const data = await apiRequest<{ event: StaffEvent }>(`${BASE}/${id(eventId)}`, { token });
  return data.event;
}

export function createStaffEvent(token: string, draft: StaffEventDraft) {
  return apiRequest<{ event: StaffEvent; occurrences: number }>(BASE, { method: "POST", token, body: draft });
}

export async function updateStaffEvent(token: string, eventId: string, update: components["schemas"]["CommunityEventUpdateRequest"]) {
  const data = await apiRequest<{ event: StaffEvent }>(`${BASE}/${id(eventId)}`, { method: "PATCH", token, body: update });
  return data.event;
}

export async function cancelStaffEvent(token: string, eventId: string, reason: string | null, scope: EventScope) {
  const data = await apiRequest<{ event: StaffEvent }>(`${BASE}/${id(eventId)}/cancel`, {
    method: "POST",
    token,
    body: { reason, scope },
  });
  return data.event;
}

/** Frees someone's place; the first on the waitlist moves up. */
export async function removeAttendee(token: string, eventId: string, userId: string) {
  const data = await apiRequest<{ event: StaffEvent }>(`${BASE}/${id(eventId)}/attendees/${id(userId)}`, {
    method: "DELETE",
    token,
  });
  return data.event;
}

export async function setCheckedIn(token: string, eventId: string, userId: string, checkedIn: boolean) {
  const data = await apiRequest<{ event: StaffEvent }>(`${BASE}/${id(eventId)}/attendees/${id(userId)}/check-in`, {
    method: "PUT",
    token,
    body: { checked_in: checkedIn },
  });
  return data.event;
}

export async function markPaid(token: string, eventId: string, userId: string, method: PaymentMethod) {
  const data = await apiRequest<{ event: StaffEvent }>(`${BASE}/${id(eventId)}/attendees/${id(userId)}/paid`, {
    method: "PUT",
    token,
    body: { payment_method: method },
  });
  return data.event;
}

export async function messageAttendees(token: string, eventId: string, body: string) {
  const data = await apiRequest<{ sent: number }>(`${BASE}/${id(eventId)}/message`, { method: "POST", token, body: { body } });
  return data.sent;
}

export async function sendTrialOffer(token: string, eventId: string) {
  const data = await apiRequest<{ sent: number }>(`${BASE}/${id(eventId)}/trial-offer`, { method: "POST", token });
  return data.sent;
}
