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

/**
 * The watch's numbers on a class or workout they merged into (`device` on
 * execution and training-log feed entries; the feed's entry is untyped).
 */
export type DeviceMetrics = {
  id: string;
  provider: string;
  sport: DeviceSport | string;
  started_at: string;
  duration_seconds: number;
  distance_meters?: number | null;
  avg_heart_rate?: number | null;
  max_heart_rate?: number | null;
  calories?: number | null;
};

export const DEVICES_KEY = ["me", "devices"] as const;
export const DEVICE_SUMMARY_KEY = ["me", "devices", "summary"] as const;
export const DEVICE_PENDING_KEY = ["me", "devices", "garmin", "pending"] as const;

export function fetchDevices(token: string) {
  return apiRequest<ConnectedDevices>("/me/devices", { token });
}

export function connectGarmin(token: string, body: GarminConnectRequest) {
  return apiRequest<GarminConnectResponse>("/me/devices/garmin/connect", { method: "POST", token, body });
}

export async function updateGarmin(token: string, syncPrefs: DeviceSyncPrefs) {
  return (await apiRequest<{ garmin: GarminRow }>("/me/devices/garmin", { method: "PATCH", token, body: { sync_prefs: syncPrefs } })).garmin;
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
