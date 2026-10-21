import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * ADR-172: Apple Health and Health Connect from the store apps. The app asks
 * the phone for read access, connects the row here, then sends what it read
 * in batches; the server applies Garmin's import rules to them.
 */
type Schemas = components["schemas"];

export type PhoneHealthProvider = Schemas["PhoneHealthRow"]["provider"];
export type PhoneHealthRow = Schemas["PhoneHealthRow"];
export type PhoneHealthConnection = NonNullable<PhoneHealthRow["connection"]>;
export type PhoneHealthSyncPrefs = Schemas["PhoneHealthSyncPrefs"];
export type PhoneHealthIngestRequest = Schemas["PhoneHealthIngestRequest"];
export type PhoneHealthIngestResponse = Schemas["PhoneHealthIngestResponse"];
export type DeviceDisconnectResponse = Schemas["GarminDisconnectResponse"];
export type DeviceDataExport = Schemas["DeviceDataExport"];

const base = (provider: PhoneHealthProvider) => `/me/devices/phone/${provider}`;

export async function connectPhoneHealth(token: string, provider: PhoneHealthProvider, syncPrefs: PhoneHealthSyncPrefs, healthDataConsent: boolean) {
  const body: Schemas["PhoneHealthConnectRequest"] = { sync_prefs: syncPrefs };
  if (healthDataConsent) body.health_data_consent = true;
  return (await apiRequest<{ row: PhoneHealthRow }>(`${base(provider)}/connect`, { method: "POST", token, body })).row;
}

export async function updatePhoneHealth(token: string, provider: PhoneHealthProvider, syncPrefs: PhoneHealthSyncPrefs, healthDataConsent = false) {
  const body: Schemas["PhoneHealthUpdateRequest"] = { sync_prefs: syncPrefs };
  if (healthDataConsent) body.health_data_consent = true;
  return (await apiRequest<{ row: PhoneHealthRow }>(base(provider), { method: "PATCH", token, body })).row;
}

export function ingestPhoneHealth(token: string, provider: PhoneHealthProvider, body: PhoneHealthIngestRequest) {
  return apiRequest<PhoneHealthIngestResponse>(`${base(provider)}/ingest`, { method: "POST", token, body });
}

export function disconnectPhoneHealth(token: string, provider: PhoneHealthProvider, deleteData: boolean) {
  return apiRequest<DeviceDisconnectResponse>(`${base(provider)}?delete_data=${deleteData ? "true" : "false"}`, { method: "DELETE", token });
}

/** Everything connected devices brought in (workouts, daily stats, import log), plan D11. */
export function exportDeviceData(token: string) {
  return apiRequest<DeviceDataExport>("/me/devices/export", { token });
}
