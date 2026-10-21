import { ApiError } from "@/api/client";

/** Error codes the season endpoints answer with (ADR-167); each has a Seasons.error_<code> message. */
export const SEASON_ERROR_CODES = [
  "season_not_open",
  "season_full",
  "season_already_requested",
  "season_place_confirmed",
  "invalid_season_transition",
  "invalid_season_status",
  "season_closed",
  "season_schedule_locked",
  "capacity_below_participants",
  "season_has_enrollments",
  "programme_workout_unavailable",
  "not_a_coach",
] as const;

type SeasonErrorCode = (typeof SEASON_ERROR_CODES)[number];

export function seasonErrorKey(error: unknown): `error_${SeasonErrorCode}` | "error_generic" {
  const code = error instanceof ApiError ? error.payload.code : undefined;
  return code && (SEASON_ERROR_CODES as readonly string[]).includes(code)
    ? (`error_${code}` as `error_${SeasonErrorCode}`)
    : "error_generic";
}

export function seasonMoney(locale: string, cents: number | null | undefined, currency?: string | null) {
  const amount = typeof cents === "number" && Number.isFinite(cents) ? cents : 0;
  try {
    return new Intl.NumberFormat(locale, { style: "currency", currency: currency || "EUR" }).format(amount / 100);
  } catch {
    return (amount / 100).toFixed(2);
  }
}

export function seasonDate(locale: string, iso: string | null | undefined) {
  if (!iso) return "";
  const date = new Date(`${iso.slice(0, 10)}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleDateString(locale, { day: "numeric", month: "short", timeZone: "UTC" });
}

/** "3 Νοε – 28 Δεκ" from a start and an end date. */
export function seasonRange(locale: string, startsOn: string | null | undefined, endsOn: string | null | undefined) {
  const start = seasonDate(locale, startsOn);
  const end = seasonDate(locale, endsOn);
  return start && end ? `${start} – ${end}` : start;
}

/** Status colours shared by the builder and the member list. */
export function statusTone(status: string | null | undefined): string {
  switch (status) {
    case "active":
    case "running":
    case "published":
      return "var(--success)";
    case "requested":
    case "waitlisted":
    case "draft":
      return "var(--warning)";
    case "declined":
    case "cancelled":
      return "var(--danger)";
    default:
      return "var(--dim)";
  }
}
