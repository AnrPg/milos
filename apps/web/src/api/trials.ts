import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Trials (ADR-144, P2-M3, board 6): a visitor asks for or books a trial at a
 * published box, follows it up, and talks to the box afterwards; staff set
 * the rules and work the queue. Visitor calls are personal (no gym in the
 * path); staff calls go through the selected gym (`/admin`).
 */
export type TrialOffer = NonNullable<components["schemas"]["TrialOffer"]>;
export type TrialAsk = components["schemas"]["TrialAsk"];
export type MyTrial = components["schemas"]["MyTrial"];
export type TrialStatus = MyTrial["status"];
export type TrialBlockedReason = TrialOffer["blocked_reason"];
export type StaffTrial = components["schemas"]["StaffTrial"];
export type TrialQueue = components["schemas"]["TrialQueueResponse"];
export type TrialStage = TrialQueue["stage"];
export type TrialPolicy = components["schemas"]["TrialPolicy"];
export type TrialPolicyResponse = components["schemas"]["TrialPolicyResponse"];
export type BoxConversation = components["schemas"]["BoxConversation"];
export type BoxConversationMessage = components["schemas"]["BoxConversationMessage"];
export type BoxConversationSummary = components["schemas"]["BoxConversationsResponse"]["conversations"][number];

export const TRIAL_STAGES: TrialStage[] = ["requests", "upcoming", "visited", "joined"];

export const MY_TRIALS_KEY = ["trials", "mine"] as const;
export const myTrialKey = (id: string) => ["trials", "mine", id] as const;
export const TRIAL_POLICY_KEY = ["admin", "trials", "policy"] as const;
export const trialQueueKey = (stage: TrialStage) => ["admin", "trials", "queue", stage] as const;
export const boxConversationKey = (slug: string) => ["box-conversation", slug] as const;
export const BOX_CONVERSATIONS_KEY = ["box-conversations"] as const;

const box = (slug: string) => `/boxes/${encodeURIComponent(slug)}`;

// Visitor ------------------------------------------------------------------

export async function requestTrial(token: string, slug: string, ask: TrialAsk) {
  const data = await apiRequest<{ trial: MyTrial }>(`${box(slug)}/trials`, { method: "POST", token, body: ask });
  return data.trial;
}

export async function fetchMyTrials(token: string) {
  const data = await apiRequest<{ trials: MyTrial[] }>("/me/trials", { token });
  return data.trials;
}

export async function fetchMyTrial(token: string, id: string) {
  const data = await apiRequest<{ trial: MyTrial }>(`/me/trials/${encodeURIComponent(id)}`, { token });
  return data.trial;
}

export async function cancelTrial(token: string, id: string) {
  const data = await apiRequest<{ trial: MyTrial }>(`/me/trials/${encodeURIComponent(id)}/cancel`, {
    method: "POST",
    token,
  });
  return data.trial;
}

export function followUpTrial(token: string, id: string, action: "join" | "dismiss") {
  return apiRequest<{ trial: MyTrial; conversation: BoxConversation | null }>(
    `/me/trials/${encodeURIComponent(id)}/follow-up`,
    { method: "POST", token, body: { action } },
  );
}

// Talking to a box ------------------------------------------------------------

export async function openBoxConversation(token: string, slug: string) {
  const data = await apiRequest<{ conversation: BoxConversation }>(`${box(slug)}/conversation`, { method: "POST", token });
  return data.conversation;
}

export async function fetchBoxConversation(token: string, slug: string) {
  const data = await apiRequest<{ conversation: BoxConversation }>(`${box(slug)}/conversation?limit=100`, { token });
  return data.conversation;
}

export async function sendBoxMessage(token: string, slug: string, body: string, clientOperationId: string) {
  const data = await apiRequest<{ message: BoxConversationMessage }>(`${box(slug)}/conversation/messages`, {
    method: "POST",
    token,
    body: { body, client_operation_id: clientOperationId },
  });
  return data.message;
}

export function markBoxConversationRead(token: string, slug: string, messageId: string) {
  return apiRequest<{ last_read_message_id: string }>(`${box(slug)}/conversation/read`, {
    method: "POST",
    token,
    body: { message_id: messageId },
  });
}

export async function fetchBoxConversations(token: string) {
  const data = await apiRequest<{ conversations: BoxConversationSummary[] }>("/me/box-conversations", { token });
  return data.conversations;
}

// Staff ------------------------------------------------------------------

export function fetchTrialPolicy(token: string) {
  return apiRequest<TrialPolicyResponse>("/admin/trial-policy", { token });
}

export function updateTrialPolicy(token: string, policy: TrialPolicy) {
  return apiRequest<TrialPolicyResponse>("/admin/trial-policy", { method: "PUT", token, body: policy });
}

export function fetchTrialQueue(token: string, stage: TrialStage) {
  return apiRequest<TrialQueue>(`/admin/trials?stage=${stage}`, { token });
}

export async function acceptTrial(token: string, id: string) {
  const data = await apiRequest<{ trial: StaffTrial }>(`/admin/trials/${encodeURIComponent(id)}/accept`, {
    method: "POST",
    token,
  });
  return data.trial;
}

export async function declineTrial(token: string, id: string, reason: string | null) {
  const data = await apiRequest<{ trial: StaffTrial }>(`/admin/trials/${encodeURIComponent(id)}/decline`, {
    method: "POST",
    token,
    body: { reason },
  });
  return data.trial;
}

export async function recordTrialAttendance(token: string, id: string, status: "attended" | "no_show") {
  const data = await apiRequest<{ trial: StaffTrial }>(`/admin/trials/${encodeURIComponent(id)}/attendance`, {
    method: "POST",
    token,
    body: { status },
  });
  return data.trial;
}

/** The trial's class as a one-event calendar file (board 6 Q5: «Also in calendar»). */
export function trialCalendarFile(trial: MyTrial, title: string) {
  const start = new Date(trial.class.scheduled_at);
  const end = new Date(start.getTime() + (trial.class.duration_minutes ?? 60) * 60_000);
  const stamp = (date: Date) => date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const escape = (value: string) => value.replace(/[\\;,]/g, (match) => `\\${match}`).replace(/\n/g, "\\n");
  const place = [trial.location?.name, trial.location?.address, trial.location?.city].filter(Boolean).join(", ");
  return [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Palee//Trial//EN",
    "BEGIN:VEVENT",
    `UID:trial-${trial.id}@palee`,
    `DTSTAMP:${stamp(new Date())}`,
    `DTSTART:${stamp(start)}`,
    `DTEND:${stamp(end)}`,
    `SUMMARY:${escape(title)}`,
    place ? `LOCATION:${escape(place)}` : null,
    trial.bring_note ? `DESCRIPTION:${escape(trial.bring_note)}` : null,
    "END:VEVENT",
    "END:VCALENDAR",
  ]
    .filter(Boolean)
    .join("\r\n");
}
