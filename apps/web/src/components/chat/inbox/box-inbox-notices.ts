import type { MessageTopic } from "@/api/messaging";

import { TOPIC_KEYS } from "../message-topics";

type Translate = (key: string, values?: Record<string, string>) => string;

/**
 * ADR-282: the bell's words for `box_inbox_message`, someone writing to the
 * box: «Γιώργος Π. έγραψε στο Milos method», or who brought a coach in; the
 * body is the topic and the opening of the message. Null for other types.
 */
export function boxInboxNotificationText(
  type: string,
  payload: Record<string, unknown>,
  part: "title" | "body",
  i18n: Translate,
): string | null {
  if (type !== "box_inbox_message") return null;
  const text = (key: string) => (typeof payload[key] === "string" ? (payload[key] as string) : "");

  if (part === "title") {
    return payload.brought_in_by
      ? i18n("ntfBoxInboxBroughtIn", { by: text("brought_in_by") })
      : i18n("ntfBoxInboxTitle", { name: text("nickname"), box: text("box_name") });
  }

  const topic = text("topic");
  const topicLabel = topic in TOPIC_KEYS ? i18n(TOPIC_KEYS[topic as MessageTopic]) : null;
  return [topicLabel, text("body") || null].filter(Boolean).join(" · ") || i18n("ntfBoxInboxBody", { name: text("nickname") });
}
