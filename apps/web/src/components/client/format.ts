import { zonedText } from "@/lib/zoned-time";

/** Long date for a `YYYY-MM-DD` calendar day, independent of the viewer's zone. */
export function formatDay(day: string, locale: string, options?: Intl.DateTimeFormatOptions): string {
  const date = new Date(`${day}T12:00:00Z`);
  if (Number.isNaN(date.getTime())) return day;
  return date.toLocaleDateString(locale, {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
    ...options,
    timeZone: "UTC",
  });
}

/** «19:00»; with an organiser's zone (ADR-177), on its clock, its city added when the viewer's differs. */
export function formatTime(iso: string, locale: string, timeZone?: string | null): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  if (timeZone) return zonedText(date, timeZone, locale, "time");
  return date.toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" });
}

export function formatDateTime(iso: string | null | undefined, locale: string): string {
  if (!iso) return "";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString(locale, { dateStyle: "medium", timeStyle: "short" });
}
