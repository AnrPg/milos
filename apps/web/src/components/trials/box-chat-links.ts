import { MESSAGE_TOPICS, type MessageTopic } from "@/api/messaging";

/** ADR-282: a topic from a link (`/b/:slug/chat?topic=payment`), or none. */
export function parseChatTopic(value: string | null | undefined): MessageTopic | null {
  return MESSAGE_TOPICS.includes(value as MessageTopic) ? (value as MessageTopic) : null;
}

/** The person's chat with a box, the topic preset from where they pressed «Επικοινωνία με το box». */
export function boxChatHref(slug: string, topic: MessageTopic | null = null) {
  const path = `/b/${encodeURIComponent(slug)}/chat`;
  return topic ? `${path}?topic=${topic}` : path;
}
