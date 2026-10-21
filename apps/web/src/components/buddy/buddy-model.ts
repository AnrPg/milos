import type {
  BuddyLink,
  BuddyOverview,
  BuddyPerson,
  BuddyQuietHours,
  SupportQuickReply,
  SupportReplyKind,
  SupportRequest,
} from "@/api/buddies";

/**
 * Pure pieces of Buddy για στήριξη (ADR-160): the undo window, quiet hours,
 * the quick replies' words, the breathing timer, who a request goes to and
 * what the sender sees. Kept apart from the screens so they can be tested.
 */

/** Joins key parts, so dynamic message keys stay plain strings. */
export const key = (...parts: string[]) => parts.join(".");

export const UNDO_SECONDS = 5;
export const NO_REPLY_MINUTES = 10;
export const BREATHING_SECONDS = 120;
export const MESSAGE_MAX = 280;

/** Whole seconds left to take a request back (0 once the window closed). */
export function undoSecondsLeft(undoUntil: string | null | undefined, now: number, cap = UNDO_SECONDS): number {
  if (!undoUntil) return 0;
  const until = Date.parse(undoUntil);
  if (Number.isNaN(until)) return 0;
  const left = Math.ceil((until - now) / 1000);
  return Math.max(0, Math.min(cap, left));
}

/** Whether the undo button still belongs on screen. */
export function canStillUndo(request: Pick<SupportRequest, "status" | "can_undo" | "undo_until">, now: number): boolean {
  if (request.status === "undone") return false;
  if (request.can_undo === false) return false;
  return undoSecondsLeft(request.undo_until, now) > 0;
}

/** «23:00–07:00» */
export function quietHoursLabel(hours: BuddyQuietHours | null | undefined): string | null {
  if (!hours?.from || !hours?.to) return null;
  return `${hours.from}–${hours.to}`;
}

function minutesOf(time: string): number | null {
  const match = /^(\d{2}):(\d{2})$/.exec(time);
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (hours > 23 || minutes > 59) return null;
  return hours * 60 + minutes;
}

/** True when `time` (HH:MM, local) falls inside quiet hours; overnight ranges wrap past midnight. */
export function insideQuietHours(hours: BuddyQuietHours | null | undefined, time: string): boolean {
  if (!hours) return false;
  const from = minutesOf(hours.from);
  const to = minutesOf(hours.to);
  const at = minutesOf(time);
  if (from === null || to === null || at === null || from === to) return false;
  return from < to ? at >= from && at < to : at >= from || at < to;
}

/** Whether a pair of HH:MM values is a valid quiet-hours range the API accepts. */
export function validQuietHours(from: string, to: string): boolean {
  const start = minutesOf(from);
  const end = minutesOf(to);
  return start !== null && end !== null && start !== end;
}

/** The message key of a quick reply, and the words the buddy sends. */
export function replyKey(kind: SupportReplyKind): string {
  return key("reply", kind);
}

/** What a reply reads as: a quick reply's words, else the buddy's own. */
export function replyText(reply: { kind: SupportReplyKind; text?: string | null }, t: (key: string) => string): string {
  const own = reply.text?.trim();
  if (reply.kind === "text") return own || "";
  const quick = t(replyKey(reply.kind));
  return own ? `${quick} ${own}` : quick;
}

export function isQuickReply(kind: string): kind is SupportQuickReply {
  return kind === "here" || kind === "walk" || kind === "call";
}

export type BreathingPhase = "in" | "hold" | "out";

/** One breath: 4 s in, 2 s hold, 4 s out (ten seconds, six a minute). */
export const BREATH_PATTERN: { phase: BreathingPhase; seconds: number }[] = [
  { phase: "in", seconds: 4 },
  { phase: "hold", seconds: 2 },
  { phase: "out", seconds: 4 },
];
const BREATH_SECONDS = BREATH_PATTERN.reduce((sum, step) => sum + step.seconds, 0);

export type BreathingState = {
  phase: BreathingPhase;
  /** Seconds left in this phase (whole, at least 1 while running). */
  phaseLeft: number;
  /** Seconds left in the whole exercise. */
  remaining: number;
  /** 0..1 how full the circle is: grows breathing in, stays on hold, shrinks out. */
  scale: number;
  done: boolean;
};

/** Where a breathing exercise is after `elapsed` seconds of `total`. */
export function breathingState(elapsed: number, total = BREATHING_SECONDS): BreathingState {
  const clamped = Math.max(0, Math.min(elapsed, total));
  const remaining = Math.max(0, Math.ceil(total - clamped));
  if (clamped >= total) return { phase: "out", phaseLeft: 0, remaining: 0, scale: 0, done: true };
  let within = clamped % BREATH_SECONDS;
  for (const step of BREATH_PATTERN) {
    if (within < step.seconds) {
      const progress = within / step.seconds;
      const scale = step.phase === "in" ? progress : step.phase === "hold" ? 1 : 1 - progress;
      return { phase: step.phase, phaseLeft: Math.max(1, Math.ceil(step.seconds - within)), remaining, scale, done: false };
    }
    within -= step.seconds;
  }
  return { phase: "in", phaseLeft: BREATH_PATTERN[0].seconds, remaining, scale: 0, done: false };
}

