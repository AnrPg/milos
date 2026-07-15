import { apiRequest } from "@/api/client";

export type MessageType = "chat" | "coaching_note" | "system";

export interface ChatParticipant {
  id: string;
  user_id: string;
  nickname?: string | null;
  last_read_message_id: string | null;
  joined_at?: string;
}

export interface ChatThread {
  id: string;
  context_type: "direct" | "assignment" | "class_slot";
  context_id: string | null;
  inserted_at: string;
  participants: ChatParticipant[];
}

export interface ChatMessage {
  id: string;
  thread_id: string;
  sender_id: string;
  body: string;
  message_type: MessageType;
  inserted_at: string;
}

export type ThreadContextType = "direct" | "assignment" | "class_slot";

export async function fetchThreads(token: string, contextType?: ThreadContextType) {
  const qs = contextType ? `?context_type=${contextType}` : "";
  return apiRequest<{ threads: ChatThread[] }>(`/threads${qs}`, { token });
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
  params: { limit?: number; cursor_inserted_at?: string } = {},
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
  return apiRequest<{ read: boolean }>(`/threads/${threadId}/read`, {
    method: "POST",
    token,
    body: { last_message_id: lastMessageId },
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
