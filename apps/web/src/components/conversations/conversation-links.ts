/**
 * Where person-conversation notifications lead and what they say (ADR-193
 * §3): `person_message` opens the conversation, `message_request` the
 * requests folder. Both name who wrote, never what.
 */
export const CONVERSATION_NOTICES = ["person_message", "message_request"] as const;

type Payload = Record<string, unknown>;
type Translate = (key: string, values?: Record<string, string>) => string;

const text = (payload: Payload, key: string) => (typeof payload[key] === "string" ? (payload[key] as string) : "");

export function isConversationNotice(type: string) {
  return (CONVERSATION_NOTICES as readonly string[]).includes(type);
}

export function conversationNotificationUrl(type: string, payload: Payload): string | null {
  if (type === "message_request") return "/me/messages?folder=requests";
  if (type !== "person_message") return null;
  const conversationId = text(payload, "conversation_id");
  return conversationId ? `/me/messages/${encodeURIComponent(conversationId)}` : "/me/messages";
}

export function conversationNotificationText(type: string, payload: Payload, part: "title" | "body", t: Translate): string | null {
  if (!isConversationNotice(type)) return null;
  const name = text(payload, "nickname") || t("someone");
  return t(["notif", type, part].join("_"), { name });
}
