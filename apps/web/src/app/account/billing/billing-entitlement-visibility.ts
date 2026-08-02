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
