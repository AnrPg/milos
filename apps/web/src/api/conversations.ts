import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Person-to-person conversations (ADR-193 §3): one per pair of people,
 * account-scoped (no gym), with the person's inbox and message requests.
 * Separate from the gym's threads (`/me/threads`), which stay the box's and
 * the coach's. Every call is sent in the personal session (`scope:
 * "account"`), never under `/org/:slug`, so people without a gym can write.
 */
export type PersonConversation = components["schemas"]["PersonConversation"];
export type PersonConversationPage = components["schemas"]["PersonConversationPage"];
export type PersonConversationUnreadCount = components["schemas"]["PersonConversationUnreadCount"];
export type PersonMessage = components["schemas"]["PersonMessage"];
export type PersonMessagePage = components["schemas"]["PersonMessagePage"];
export type ConversationFolder = PersonConversation["folder"];
export type ConversationPerson = PersonConversation["person"];
export type PeopleSearchPerson = components["schemas"]["PeopleSearchPerson"];

export const CONVERSATION_FOLDERS: ConversationFolder[] = ["inbox", "requests"];

export const CONVERSATIONS_KEY = ["my", "conversations"] as const;
export const CONVERSATION_LISTS_KEY = [...CONVERSATIONS_KEY, "list"] as const;
export const CONVERSATIONS_UNREAD_KEY = [...CONVERSATIONS_KEY, "unread"] as const;
export const PEOPLE_SEARCH_KEY = ["people-search"] as const;

export const conversationListKey = (folder: ConversationFolder) => [...CONVERSATION_LISTS_KEY, folder] as const;
export const conversationKey = (conversationId: string) => [...CONVERSATIONS_KEY, "one", conversationId] as const;
export const conversationMessagesKey = (conversationId: string) => [...conversationKey(conversationId), "messages"] as const;
export const peopleSearchKey = (query: string) => [...PEOPLE_SEARCH_KEY, query] as const;

const id = (value: string) => encodeURIComponent(value);

function query(params: Record<string, string | number | null | undefined>) {
  const search = new URLSearchParams();
  Object.entries(params).forEach(([name, value]) => {
    if (value !== null && value !== undefined && value !== "") search.set(name, String(value));
  });
  const text = search.toString();
  return text ? `?${text}` : "";
}

export function fetchConversations(
  token: string,
  folder: ConversationFolder = "inbox",
  cursor?: string | null,
  limit?: number,
) {
  return apiRequest<PersonConversationPage>(`/me/conversations${query({ folder, cursor, limit })}`, { token, scope: "account" });
}

export function fetchConversationUnreadCount(token: string) {
  return apiRequest<PersonConversationUnreadCount>("/me/conversations/unread-count", { token, scope: "account" });
}

/** Opens the conversation with a person, or finds the one that exists. */
export async function openConversation(token: string, personId: string) {
  return (
    await apiRequest<{ conversation: PersonConversation }>("/me/conversations", {
      method: "POST",
      token,
      scope: "account",
      body: { person_id: personId },
    })
  ).conversation;
}

export async function fetchConversation(token: string, conversationId: string) {
  return (await apiRequest<{ conversation: PersonConversation }>(`/me/conversations/${id(conversationId)}`, { token, scope: "account" }))
    .conversation;
}

/** A page of messages, newest first; `next_cursor` pages back in time. */
export function fetchConversationMessages(token: string, conversationId: string, cursor?: string | null) {
  return apiRequest<PersonMessagePage>(`/me/conversations/${id(conversationId)}/messages${query({ cursor })}`, {
    token,
    scope: "account",
  });
}

/** A retry with the same `clientOperationId` is answered with the message already written. */
export async function sendConversationMessage(token: string, conversationId: string, body: string, clientOperationId: string) {
  return (
    await apiRequest<{ message: PersonMessage }>(`/me/conversations/${id(conversationId)}/messages`, {
      method: "POST",
      token,
      scope: "account",
      body: { body, client_operation_id: clientOperationId },
    })
  ).message;
}

async function conversationAction(token: string, conversationId: string, action: "read" | "accept") {
  return (
    await apiRequest<{ conversation: PersonConversation }>(`/me/conversations/${id(conversationId)}/${action}`, {
      method: "POST",
      token,
      scope: "account",
    })
  ).conversation;
}

export const markConversationRead = (token: string, conversationId: string) => conversationAction(token, conversationId, "read");
export const acceptConversation = (token: string, conversationId: string) => conversationAction(token, conversationId, "accept");

/** Declines a request: it disappears for you, and the sender is not told. */
export async function declineConversation(token: string, conversationId: string) {
  await apiRequest<void>(`/me/conversations/${id(conversationId)}/decline`, { method: "POST", token, scope: "account" });
}

/** People search across Palee (ADR-193 §4), ranked by shared clubs, Buddies, follows, nearby, public. */
export async function searchPeople(token: string, text: string, signal?: AbortSignal) {
  return (await apiRequest<{ people: PeopleSearchPerson[] }>(`/people-search${query({ q: text })}`, { token, scope: "account", signal }))
    .people;
}
