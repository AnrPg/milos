import type { Integration } from "@/api/check-in";
import type {
  DeviceActivity,
  DeviceMetrics,
  DeviceSummary,
  DeviceSyncPrefs,
  GarminConnectRequest,
  GarminConnection,
  GarminRow,
} from "@/api/devices";

/**
 * The pure part of Garmin's screens (ADR-161, board 16 A): what syncs and
 * where it lands, the history window, the progress of the history import,
 * the journal card's line and a watch workout's numbers.
 */

export type SyncPref = "activities" | "sleep" | "weight" | "resting_hr";

/** In the order the connect sheet lists them, each with the place it lands. */
export const SYNC_PREFS: SyncPref[] = ["activities", "sleep", "weight", "resting_hr"];

/** A phone also counts steps (ADR-172). */
export type DevicePref = SyncPref | "steps";

/** Προπονήσεις → Ημερολόγιο, Ύπνος → Ευεξία, Βάρος → Σώμα, Ρυθμός ηρεμίας και βήματα → Πρόοδος. */
export const PREF_DESTINATION: Record<DevicePref, "journal" | "wellness" | "body" | "progress"> = {
  activities: "journal",
  sleep: "wellness",
  weight: "body",
  resting_hr: "progress",
  steps: "progress",
};

export type FullSyncPrefs = Record<SyncPref, boolean>;

export const DEFAULT_SYNC_PREFS: FullSyncPrefs = { activities: true, sleep: true, weight: true, resting_hr: true };

export const DEFAULT_BACKFILL_DAYS = 30;
export const BACKFILL_OPTIONS = [0, 30, 90] as const;

/** Every choice present: a missing one is on, as the server defaults it. */
export function fullPrefs(prefs: DeviceSyncPrefs | null | undefined): FullSyncPrefs {
  return {
    activities: prefs?.activities ?? true,
    sleep: prefs?.sleep ?? true,
    weight: prefs?.weight ?? true,
    resting_hr: prefs?.resting_hr ?? true,
  };
}

export function togglePref(prefs: FullSyncPrefs, pref: SyncPref): FullSyncPrefs {
  return { ...prefs, [pref]: !prefs[pref] };
}

/** The choices that are on, in sheet order. */
export function enabledPrefs(prefs: DeviceSyncPrefs | null | undefined): SyncPref[] {
  const full = fullPrefs(prefs);
  return SYNC_PREFS.filter((pref) => full[pref]);
}

/** Sleep, weight and resting heart rate are health data (plan D8). */
export function bringsHealthData(prefs: DeviceSyncPrefs | null | undefined): boolean {
  const full = fullPrefs(prefs);
  return full.sleep || full.weight || full.resting_hr;
}

/**
 * The consent line shows when health data comes in and the member has not
 * given the consent yet, or when the server asked for it anyway.
 */
export function showsConsentLine(prefs: FullSyncPrefs, consented: boolean, serverAsked: boolean): boolean {
  if (consented) return false;
  return serverAsked || bringsHealthData(prefs);
}

/** Continue is possible once something is chosen and a shown consent is ticked. */
export function canContinue(prefs: FullSyncPrefs, consentShown: boolean, consentTicked: boolean): boolean {
  return enabledPrefs(prefs).length > 0 && (!consentShown || consentTicked);
}

export function connectRequest(prefs: FullSyncPrefs, backfillDays: number, consentTicked: boolean): GarminConnectRequest {
  const days = (BACKFILL_OPTIONS as readonly number[]).includes(backfillDays) ? backfillDays : DEFAULT_BACKFILL_DAYS;
  const body: GarminConnectRequest = { sync_prefs: { ...prefs }, backfill_days: days as 0 | 30 | 90 };
  if (consentTicked) body.health_data_consent = true;
  return body;
}

export function backfillOptions(row: Pick<GarminRow, "backfill_day_options"> | null | undefined): number[] {
  const options = (row?.backfill_day_options ?? []).filter((days) => (BACKFILL_OPTIONS as readonly number[]).includes(days));
  return options.length ? options : [...BACKFILL_OPTIONS];
}

/** The Garmin row inside the devices page's integrations, with the server's defaults filled in. */
export function garminRowOf(integrations: Integration[]): GarminRow | null {
  const row = integrations.find((integration) => integration.provider === "garmin");
  if (!row) return null;
  const configured = row.configured ?? row.status !== "unavailable";
  // The integrations list types `connection` for every provider; Garmin's row carries Garmin's.
  const connection = (row.connection ?? null) as GarminConnection | null;
  return {
    provider: "garmin",
    status: row.status === "native_only" ? "unavailable" : (row.status as GarminRow["status"]),
    configured,
    capability: row.capability ?? (configured ? "available" : "not_configured"),
    sync_prefs: fullPrefs(row.sync_prefs),
    backfill_day_options: row.backfill_day_options ?? [...BACKFILL_OPTIONS],
    connection,
  };
}

export type GarminRowState = "soon" | "disconnected" | "connected" | "reconnect";

export function garminRowState(row: GarminRow): GarminRowState {
  if (row.status === "unavailable" || !row.configured || row.capability === "not_configured") return "soon";
  if (row.connection?.needs_reconnect || row.status === "error" || row.connection?.status === "error") return "reconnect";
  if (row.status === "connected" || row.connection) return "connected";
  return "disconnected";
}

/** The history import's percentage while it runs, or null. */
export function backfillPercent(connection: Pick<GarminConnection, "backfill_status" | "backfill_progress"> | null | undefined): number | null {
  if (!connection || connection.backfill_status !== "running") return null;
  const value = connection.backfill_progress ?? 0;
  return Math.max(0, Math.min(100, Math.round(value)));
}

