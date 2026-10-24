import type { PersonConversation, PersonConversationPage, PersonMessage, PersonMessagePage } from "@/api/conversations";

/**
 * Pure helpers for person conversations (ADR-193 §3): the order messages
 * show in, the sends still on their way and the rows a list shows.
 */

/** A message written here and not yet answered by the API (or failed). */
export type PendingMessage = {
  client_operation_id: string;
  body: string;
  created_at: string;
  status: "sending" | "failed";
};

export type ShownMessage =
  | { kind: "sent"; key: string; message: PersonMessage }
  | { kind: "pending"; key: string; pending: PendingMessage };

/**
 * Pages arrive newest first (each page, and the pages in turn). The screen
 * shows the oldest at the top and the newest at the bottom, each message
 * once, then the pending sends the API has not answered yet. A pending send
 * whose operation id already came back from the API is not shown twice.
 */
export function shownMessages(pages: PersonMessagePage[], pending: PendingMessage[] = []): ShownMessage[] {
  const seen = new Set<string>();
  const operations = new Set<string>();
  const sent: ShownMessage[] = [];
  for (const page of pages) {
    for (const message of page.messages ?? []) {
      if (seen.has(message.id)) continue;
      seen.add(message.id);
      if (message.client_operation_id) operations.add(message.client_operation_id);
      sent.push({ kind: "sent", key: message.id, message });
    }
  }
  sent.reverse();
  const waiting = pending
    .filter((item) => !operations.has(item.client_operation_id))
    .map((item): ShownMessage => ({ kind: "pending", key: item.client_operation_id, pending: item }));
  return [...sent, ...waiting];
}

/** Drops the pending sends the API now holds (after a refetch). */
export function settledPending(pending: PendingMessage[], pages: PersonMessagePage[]): PendingMessage[] {
  const operations = new Set(
    pages.flatMap((page) => (page.messages ?? []).map((message) => message.client_operation_id).filter(Boolean)),
  );
  return pending.filter((item) => !operations.has(item.client_operation_id));
}

/**
 * The rows of a folder, across pages, each conversation once. A conversation
 * you opened and never wrote in has nothing to show, so it is left out
 * (vision §4 principle 2: no empty cards).
 */
export function listedConversations(pages: PersonConversationPage[]): PersonConversation[] {
  const seen = new Set<string>();
  const rows: PersonConversation[] = [];
  for (const page of pages) {
    for (const conversation of page.conversations ?? []) {
      if (seen.has(conversation.id) || !conversation.last_message) continue;
      seen.add(conversation.id);
      rows.push(conversation);
    }
  }
  return rows;
}

export function badgeText(count: number) {
  return count > 99 ? "99+" : String(count);
}

/** A last message on one line, for a list row. */
export function previewLine(body: string, max = 80) {
  const line = body.replace(/\s+/g, " ").trim();
  return line.length > max ? `${line.slice(0, max - 1).trimEnd()}…` : line;
}

/** The name a person goes by here: nickname, else @handle, else the fallback. */
export function personLabel(person: { nickname?: string | null; handle?: string | null }, fallback: string) {
  if (person.nickname) return person.nickname;
  if (person.handle) return `@${person.handle}`;
  return fallback;
}
