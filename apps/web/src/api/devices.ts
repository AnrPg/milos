import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";
import type { ConnectedDevices } from "@/api/check-in";

/**
 * Εγώ › Συνδεδεμένες συσκευές and the journal's device card (ADR-161, P2-M13):
 * Garmin's row, connecting and disconnecting it, «Συγχρονισμός τώρα», the
 * workouts that wait for an answer and the card above Ροή.
 */
type Schemas = components["schemas"];

export type GarminRow = Schemas["GarminDeviceRow"];
export type GarminConnection = NonNullable<GarminRow["connection"]>;
export type DeviceSyncPrefs = Schemas["DeviceSyncPrefs"];
export type GarminConnectRequest = Schemas["GarminConnectRequest"];
export type GarminConnectResponse = Schemas["GarminConnectResponse"];
export type GarminDisconnectResponse = Schemas["GarminDisconnectResponse"];
export type DeviceSummary = Schemas["DeviceSummary"];
export type DeviceActivity = Schemas["DeviceActivity"];
export type DeviceActivityCandidate = Schemas["DeviceActivityCandidate"];
export type DevicePendingImport = Schemas["DevicePendingImports"]["imports"][number];
export type DeviceSport = DeviceActivity["sport"];

/** The watch's numbers on a class or workout they merged into (`device` on execution and training-log entries). */
export type DeviceMetrics = NonNullable<Schemas["DeviceMetrics"]>;
export type DailyStats = Schemas["DailyStats"];
export type DailyStatPoint = DailyStats["points"][number];
export type DailyStatsRange = DailyStats["range"];

export const DEVICES_KEY = ["me", "devices"] as const;
export const DEVICE_SUMMARY_KEY = ["me", "devices", "summary"] as const;
export const DEVICE_PENDING_KEY = ["me", "devices", "garmin", "pending"] as const;
export const dailyStatsKey = (range: DailyStatsRange) => ["me", "daily-stats", "resting_hr", range] as const;

export function fetchDevices(token: string) {
  return apiRequest<ConnectedDevices>("/me/devices", { token });
}

export function connectGarmin(token: string, body: GarminConnectRequest) {
  return apiRequest<GarminConnectResponse>("/me/devices/garmin/connect", { method: "POST", token, body });
}

export async function updateGarmin(token: string, syncPrefs: DeviceSyncPrefs, healthDataConsent = false) {
  const body: Schemas["GarminUpdateRequest"] = { sync_prefs: syncPrefs };
  if (healthDataConsent) body.health_data_consent = true;
  return (await apiRequest<{ garmin: GarminRow }>("/me/devices/garmin", { method: "PATCH", token, body })).garmin;
}

export async function syncGarmin(token: string) {
  return (await apiRequest<{ garmin: GarminRow }>("/me/devices/garmin/sync", { method: "POST", token })).garmin;
}

export function disconnectGarmin(token: string, deleteData: boolean) {
  return apiRequest<GarminDisconnectResponse>(`/me/devices/garmin?delete_data=${deleteData ? "true" : "false"}`, {
    method: "DELETE",
    token,
  });
}

/** Πρόοδος: the member's own resting heart rate from a device. */
export function fetchRestingHeartRate(token: string, range: DailyStatsRange = "3m") {
  return apiRequest<DailyStats>(`/me/daily-stats?metric=resting_hr&range=${range}`, { token });
}

export function fetchDeviceSummary(token: string) {
  return apiRequest<DeviceSummary>("/me/devices/summary", { token });
}

export function markDeviceSummarySeen(token: string) {
  return apiRequest<DeviceSummary>("/me/devices/summary/seen", { method: "POST", token });
}

export async function fetchGarminPending(token: string) {
  return (await apiRequest<Schemas["DevicePendingImports"]>("/me/devices/garmin/pending", { token })).imports;
}

export async function confirmDeviceImport(token: string, importId: string, answer: { target_id: string } | { as_new: true }) {
  return (
    await apiRequest<{ activity: DeviceActivity }>(`/me/device-imports/${importId}/confirm`, { method: "POST", token, body: answer })
  ).activity;
}
