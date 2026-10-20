import type { CheckInRules, DeskResult, DoorCode, MemberCode, MemberCodeMode, ScanResult } from "@/api/check-in";

/**
 * Pure rules behind the QR check-in screens (ADR-155): which door code shows
 * now and when to fetch the next batch, what a scan's answer looks like on
 * the phone, what a desk scanner read, and the owner's rule limits.
 */

// -- the door kiosk: rotating through the offline batch ---------------------------

export type DoorFrame = {
  /** The code to show now, or null when the batch has run out (or hasn't started). */
  current: DoorCode | null;
  /** Whole seconds until the next code shows (0 when there is none). */
  secondsUntilRotation: number;
  /** Milliseconds until the screen should change: the next code, or the batch running out. */
  nextChangeInMs: number | null;
  /** When the last code of the batch stops showing, as epoch ms. */
  batchEndsAt: number | null;
};

const at = (iso: string) => new Date(iso).getTime();

/**
 * The code a door shows at `now` (server-corrected epoch ms): the latest code
 * whose `shows_from` has passed and which is still valid. A code stops
 * *showing* when the next one starts; the last one shows until one rotation
 * after it started, so a stale screen never shows a code about to expire.
 */
export function doorFrame(codes: DoorCode[], now: number, rotationSeconds: number): DoorFrame {
  const sorted = [...codes].sort((a, b) => at(a.shows_from) - at(b.shows_from));
  if (sorted.length === 0) return { current: null, secondsUntilRotation: 0, nextChangeInMs: null, batchEndsAt: null };

  const last = sorted[sorted.length - 1];
  const batchEndsAt = Math.min(at(last.shows_from) + rotationSeconds * 1000, at(last.valid_until));
  let index = -1;
  for (let i = 0; i < sorted.length; i += 1) {
    if (at(sorted[i].shows_from) <= now && at(sorted[i].valid_until) > now) index = i;
  }
  if (index === -1 || now >= batchEndsAt) {
    const upcoming = sorted.find((code) => at(code.shows_from) > now);
    return {
      current: null,
      secondsUntilRotation: 0,
      nextChangeInMs: upcoming ? at(upcoming.shows_from) - now : null,
      batchEndsAt,
    };
  }

  const next = sorted[index + 1];
  const changeAt = next ? at(next.shows_from) : batchEndsAt;
  const ms = Math.max(0, changeAt - now);
  return {
    current: sorted[index],
    secondsUntilRotation: next ? Math.ceil(ms / 1000) : 0,
    nextChangeInMs: ms,
    batchEndsAt,
  };
}

/**
 * When to fetch the next batch: once half of what's left of the batch has
 * shown (at least one rotation before it runs out), right away when it has
 * run out. A failed fetch retries sooner, but never more than every 5 s.
 */
export function doorRefetchDelay(batchEndsAt: number | null, now: number, rotationSeconds: number, failed = false) {
  if (batchEndsAt === null) return 0;
  const left = batchEndsAt - now;
  if (left <= 0) return failed ? 5_000 : 0;
  const delay = Math.min(left / 2, left - rotationSeconds * 1000);
  return Math.max(failed ? 5_000 : 1_000, Math.floor(delay));
}

/** The server's clock minus ours, from a response's `server_time` received at `receivedAt`. */
export function clockOffset(serverTime: string | null | undefined, receivedAt: number) {
  if (!serverTime) return 0;
  const server = at(serverTime);
  return Number.isFinite(server) ? server - receivedAt : 0;
}

