import type { ChatThread } from "@/api/messaging";

/**
 * The one inbox (vision §6.1–6.3, ADR-196): Feed ✈ and `Box › Coach` open the
 * same list, segmented «Όλα · Coach · Clubs · Partners». `/messages` is its
 * address; `?filter=` picks the segment and `?thread=` opens a conversation.
 */
export const INBOX_SEGMENTS = ["all", "coach", "clubs", "partners"] as const;
export type InboxSegment = (typeof INBOX_SEGMENTS)[number];

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
 * client) is «Coach»; the box's thread and a class's thread are «Clubs»; any
 * other direct chat shows under «Όλα» only.
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
      return other && context.coachPeerIds.has(other.user_id) ? "coach" : null;
    }
    default:
      return null;
  }
}

export function threadsIn(threads: ChatThread[], selected: InboxSegment, context: ThreadSegmentContext) {
  if (selected === "all") return threads;
  return threads.filter((thread) => threadSegment(thread, context) === selected);
}
