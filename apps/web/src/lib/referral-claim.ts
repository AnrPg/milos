import type { ReferralChannel, ReferralClaim } from "@/api/referrals";

/**
 * Invites a friend opened, kept on their device until they're signed in
 * (ADR-156, board 11 Q1: kept 30 days, then the member can send it again). Invite pages and event links
 * save them; once there is a session each is claimed once, oldest first, and
 * forgotten, so signing up later, from another page, still credits the
 * member who invited them. The server keeps the first invite per box (Q4),
 * so claiming them in the order they were opened keeps that rule.
 */
export const PENDING_REFERRAL_KEY = "milos:pending-referrals";
export const PENDING_REFERRAL_DAYS = 30;
const MAX_PENDING = 5;

export type PendingReferral = {
  code: string;
  channel: ReferralChannel;
  event_id: string | null;
  new_account: boolean;
  saved_at: string;
};

const DAY_MS = 24 * 60 * 60 * 1000;
const CHANNELS: ReferralChannel[] = ["link", "qr", "event", "guest_pass"];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function storage(): Storage | null {
  try {
    return typeof window === "undefined" ? null : window.localStorage;
  } catch {
    return null;
  }
}

/** The code as the server reads it (upper case, no spaces or dashes), to compare two links. */
export function codeKey(code: string) {
  return code.toUpperCase().replace(/[\s_-]/g, "");
}

/** How a visit to `/r/<code>` arrived: `?via=qr` from the QR, `?event=<id>` from an event invite. */
export function inviteChannel(params: { via?: string | null; event?: string | null }) {
  const eventId = params.event && UUID.test(params.event) ? params.event : null;
  if (eventId) return { channel: "event" as const, event_id: eventId };
  return { channel: params.via === "qr" ? ("qr" as const) : ("link" as const), event_id: null };
}

/** Keeps an invite; opening the same code again keeps its first visit and adds what it now carries. */
export function rememberReferral(
  invite: { code: string; channel: ReferralChannel; event_id: string | null },
  now: Date = new Date(),
) {
  const entries = readPendingReferrals(now);
  const index = entries.findIndex((entry) => codeKey(entry.code) === codeKey(invite.code));
  if (index >= 0) {
    const current = entries[index];
    entries[index] = {
      ...current,
      channel: invite.event_id ? invite.channel : current.channel,
      event_id: invite.event_id ?? current.event_id,
    };
  } else {
    entries.push({ ...invite, new_account: false, saved_at: now.toISOString() });
  }
  write(entries.slice(-MAX_PENDING));
}

/**
 * Registration marks the kept invites as the ones that brought a new account,
 * before the session lands (the claim runs as soon as it does); a failed
 * registration takes the mark back.
 */
export function markReferralNewAccount(value = true) {
  const entries = readPendingReferrals();
  if (entries.length === 0) return;
  write(entries.map((entry) => ({ ...entry, new_account: value })));
}

export function readPendingReferrals(now: Date = new Date()): PendingReferral[] {
  const store = storage();
  if (!store) return [];
  let raw: string | null = null;
  try {
    raw = store.getItem(PENDING_REFERRAL_KEY);
  } catch {
    return [];
  }
  if (!raw) return [];
  const parsed = parseAll(raw);
  const fresh = parsed.filter((entry) => now.getTime() - new Date(entry.saved_at).getTime() <= PENDING_REFERRAL_DAYS * DAY_MS);
  if (fresh.length !== parsed.length || parsed.length === 0) write(fresh);
  return fresh;
}

export function forgetReferral(code: string) {
  write(readPendingReferrals().filter((entry) => codeKey(entry.code) !== codeKey(code)));
}

export function claimBody(entry: Pick<PendingReferral, "code" | "channel" | "event_id" | "new_account">): ReferralClaim {
  return {
    code: entry.code,
    channel: entry.channel,
    ...(entry.event_id ? { event_id: entry.event_id } : {}),
    ...(entry.new_account ? { new_account: true } : {}),
  };
}

/** A claim the server answered (any 4xx included) is settled; only a network or server failure is retried later. */
export function claimSettled(error: unknown) {
  const status = (error as { status?: unknown } | null)?.status;
  return typeof status === "number" && status >= 400 && status < 500;
}

function write(entries: PendingReferral[]) {
  const store = storage();
  if (!store) return;
  try {
    if (entries.length === 0) store.removeItem(PENDING_REFERRAL_KEY);
    else store.setItem(PENDING_REFERRAL_KEY, JSON.stringify(entries));
  } catch {}
}

function parseAll(raw: string): PendingReferral[] {
  try {
    const value: unknown = JSON.parse(raw);
    return Array.isArray(value) ? value.flatMap((entry) => parse(entry)) : [];
  } catch {
    return [];
  }
}

function parse(value: unknown): PendingReferral[] {
  if (!value || typeof value !== "object") return [];
  const entry = value as Partial<PendingReferral>;
  if (typeof entry.code !== "string" || !entry.code || entry.code.length > 32) return [];
  if (!entry.channel || !CHANNELS.includes(entry.channel)) return [];
  if (typeof entry.saved_at !== "string" || Number.isNaN(new Date(entry.saved_at).getTime())) return [];
  return [
    {
      code: entry.code,
      channel: entry.channel,
      event_id: typeof entry.event_id === "string" && UUID.test(entry.event_id) ? entry.event_id : null,
      new_account: entry.new_account === true,
      saved_at: entry.saved_at,
    },
  ];
}
