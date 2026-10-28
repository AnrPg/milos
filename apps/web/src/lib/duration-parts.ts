/**
 * ADR-222: booking rules (approval wait, late-cancellation cutoff) are stored
 * as whole minutes; staff enter them as hours plus minutes.
 */
export type DurationParts = { hours: number; minutes: number };

export function splitMinutes(total: number): DurationParts {
  const safe = Math.max(0, Math.round(total));
  return { hours: Math.floor(safe / 60), minutes: safe % 60 };
}

/** Hours and minutes as one stored value, kept inside [min, max]. */
export function joinMinutes(parts: DurationParts, min: number, max: number) {
  const total = Math.max(0, Math.round(parts.hours)) * 60 + Math.max(0, Math.round(parts.minutes));
  return Math.min(max, Math.max(min, total));
}

/** "1 hour 30 minutes", "2 days 3 hours", in the viewer's language. */
export function formatMinutes(total: number, locale: string) {
  const safe = Math.max(0, Math.round(total));
  const days = Math.floor(safe / 1440);
  const hours = Math.floor((safe % 1440) / 60);
  const minutes = safe % 60;
  const unit = (value: number, name: "day" | "hour" | "minute") =>
    new Intl.NumberFormat(locale, { style: "unit", unit: name, unitDisplay: "long" }).format(value);
  const parts = [
    days ? unit(days, "day") : null,
    hours ? unit(hours, "hour") : null,
    minutes || safe === 0 ? unit(minutes, "minute") : null,
  ].filter((part): part is string => part !== null);
  return parts.join(" ");
}