/** «Μ:ΔΔ» for the countdown under the door QR. */
export function countdownLabel(seconds: number) {
  const whole = Math.max(0, Math.ceil(seconds));
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, "0")}`;
}

// -- the scan landing: an answer → a view -----------------------------------------

export type ScanView =
  | { kind: "checked_in" }
  | { kind: "choose" }
  | { kind: "already" }
  | { kind: "suggestions" }
  | { kind: "nothing" }
  | { kind: "visitor"; trial: boolean }
  | { kind: "poster_member" }
  | { kind: "poster_visitor" };

/**
 * What the phone shows for a scan's answer. The poster path only ever shows
 * the limited outcomes: a check-in, «no booking now», or «not a member».
 */
export function scanView(result: ScanResult, source: "door" | "poster"): ScanView {
  switch (result.outcome) {
    case "checked_in":
      return { kind: "checked_in" };
    case "already_checked_in":
      return { kind: "already" };
    case "choose":
      return { kind: "choose" };
    case "no_booking":
      return { kind: "poster_member" };
    case "visitor": {
      if (source === "poster") return { kind: "poster_visitor" };
      const trial = Boolean(result.trial?.enabled && !result.trial.blocked_reason && (result.trial.classes ?? []).length > 0);
      return { kind: "visitor", trial };
    }
    case "nothing":
    default:
      if (source === "poster") return { kind: "poster_member" };
      return (result.classes ?? []).length > 0 ? { kind: "suggestions" } : { kind: "nothing" };
  }
}

/** Why a member got `nothing`: a message key in the CheckIn namespace. */
export function nothingReasonKey(reason: string | null | undefined) {
  if (!reason) return "scanNothingNoBooking";
  if (reason === "finance_allowance_exhausted") return "scanNothingNoVisits";
  if (["finance_entitlement_inactive", "finance_entitlement_blocked", "finance_profile_missing", "finance_entitlement_plan_missing"].includes(reason))
    return "scanNothingInactive";
  if (reason === "finance_membership_frozen") return "scanNothingFrozen";
  return "scanNothingNoOpenGym";
}

/** Seconds left on the undo, from `undo_until` (server time) and the clock offset. */
export function undoSecondsLeft(undoUntil: string | null | undefined, now: number) {
  if (!undoUntil) return 0;
  return Math.max(0, Math.ceil((at(undoUntil) - now) / 1000));
}

// -- the member's personal code -----------------------------------------------------

/**
 * When to fetch a rotating code again: just after it rotates (a quarter
 * second of slack for the server's window to turn), never sooner than 1 s.
 * A static code never needs fetching again.
 */
export function memberCodeRefetchDelay(code: Pick<MemberCode, "mode" | "seconds_until_rotation" | "rotation_seconds">) {
  if (code.mode !== "rotating") return null;
  const seconds = code.seconds_until_rotation ?? code.rotation_seconds ?? 30;
  return Math.max(1_000, Math.round(seconds * 1000) + 250);
}

// -- the desk scanner: what the camera read ---------------------------------------------

export type ScannedCode = { kind: "member"; code: string } | { kind: "door" } | { kind: "unknown" };

const MEMBER_CODE = /^(?:M1|S1|W1)[A-Za-z0-9_-]{8,250}$/;

/**
 * Personal codes are `M1…` (rotating), `S1…` (static, in the app) and `W1…`
 * (static, on a Wallet card). A door or poster QR opens `/c/…`: someone
 * held up the wrong code.
 */
export function parseScannedCode(raw: string): ScannedCode {
  const text = raw.trim();
  if (MEMBER_CODE.test(text)) return { kind: "member", code: text };
  try {
    const url = new URL(text);
    if (/^\/c\/[^/]+\/(?:p\/)?[^/]+\/?$/.test(url.pathname)) return { kind: "door" };
  } catch {
    // Not a URL.
  }
  return { kind: "unknown" };
}

/** Whether the desk should check in without a tap: auto mode on and the API says it's safe. */
export function shouldAutoCheckIn(result: Pick<DeskResult, "can_auto_check_in" | "checked_in">, auto: boolean) {
  return auto && result.can_auto_check_in && !result.checked_in;
}

// -- Ρυθμίσεις › Check-in ------------------------------------------------------------------

export type RulesDraft = Required<CheckInRules>;
export type RulesError = "window_before" | "window_after" | "rotation";

export const ROTATION_CHOICES = [15, 30, 60] as const;

export const DEFAULT_RULES: RulesDraft = {
  window_before_minutes: 30,
  window_after_minutes: 15,
  open_gym_requires_package: true,
  visitor_trial_offer: true,
  desk_override: false,
  door_rotation_seconds: 30,
  member_code_mode: "rotating",
};

const inWindow = (value: unknown) => Number.isInteger(value) && (value as number) >= 0 && (value as number) <= 120;

/** The owner's limits, mirroring the API's `CheckInRules` (0–120 minutes; 15, 30 or 60 s). */
export function validateRules(draft: RulesDraft): RulesError[] {
  const errors: RulesError[] = [];
  if (!inWindow(draft.window_before_minutes)) errors.push("window_before");
  if (!inWindow(draft.window_after_minutes)) errors.push("window_after");
  if (!(ROTATION_CHOICES as readonly number[]).includes(draft.door_rotation_seconds)) errors.push("rotation");
  return errors;
}

/** Static → rotating revokes every static code and Wallet card of the box, so it asks first. */
export function modeChangeNeedsConfirm(saved: MemberCodeMode, next: MemberCodeMode) {
  return saved === "static" && next === "rotating";
}
