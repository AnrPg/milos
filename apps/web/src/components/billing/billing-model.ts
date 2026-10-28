import { visibleBillingAllowances } from "@/components/finance/billing-entitlement-visibility";

/** The three segments of Εγώ › Πληρωμές, kept in `?tab=`. */
export const BILLING_TABS = ["membership", "transactions", "offers"] as const;
export type BillingTab = (typeof BILLING_TABS)[number];

export function billingTab(value: string | null | undefined): BillingTab {
  return (BILLING_TABS as readonly string[]).includes(value ?? "") ? (value as BillingTab) : "membership";
}

/** Above this many entries Συναλλαγές offers a kind filter. */
export const TRANSACTION_FILTER_THRESHOLD = 10;

/** Sum per currency of the entries on screen, in a stable (alphabetical) order. */
export function totalsByCurrency(entries: { amount_cents: number; currency: string }[]) {
  const totals = new Map<string, number>();
  for (const entry of entries) totals.set(entry.currency, (totals.get(entry.currency) ?? 0) + entry.amount_cents);
  return Array.from(totals, ([currency, cents]) => ({ currency, cents })).sort((a, b) => a.currency.localeCompare(b.currency));
}

type Allowance = { limit: number | "unlimited"; remaining: number | "unlimited" };

/**
 * What is left of the package for the summary: the visits allowance when
 * there is one (classes before other kinds), else the first counted one.
 * `null` when the package counts nothing.
 */
export function sessionsLeft(
  entitlement: { allowances?: Record<string, unknown> | null } | null | undefined,
): { unlimited: true } | { unlimited: false; remaining: number; limit: number } | null {
  const entries = visibleBillingAllowances((entitlement?.allowances ?? {}) as Record<string, Allowance | undefined>).filter(
    (entry): entry is [string, Allowance] => Boolean(entry[1]),
  );
  if (entries.length === 0) return null;
  const preferred = entries.find(([key]) => key === "class_visits") ?? entries.find(([key]) => key.includes("visits")) ?? entries[0];
  const usage = preferred[1];
  if (usage.remaining === "unlimited" || usage.limit === "unlimited") return { unlimited: true };
  return { unlimited: false, remaining: usage.remaining, limit: usage.limit };
}

/** How much of the validity window has passed, 0..1, or null without both ends. */
export function validityProgress(startsOn: string | null | undefined, endsOn: string | null | undefined, now: Date) {
  if (!startsOn || !endsOn) return null;
  const start = Date.parse(startsOn);
  const end = Date.parse(endsOn);
  if (Number.isNaN(start) || Number.isNaN(end) || end <= start) return null;
  return Math.min(1, Math.max(0, (now.getTime() - start) / (end - start)));
}

type LeaveFacts = {
  actions: { self_service_leave?: boolean };
  membership?: { leaving_on?: string | null; left_by?: string | null; leave_preview_on?: string | null } | null;
};

export type LeaveState =
  | { kind: "none" }
  | { kind: "leaving"; leavingOn: string; byStaff: boolean }
  | { kind: "can_leave"; previewOn: string | null };

/**
 * ADR-220: where the member stands with leaving this provider: already
 * leaving (on their own or marked by staff), free to leave (with the last
 * day they would keep), or neither (no membership there).
 */
export function leaveState(provider: LeaveFacts): LeaveState {
  const membership = provider.membership;
  if (membership?.leaving_on) {
    return { kind: "leaving", leavingOn: membership.leaving_on, byStaff: membership.left_by === "staff" };
  }
  if (provider.actions.self_service_leave && membership) {
    return { kind: "can_leave", previewOn: membership.leave_preview_on ?? null };
  }
  return { kind: "none" };
}

/** A member can change their mind until their last day has passed (local calendar day). */
export function canStay(leavingOn: string, now: Date): boolean {
  const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
  return leavingOn.slice(0, 10) >= today;
}
