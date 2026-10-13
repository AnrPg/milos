import type { MembershipFreeze } from "@/api/admin-users";

const DAY_MS = 86_400_000;

function utcDay(value: string) {
  const time = Date.parse(`${value.slice(0, 10)}T00:00:00Z`);
  return Number.isNaN(time) ? null : time;
}

/** Inclusive length of a freeze in days, matching the API (0 when the range is invalid). */
export function freezeDays(startsOn: string, endsOn: string) {
  const start = utcDay(startsOn);
  const end = utcDay(endsOn);
  if (start === null || end === null || end < start) return 0;
  return Math.round((end - start) / DAY_MS) + 1;
}

/**
 * Freeze days already used in a calendar year. Cancelled freezes do not count,
 * and freezes crossing New Year only count their days inside `year` (ADR-097).
 */
export function freezeDaysUsedInYear(freezes: MembershipFreeze[], year: number) {
  return freezes
    .filter((freeze) => !freeze.cancelled_at)
    .reduce((total, freeze) => {
      const first = freeze.starts_on.slice(0, 10) < `${year}-01-01` ? `${year}-01-01` : freeze.starts_on;
      const last = freeze.ends_on.slice(0, 10) > `${year}-12-31` ? `${year}-12-31` : freeze.ends_on;
      return total + freezeDays(first, last);
    }, 0);
}

/** Yearly freeze days of the member's active package (0 when it has none). */
export function freezeDaysPerYear(subscriptions: Array<Record<string, unknown>>) {
  return subscriptions
    .filter((subscription) => subscription.status === "active")
    .reduce((max, subscription) => {
      const fields = subscription.fields as Record<string, unknown> | undefined;
      const days = Number(fields?.["perks.freeze_days_per_year"] ?? 0);
      return Number.isFinite(days) && days > max ? days : max;
    }, 0);
}

export type FreezeState = "cancelled" | "upcoming" | "active" | "ended";

export function freezeState(freeze: MembershipFreeze, today: string): FreezeState {
  if (freeze.cancelled_at) return "cancelled";
  if (today < freeze.starts_on.slice(0, 10)) return "upcoming";
  if (today > freeze.ends_on.slice(0, 10)) return "ended";
  return "active";
}

/** Today's date as YYYY-MM-DD in the browser's time zone. */
export function localIsoDate(date = new Date()) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 10);
}