/** «2:00» */
export function clock(seconds: number): string {
  const whole = Math.max(0, Math.round(seconds));
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, "0")}`;
}

/** Display name of a person, or the fallback for an unclaimed link. */
export function personName(person: BuddyPerson | null | undefined, fallback: string): string {
  return person?.nickname?.trim() || fallback;
}

/** Defensive read of the overview (a partial answer never breaks a screen). */
export function overviewLists(overview: Partial<BuddyOverview> | null | undefined) {
  return {
    buddies: overview?.buddies ?? [],
    supporting: overview?.supporting ?? [],
    invitations: overview?.invitations ?? [],
    maxBuddies: overview?.max_buddies ?? 2,
    inviteDays: overview?.invite_days ?? 7,
  };
}

/** My buddies who would get «Χρειάζομαι στήριξη» right now. */
export function activeBuddies(overview: Partial<BuddyOverview> | null | undefined): BuddyLink[] {
  return overviewLists(overview).buddies.filter((link) => link.status === "active" && link.person);
}

/** «Δήμητρα, Κώστας» */
export function recipientNames(links: Pick<BuddyLink, "person">[], fallback: string): string {
  return links.map((link) => personName(link.person, fallback)).join(", ");
}

/** Open slots for my own buddies (pending invitations count). */
export function freeBuddySlots(overview: Partial<BuddyOverview> | null | undefined): number {
  const { buddies, maxBuddies } = overviewLists(overview);
  const open = buddies.filter((link) => link.status === "pending" || link.status === "active").length;
  return Math.max(0, maxBuddies - open);
}

/** Unread buddy messages across every link, for the Εγώ row's badge. */
export function unreadTotal(overview: Partial<BuddyOverview> | null | undefined): number {
  const { buddies, supporting } = overviewLists(overview);
  return [...buddies, ...supporting].reduce((sum, link) => sum + (link.unread_messages ?? 0), 0);
}

/** Which links the Buddy page lists: open ones always, ended ones only when they have a conversation to reread. */
export function visibleLinks(links: BuddyLink[]): BuddyLink[] {
  return links.filter((link) => link.status === "pending" || link.status === "active" || (link.status === "ended" && link.started_at));
}

export type SenderPhase = "sending" | "undone" | "waiting" | "replied" | "noReply";

/** What the sender's status card shows. */
export function senderPhase(request: SupportRequest, now: number): SenderPhase {
  if (request.status === "undone") return "undone";
  if ((request.replies?.length ?? 0) > 0) return "replied";
  if (request.status === "sending" && canStillUndo(request, now)) return "sending";
  if (nudgeDue(request, now)) return "noReply";
  return "waiting";
}

/** The calm card is due ten minutes after delivery with no reply (the server says so, or the clock caught up). */
export function nudgeDue(request: SupportRequest, now: number): boolean {
  if (request.status === "undone" || (request.replies?.length ?? 0) > 0) return false;
  const nudge = request.nudge;
  if (!nudge) return false;
  if (nudge.due) return true;
  const at = nudge.due_at ? Date.parse(nudge.due_at) : Number.NaN;
  return !Number.isNaN(at) && now >= at;
}

/** Milliseconds until the calm card is due (null when never). */
export function msUntilNudge(request: SupportRequest, now: number): number | null {
  if (request.status === "undone" || (request.replies?.length ?? 0) > 0) return null;
  const at = request.nudge?.due_at ? Date.parse(request.nudge.due_at) : Number.NaN;
  if (Number.isNaN(at)) return null;
  return Math.max(0, at - now);
}

/** The latest request of mine still worth showing on Ευεξία (the last two hours, not taken back). */
export function latestOpenRequest(requests: SupportRequest[], now: number, windowMs = 2 * 60 * 60_000): SupportRequest | null {
  const open = requests
    .filter((request) => request.role !== "buddy" && request.status !== "undone")
    .filter((request) => now - Date.parse(request.created_at) <= windowMs)
    .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
  return open[0] ?? null;
}

/** Requests a buddy should still see on Αρχική: delivered in the last day. */
export function receivedToShow(requests: SupportRequest[], now: number, windowMs = 24 * 60 * 60_000): SupportRequest[] {
  return requests
    .filter((request) => request.status === "delivered")
    .filter((request) => now - Date.parse(request.created_at) <= windowMs)
    .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
}

/** A phone as a `tel:` href (digits and a leading +). */
export function telHref(phone: string): string {
  const trimmed = phone.trim();
  const digits = trimmed.replace(/[^\d]/g, "");
  return `tel:${trimmed.startsWith("+") ? "+" : ""}${digits}`;
}

/** Monday of the week holding `date` (YYYY-MM-DD, local). */
export function weekStart(date: string): string {
  const day = new Date(`${date}T12:00:00`);
  const offset = (day.getDay() + 6) % 7;
  day.setDate(day.getDate() - offset);
  return isoDate(day);
}

export function shiftWeek(start: string, weeks: number): string {
  const day = new Date(`${start}T12:00:00`);
  day.setDate(day.getDate() + weeks * 7);
  return isoDate(day);
}

function isoDate(day: Date): string {
  return `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, "0")}-${String(day.getDate()).padStart(2, "0")}`;
}
