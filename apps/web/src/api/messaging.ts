import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

type ThreadsResponse =
  paths["/api/threads"]["get"]["responses"]["200"]["content"]["application/json"];
type MessagesResponse =
  paths["/api/threads/{id}/messages"]["get"]["responses"]["200"]["content"]["application/json"];
type MarkReadResponse =
  paths["/api/threads/{id}/read"]["post"]["responses"]["200"]["content"]["application/json"];

export type ChatThread = ThreadsResponse["threads"][number];
export type ChatParticipant = ChatThread["participants"][number];
export type ChatMessage = MessagesResponse["messages"][number];
export type MessageType = ChatMessage["message_type"];
export type ThreadContextType = ChatThread["context_type"];

export async function fetchThreads(token: string, contextType?: ThreadContextType) {
  const qs = contextType ? `?context_type=${contextType}` : "";
  return apiRequest<ThreadsResponse>(`/threads${qs}`, { token });
}

export async function createDirectThread(token: string, participantId: string) {
  return apiRequest<{ thread: ChatThread }>("/threads", {
    method: "POST",
    token,
    body: { context_type: "direct", participant_id: participantId },
  });
}

export async function getOrCreateContextThread(
  token: string,
  contextType: "assignment" | "class_slot",
  contextId: string,
) {
  return apiRequest<{ thread: ChatThread }>("/threads", {
    method: "POST",
    token,
    body: { context_type: contextType, context_id: contextId },
  });
}

export async function fetchThreadMessages(
  token: string,
  threadId: string,
  params: { limit?: number; before_id?: string } = {},
) {
  const qs = new URLSearchParams(
    Object.entries(params)
      .filter(([, v]) => v !== undefined)
      .map(([k, v]) => [k, String(v)]),
  ).toString();

  return apiRequest<{ messages: ChatMessage[] }>(
    `/threads/${threadId}/messages${qs ? `?${qs}` : ""}`,
    { token },
  );
}

export async function sendMessage(
  token: string,
  threadId: string,
  body: string,
  messageType: MessageType = "chat",
) {
  return apiRequest<{ message: ChatMessage }>(`/threads/${threadId}/messages`, {
    method: "POST",
    token,
    body: { body, message_type: messageType },
  });
}

export async function markThreadRead(token: string, threadId: string, lastMessageId: string) {
  return apiRequest<MarkReadResponse>(`/threads/${threadId}/read`, {
    method: "POST",
    token,
    body: { message_id: lastMessageId },
  });
}

export async function fetchUnreadCount(token: string) {
  return apiRequest<{ unread_count: number }>("/threads/unread-count", { token });
}

export async function searchUsers(token: string, query: string) {
  return apiRequest<{ users: { id: string; nickname: string; role: string }[] }>(
    `/me/search/users?q=${encodeURIComponent(query)}`,
    { token },
  );
}
