import type { ChatThread } from "@/api/messaging";

/**
 * The one inbox (vision §6.1–6.3, ADR-196): Feed Μηνύματα and `Box › Coach` open the
 * same list, segmented «Όλα · Άτομα · Coach · Box · Συναθλητές». `/messages`
 * is its address; `?filter=` picks the segment and `?thread=` opens a
 * conversation. «Άτομα» holds chats with other people (person conversations,
 * message requests, check-in buddy chats and other direct chats, ANR
 * 2026-10-25, ontology §5.1). The segment ids `clubs` and `partners` predate
 * the labels «Box» and «Συναθλητές» and stay, as addresses use them.
 */
export const INBOX_SEGMENTS = ["all", "people", "coach", "clubs", "partners"] as const;
export type InboxSegment = (typeof INBOX_SEGMENTS)[number];

/**
 * The segments offered: «Συναθλητές» (training partners) only once the person
 * has one, so no tab opens onto nothing (vision §4 principle 2, ANR 2026-10-25).
 */
export function visibleSegments({ hasPartners }: { hasPartners: boolean }): InboxSegment[] {
  return INBOX_SEGMENTS.filter((segment) => segment !== "partners" || hasPartners);
}

export const INBOX_PATH = "/messages";

export function parseInboxSegment(value: string | null | undefined): InboxSegment {
  return INBOX_SEGMENTS.includes(value as InboxSegment) ? (value as InboxSegment) : "all";
}

/** The inbox's address, optionally on one segment or one conversation. */
export function inboxHref({ filter, thread }: { filter?: InboxSegment; thread?: string | null } = {}) {
  const params = new URLSearchParams();
  if (filter && filter !== "all") params.set("filter", filter);
  if (thread) params.set("thread", thread);
  const query = params.toString();
  return query ? `${INBOX_PATH}?${query}` : INBOX_PATH;
}

/** Whether a section that belongs to `segments` shows under `selected`; «Όλα» shows everything. */
export function showsIn(segments: readonly InboxSegment[], selected: InboxSegment) {
  return selected === "all" || segments.includes(selected);
}

export type ThreadSegmentContext = {
  currentUserId: string | null;
  /** Coaches of my providers and, for a coach, their clients: a direct chat with them is «Coach». */
  coachPeerIds: ReadonlySet<string>;
  /** Threads where a coaching message reached me (ADR-140 §7). */
  coachingThreadIds: ReadonlySet<string>;
};

/**
 * Where a gym thread files: a workout thread or a chat with my coach (or my
 * client) is «Coach»; the box's thread and a class's thread are «Box» (group
 * chats, ontology §5.8); any
 * other direct chat is with another person: «Άτομα».
 */
export function threadSegment(thread: ChatThread, context: ThreadSegmentContext): InboxSegment | null {
  if (context.coachingThreadIds.has(thread.id)) return "coach";
  switch (thread.context_type) {
    case "assignment":
      return "coach";
    case "box":
    case "class_slot":
      return "clubs";
    case "direct": {
      const other = thread.participants.find((participant) => participant.user_id !== context.currentUserId);
      return other && context.coachPeerIds.has(other.user_id) ? "coach" : "people";
    }
    default:
      return null;
  }
}

export function threadsIn(threads: ChatThread[], selected: InboxSegment, context: ThreadSegmentContext) {
  if (selected === "all") return threads;
  return threads.filter((thread) => threadSegment(thread, context) === selected);
}

/**
 * ADR-282: a thread the box's inbox answers (a box thread with someone
 * else). The person's own thread with a box lives in their box chats.
 */
export function isBoxInboxThread(thread: ChatThread, currentUserId: string | null) {
  return thread.context_type === "box" && thread.context_id !== currentUserId;
}

/** «Αναπάντητα»: the person wrote last, so the box owes an answer. */
export function awaitsBoxReply(thread: ChatThread) {
  return thread.context_type === "box" && thread.last_message?.sender_id === thread.context_id;
}

export const BOX_FILTERS = ["unanswered", "all"] as const;
export type BoxFilter = (typeof BOX_FILTERS)[number];

/**
 * Μηνύματα › Box for the box's inbox: «Αναπάντητα» keeps the box threads
 * waiting for an answer, «Όλα» everything; newest message first.
 */
export function boxInboxThreads(threads: ChatThread[], filter: BoxFilter) {
  const kept = filter === "unanswered" ? threads.filter(awaitsBoxReply) : threads;
  return [...kept].sort((a, b) => lastActivity(b).localeCompare(lastActivity(a)));
}

function lastActivity(thread: ChatThread) {
  return thread.last_message?.inserted_at ?? thread.inserted_at;
}
