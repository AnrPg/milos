const HIDDEN_CUSTOMER_CHANNELS = new Set(["workout_library"]);
const HIDDEN_CUSTOMER_ALLOWANCES = new Set(["coaching_touchpoints"]);

export function visibleBillingChannels(channels: string[]): string[] {
  return channels.filter((channel) => !HIDDEN_CUSTOMER_CHANNELS.has(channel));
}

export function visibleBillingAllowances<T>(allowances: Record<string, T>): [string, T][] {
  return Object.entries(allowances).filter(
    ([allowance]) => !HIDDEN_CUSTOMER_ALLOWANCES.has(allowance),
  );
}

export function shouldShowAllowanceQuota(usage: {
  limit?: number | "unlimited" | string | null;
  remaining?: number | "unlimited" | string | null;
}) {
  return usage.limit !== "unlimited" || usage.remaining !== "unlimited";
}

/** Freezes worth showing to the member: not cancelled, newest first (ADR-097). */
export function visibleBillingFreezes<
  T extends { starts_on: string; cancelled_at: string | null },
>(freezes: T[]): T[] {
  return freezes
    .filter((freeze) => !freeze.cancelled_at)
    .sort((a, b) => b.starts_on.localeCompare(a.starts_on));
}
