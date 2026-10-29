import type { FinanceRecord } from "@/api/finance";

/**
 * ADR-274: a member's status is worked out from their subscription and what
 * they owe; staff may set it (or a subscription's last day) by hand, and every
 * such change is kept with who made it, when and what it replaced.
 */

/** Every status the ledger shows, in the order the server weighs them. */
export const MEMBER_STATUSES = [
  "cancelled",
  "paused",
  "expired",
  "overdue",
  "unpaid",
  "leaving",
  "expiring",
  "trial",
  "comped",
  "active",
  "no_package",
] as const;

export type MemberStatus = (typeof MEMBER_STATUSES)[number];

/** The statuses staff may set by hand (leaving has its own flow, ADR-220). */
export const OVERRIDABLE_STATUSES = ["active", "trial", "comped", "paused", "expired", "cancelled"] as const;

export type StatusTone = "good" | "warn" | "bad" | "info" | "off";

const TONES: Record<MemberStatus, StatusTone> = {
  active: "good",
  unpaid: "warn",
  expiring: "warn",
  overdue: "bad",
  trial: "info",
  comped: "info",
  paused: "off",
  expired: "off",
  leaving: "off",
  cancelled: "off",
  no_package: "off",
};

export function statusTone(status: string): StatusTone {
  return TONES[status as MemberStatus] ?? "off";
}

/** The pill colours of a tone, from theme tokens only. */
export function toneStyle(tone: StatusTone) {
  const colour = {
    good: "var(--success)",
    warn: "var(--warning)",
    bad: "var(--danger)",
    info: "var(--primary)",
    off: "var(--muted)",
  }[tone];
  return {
    background: `color-mix(in srgb, ${colour} 14%, transparent)`,
    color: colour,
    border: `1px solid color-mix(in srgb, ${colour} 28%, transparent)`,
  };
}

export interface ValueOverride {
  id: string;
  field: "status" | "ends_on";
  subject_id: string;
  computed_value: string | null;
  value: string;
  reason: string | null;
  set_by_name: string | null;
  set_at: string;
  ended_at?: string | null;
  ended_by_name?: string | null;
  end_reason?: "reset" | "replaced" | "lapsed" | null;
}

function record(value: unknown): FinanceRecord | null {
  return value && typeof value === "object" ? (value as FinanceRecord) : null;
}

function text(value: unknown): string {
  return value === null || value === undefined ? "" : String(value);
}

/** What staff see for a ledger row (the stored status until the server works it out). */
export function shownStatus(member: FinanceRecord): string {
  const membership = record(member.membership);
  return text(membership?.status_shown) || text(membership?.status);
}

/** The override in force for a field (for `ends_on`, of that subscription). */
export function overrideFor(
  overrides: unknown,
  field: ValueOverride["field"],
  subjectId?: string | null,
): ValueOverride | null {
  if (!Array.isArray(overrides)) return null;
  return (
    (overrides as ValueOverride[]).find(
      (override) => override.field === field && !override.ended_at && (!subjectId || override.subject_id === subjectId),
    ) ?? null
  );
}

/**
 * The last day «Λήγει» shows: the subscription's current period (which
 * renews, or ends there), else the profile's own end date.
 */
export function memberEndsOn(member: FinanceRecord): { date: string; renews: boolean } {
  const subscription = record(member.active_package_subscription);
  const period = record(subscription?.current_period);
  const date =
    text(period?.ends_on) || text(subscription?.ends_on) || text(record(member.membership)?.expires_on);
  return { date: date.slice(0, 10), renews: period?.renews === true };
}
