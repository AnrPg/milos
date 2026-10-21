import type { ConnectedDevices, Integration } from "@/api/check-in";
import type { PhoneHealthConnection, PhoneHealthProvider, PhoneHealthRow } from "@/api/phone-health";
import type { HealthAvailability } from "@/lib/platform/health";

/**
 * The pure part of the phone-health row (ADR-172): Apple Health on an
 * iPhone, Health Connect on Android. What it can bring in, how the row reads
 * where it is seen, and the cached devices page after a change.
 */

export const PHONE_PREFS = ["activities", "sleep", "weight", "resting_hr", "steps"] as const;
export type PhonePref = (typeof PHONE_PREFS)[number];
export type FullPhonePrefs = Record<PhonePref, boolean>;

const HEALTH_PREFS: PhonePref[] = ["sleep", "weight", "resting_hr", "steps"];

/** Every choice present: a missing one is on, as the server defaults it. */
export function fullPhonePrefs(prefs: Partial<Record<PhonePref, boolean>> | null | undefined): FullPhonePrefs {
  return Object.fromEntries(PHONE_PREFS.map((pref) => [pref, prefs?.[pref] ?? true])) as FullPhonePrefs;
}

export function togglePhonePref(prefs: FullPhonePrefs, pref: PhonePref): FullPhonePrefs {
  return { ...prefs, [pref]: !prefs[pref] };
}

export function enabledPhonePrefs(prefs: Partial<Record<PhonePref, boolean>> | null | undefined): PhonePref[] {
  const full = fullPhonePrefs(prefs);
  return PHONE_PREFS.filter((pref) => full[pref]);
}

/** Sleep, weight, resting heart rate and steps are health data (plan D8). */
export function bringsPhoneHealthData(prefs: FullPhonePrefs): boolean {
  return HEALTH_PREFS.some((pref) => prefs[pref]);
}

export function isPhoneProvider(provider: string): provider is PhoneHealthProvider {
  return provider === "apple_health" || provider === "health_connect";
}

/** The phone row inside the devices page's integrations, with the server's defaults filled in. */
export function phoneRowOf(integrations: Integration[], provider: PhoneHealthProvider): PhoneHealthRow | null {
  const row = integrations.find((integration) => integration.provider === provider);
  if (!row) return null;
  const connection = row.status === "connected" ? ((row.connection ?? null) as PhoneHealthConnection | null) : null;
  return {
    provider,
    status: row.status === "connected" ? "connected" : "native_only",
    sync_prefs: fullPhonePrefs(connection?.sync_prefs ?? row.sync_prefs),
    history_days: row.history_days ?? 30,
    connection,
  };
}

/** Swap a phone row inside the cached devices page. */
export function withPhoneRow(current: ConnectedDevices | undefined, row: PhoneHealthRow): ConnectedDevices | undefined {
  if (!current) return current;
  return {
    ...current,
    integrations: current.integrations.map((integration) => (integration.provider === row.provider ? { ...integration, ...row } : integration)),
  };
}

/**
 * - `connect`: inside the app on this phone, not connected yet;
 * - `unavailable`: inside the app, but the phone has no health store
 *   (an iPad, Android without Health Connect);
 * - `connected`: connected, seen in the app on this phone;
 * - `remote`: connected, seen anywhere else (it syncs from the app).
 */
export type PhoneRowState = "connect" | "unavailable" | "connected" | "remote";

export function phoneRowState(row: Pick<PhoneHealthRow, "status">, inApp: boolean, availability: HealthAvailability | null | undefined): PhoneRowState {
  if (row.status === "connected") return inApp ? "connected" : "remote";
  return availability?.available === false ? "unavailable" : "connect";
}

/** Whether the phone row replaces the plain «Με την εφαρμογή» line. */
export function showsPhoneRow(integration: Pick<Integration, "provider" | "status">, appProvider: PhoneHealthProvider | null): boolean {
  if (!isPhoneProvider(integration.provider)) return false;
  return integration.provider === appProvider || integration.status === "connected";
}

/** «Χρειάζεται η εφαρμογή Health Connect» and friends. */
export function unavailableKey(availability: HealthAvailability | null | undefined): string {
  const reason = availability?.reason;
  return ["phoneUnavailable", reason === "not_installed" || reason === "update_required" ? reason : "unsupported"].join("_");
}

export function canInstall(availability: HealthAvailability | null | undefined): boolean {
  return availability?.reason === "not_installed" || availability?.reason === "update_required";
}

/** Any device connected: the page offers the device-data export. */
export function anyDeviceConnected(integrations: Integration[]): boolean {
  return integrations.some((integration) => integration.status === "connected" || integration.status === "error");
}
