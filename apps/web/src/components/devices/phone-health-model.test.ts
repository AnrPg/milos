import { describe, expect, it } from "vitest";

import type { ConnectedDevices, Integration } from "@/api/check-in";

import {
  anyDeviceConnected,
  bringsPhoneHealthData,
  canInstall,
  enabledPhonePrefs,
  fullPhonePrefs,
  phoneRowOf,
  phoneRowState,
  showsPhoneRow,
  togglePhonePref,
  unavailableKey,
  withPhoneRow,
} from "./phone-health-model";

const integration = (fields: Record<string, unknown>) => fields as unknown as Integration;

describe("phone-health-model", () => {
  it("fills missing prefs as on and lists the enabled ones", () => {
    const prefs = fullPhonePrefs({ sleep: false });
    expect(prefs).toEqual({ activities: true, sleep: false, weight: true, resting_hr: true, steps: true });
    expect(enabledPhonePrefs(togglePhonePref(prefs, "steps"))).toEqual(["activities", "weight", "resting_hr"]);
  });

  it("counts everything but workouts as health data", () => {
    const only = (pref: string) => fullPhonePrefs({ activities: false, sleep: false, weight: false, resting_hr: false, steps: false, [pref]: true });
    expect(bringsPhoneHealthData(only("activities"))).toBe(false);
    expect(bringsPhoneHealthData(only("steps"))).toBe(true);
    expect(bringsPhoneHealthData(only("sleep"))).toBe(true);
  });

  it("reads the phone row with the server defaults", () => {
    const rows = [integration({ provider: "apple_health", status: "native_only", sync_prefs: null })];
    expect(phoneRowOf(rows, "apple_health")).toMatchObject({ status: "native_only", history_days: 30, connection: null });
    expect(phoneRowOf(rows, "health_connect")).toBeNull();
    const connected = [
      integration({ provider: "health_connect", status: "connected", history_days: 30, connection: { sync_prefs: { steps: false }, last_synced_at: null } }),
    ];
    expect(phoneRowOf(connected, "health_connect")?.sync_prefs.steps).toBe(false);
  });

  it("swaps a row inside the cached page", () => {
    const page = { integrations: [integration({ provider: "garmin", status: "available" }), integration({ provider: "apple_health", status: "native_only" })] } as unknown as ConnectedDevices;
    const next = withPhoneRow(page, { provider: "apple_health", status: "connected", sync_prefs: fullPhonePrefs(null), history_days: 30, connection: null });
    expect(next?.integrations.map((row) => row.status)).toEqual(["available", "connected"]);
    expect(withPhoneRow(undefined, { provider: "apple_health", status: "connected", sync_prefs: fullPhonePrefs(null), history_days: 30, connection: null })).toBeUndefined();
  });

  it("decides how the row reads where it is seen", () => {
    expect(phoneRowState({ status: "connected" }, true, null)).toBe("connected");
    expect(phoneRowState({ status: "connected" }, false, null)).toBe("remote");
    expect(phoneRowState({ status: "native_only" }, true, { available: false, reason: "not_installed" })).toBe("unavailable");
    expect(phoneRowState({ status: "native_only" }, true, { available: true })).toBe("connect");
  });

  it("shows the phone row in its own app or once connected", () => {
    expect(showsPhoneRow({ provider: "apple_health", status: "native_only" }, "apple_health")).toBe(true);
    expect(showsPhoneRow({ provider: "health_connect", status: "native_only" }, "apple_health")).toBe(false);
    expect(showsPhoneRow({ provider: "health_connect", status: "connected" }, null)).toBe(true);
    expect(showsPhoneRow({ provider: "garmin", status: "connected" }, null)).toBe(false);
  });

  it("explains why it is unavailable and offers the installer", () => {
    expect(unavailableKey({ available: false, reason: "not_installed" })).toBe("phoneUnavailable_not_installed");
    expect(unavailableKey({ available: false })).toBe("phoneUnavailable_unsupported");
    expect(canInstall({ available: false, reason: "update_required" })).toBe(true);
    expect(canInstall({ available: false, reason: "unsupported" })).toBe(false);
  });

  it("offers the export once any device is connected", () => {
    expect(anyDeviceConnected([integration({ provider: "garmin", status: "available" })])).toBe(false);
    expect(anyDeviceConnected([integration({ provider: "garmin", status: "error" })])).toBe(true);
  });
});