/** «40%» in the reader's locale. */
export function formatPercent(value: number, locale: string): string {
  return new Intl.NumberFormat(locale, { style: "percent", maximumFractionDigits: 0 }).format(value / 100);
}

/** How long ago, for «Τελευταίος συγχρονισμός πριν 12′». */
export type Ago = { unit: "now" | "minutes" | "hours" | "days"; count: number };

export function agoFrom(iso: string, now: Date = new Date()): Ago {
  const minutes = Math.max(0, Math.floor((now.getTime() - new Date(iso).getTime()) / 60_000));
  if (minutes < 1) return { unit: "now", count: 0 };
  if (minutes < 60) return { unit: "minutes", count: minutes };
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return { unit: "hours", count: hours };
  return { unit: "days", count: Math.floor(hours / 24) };
}

/** Where the OAuth return left us: `?garmin=connected` or `?garmin=error&reason=…`. */
export type GarminReturn = { outcome: "connected" } | { outcome: "error"; reason: string | null };

export function garminReturn(params: URLSearchParams | null | undefined): GarminReturn | null {
  const value = params?.get("garmin");
  if (value === "connected") return { outcome: "connected" };
  if (value === "error") return { outcome: "error", reason: params?.get("reason") || null };
  return null;
}

/** Reasons that get their own words; anything else reads as a generic failure. */
const RETURN_REASONS = [
  "garmin_access_denied",
  "oauth_sign_in_expired",
  "invalid_oauth_state",
  "garmin_unavailable",
  "garmin_account_in_use",
  "garmin_connect_failed",
] as const;

export function returnReasonKey(reason: string | null): string {
  return reason && (RETURN_REASONS as readonly string[]).includes(reason) ? reason : "generic";
}

/** The journal card's parts: «Garmin · 2 νέες προπονήσεις · 1 χρειάζεται επιβεβαίωση». */
export type SummaryPart = { key: "activity" | "sleep" | "weight" | "pending" | "importing"; count: number };

export function summaryParts(summary: DeviceSummary): SummaryPart[] {
  const parts: SummaryPart[] = [];
  const counts = summary.new_counts ?? {};
  if (counts.activity) parts.push({ key: "activity", count: counts.activity });
  if (counts.sleep) parts.push({ key: "sleep", count: counts.sleep });
  if (counts.weight) parts.push({ key: "weight", count: counts.weight });
  if (summary.needs_confirmation) parts.push({ key: "pending", count: summary.needs_confirmation });
  const progress = summary.backfill_progress;
  if (typeof progress === "number" && progress < 100) parts.push({ key: "importing", count: progress });
  return parts;
}

/** The card shows when there is something new or to answer, and while history comes in. */
export function showsDeviceCard(summary: DeviceSummary | null | undefined): boolean {
  if (!summary || !summary.connected) return false;
  const progress = summary.backfill_progress;
  return summary.visible || (typeof progress === "number" && progress < 100);
}

/** «52′», or «1:12:05» past the hour. */
export function formatDuration(seconds: number): string {
  const total = Math.max(0, Math.round(seconds));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (hours === 0) return `${Math.max(1, Math.round(total / 60))}′`;
  const secs = total % 60;
  return `${hours}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
}

/** «6,2 km», or «850 m» under a kilometre. */
export function formatDistance(meters: number, locale: string): string {
  if (meters < 1000) return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(meters)} m`;
  return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 1, minimumFractionDigits: 1 }).format(meters / 1000)} km`;
}

/**
 * The numbers worth a line, in order: distance, duration, average heart rate;
 * the detail adds the maximum. Calories are never shown (vision §8.6).
 */
export type MetricPart = { key: "distance" | "duration" | "avgHr" | "maxHr"; value: string };

export function metricParts(metrics: Pick<DeviceMetrics, "duration_seconds" | "distance_meters" | "avg_heart_rate" | "max_heart_rate">, locale: string, full = false): MetricPart[] {
  const parts: MetricPart[] = [];
  if (typeof metrics.distance_meters === "number" && metrics.distance_meters > 0) parts.push({ key: "distance", value: formatDistance(metrics.distance_meters, locale) });
  parts.push({ key: "duration", value: formatDuration(metrics.duration_seconds) });
  if (typeof metrics.avg_heart_rate === "number") parts.push({ key: "avgHr", value: String(metrics.avg_heart_rate) });
  if (full && typeof metrics.max_heart_rate === "number") parts.push({ key: "maxHr", value: String(metrics.max_heart_rate) });
  return parts;
}

/** The matched entry's line: «από Garmin · 52′ · μέσος 148 bpm» (no distance on a class). */
export function attachmentParts(metrics: DeviceMetrics, locale: string): MetricPart[] {
  return metricParts(metrics, locale).filter((part) => part.key !== "distance" || metrics.sport !== "strength");
}

export const SPORT_ICONS: Record<DeviceActivity["sport"], string> = {
  run: "🏃",
  ride: "🚴",
  swim: "🏊",
  walk: "🚶",
  hike: "🥾",
  strength: "🏋️",
  cardio: "❤️",
  hiit: "⚡",
  yoga: "🧘",
  row: "🚣",
  ski: "⛷️",
  other: "⌚",
};

export function sportIcon(sport: string): string {
  return SPORT_ICONS[sport as DeviceActivity["sport"]] ?? SPORT_ICONS.other;
}

export function isKnownSport(sport: string): sport is DeviceActivity["sport"] {
  return sport in SPORT_ICONS;
}
