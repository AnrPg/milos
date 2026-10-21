import { describe, expect, it } from "vitest";

import type { DeviceSummary } from "@/api/devices";

import {
  agoFrom,
  attachmentParts,
  backfillOptions,
  backfillPercent,
  bringsHealthData,
  canContinue,
  connectRequest,
  DEFAULT_SYNC_PREFS,
  enabledPrefs,
  formatDistance,
  formatDuration,
  formatPercent,
  fullPrefs,
  garminReturn,
  garminRowOf,
  garminRowState,
  metricParts,
  returnReasonKey,
  showsConsentLine,
  showsDeviceCard,
  sportIcon,
  summaryParts,
  togglePref,
} from "./garmin-model";

const summary = (overrides: Partial<DeviceSummary> = {}): DeviceSummary => ({
  provider: "garmin",
  connected: true,
  visible: true,
  new_total: 2,
  new_counts: { activity: 2, sleep: 0, weight: 0 },
  needs_confirmation: 1,
  backfill_progress: 100,
  ...overrides,
});

describe("sync prefs", () => {
  it("fills missing choices as on and keeps the sheet order", () => {
    expect(fullPrefs({ sleep: false })).toEqual({ activities: true, sleep: false, weight: true, resting_hr: true });
    expect(fullPrefs(null)).toEqual(DEFAULT_SYNC_PREFS);
    expect(enabledPrefs({ activities: true, sleep: false, weight: true, resting_hr: false })).toEqual(["activities", "weight"]);
  });

  it("toggles one choice", () => {
    expect(togglePref(DEFAULT_SYNC_PREFS, "weight").weight).toBe(false);
    expect(togglePref(DEFAULT_SYNC_PREFS, "weight").sleep).toBe(true);
  });

  it("asks for the health-data consent only for sleep, weight or resting heart rate", () => {
    const workoutsOnly = { activities: true, sleep: false, weight: false, resting_hr: false };
    expect(bringsHealthData(workoutsOnly)).toBe(false);
    expect(bringsHealthData(DEFAULT_SYNC_PREFS)).toBe(true);
    expect(showsConsentLine(DEFAULT_SYNC_PREFS, false, false)).toBe(true);
    expect(showsConsentLine(DEFAULT_SYNC_PREFS, true, false)).toBe(false);
    expect(showsConsentLine(workoutsOnly, false, false)).toBe(false);
    expect(showsConsentLine(workoutsOnly, false, true)).toBe(true);
  });

  it("continues once something is chosen and a shown consent is ticked", () => {
    const none = { activities: false, sleep: false, weight: false, resting_hr: false };
    expect(canContinue(none, false, false)).toBe(false);
    expect(canContinue(DEFAULT_SYNC_PREFS, true, false)).toBe(false);
    expect(canContinue(DEFAULT_SYNC_PREFS, true, true)).toBe(true);
    expect(canContinue(DEFAULT_SYNC_PREFS, false, false)).toBe(true);
  });

  it("builds the connect request with the history window and the consent", () => {
    expect(connectRequest(DEFAULT_SYNC_PREFS, 90, true)).toEqual({
      sync_prefs: DEFAULT_SYNC_PREFS,
      backfill_days: 90,
      health_data_consent: true,
    });
    expect(connectRequest(DEFAULT_SYNC_PREFS, 7, false)).toEqual({ sync_prefs: DEFAULT_SYNC_PREFS, backfill_days: 30 });
  });

  it("keeps only the known history windows", () => {
    expect(backfillOptions({ backfill_day_options: [0, 30, 90, 365] })).toEqual([0, 30, 90]);
    expect(backfillOptions(null)).toEqual([0, 30, 90]);
  });
});

describe("the Garmin row", () => {
  it("reads «Σύντομα» when the server has no Garmin credentials", () => {
    const row = garminRowOf([{ provider: "garmin", status: "unavailable" }]);
    expect(row).not.toBeNull();
    expect(garminRowState(row!)).toBe("soon");
  });

  it("tells disconnected, connected and needs-reconnect apart", () => {
    const base = { provider: "garmin" as const, configured: true, capability: "available" as const };
    expect(garminRowState(garminRowOf([{ ...base, status: "disconnected" }])!)).toBe("disconnected");
    const connection = { status: "active" as const, backfill_days: 30 as const, backfill_status: "done" as const, needs_reconnect: false, sync_prefs: {} };
    expect(garminRowState(garminRowOf([{ ...base, status: "connected", connection }])!)).toBe("connected");
    expect(
      garminRowState(garminRowOf([{ ...base, status: "error", connection: { ...connection, status: "error", needs_reconnect: true } }])!),
    ).toBe("reconnect");
  });

  it("is missing when the server lists no Garmin", () => {
    expect(garminRowOf([{ provider: "apple_health", status: "native_only" }])).toBeNull();
  });
});

describe("progress and time", () => {
  it("shows the history import's percentage only while it runs", () => {
    expect(backfillPercent({ backfill_status: "running", backfill_progress: 40 })).toBe(40);
    expect(backfillPercent({ backfill_status: "running", backfill_progress: null })).toBe(0);
    expect(backfillPercent({ backfill_status: "done", backfill_progress: 100 })).toBeNull();
    expect(backfillPercent(null)).toBeNull();
  });

  it("formats a percentage in the locale", () => {
    expect(formatPercent(40, "en")).toBe("40%");
    expect(formatPercent(40, "el")).toMatch(/^40\s?%$/);
  });

  it("says how long ago in the largest whole unit", () => {
    const now = new Date("2026-10-21T12:00:00Z");
    expect(agoFrom("2026-10-21T11:59:40Z", now)).toEqual({ unit: "now", count: 0 });
    expect(agoFrom("2026-10-21T11:48:00Z", now)).toEqual({ unit: "minutes", count: 12 });
    expect(agoFrom("2026-10-21T09:00:00Z", now)).toEqual({ unit: "hours", count: 3 });
    expect(agoFrom("2026-10-19T09:00:00Z", now)).toEqual({ unit: "days", count: 2 });
  });
});

describe("the OAuth return", () => {
  it("reads connected and error with its reason", () => {
    expect(garminReturn(new URLSearchParams("garmin=connected"))).toEqual({ outcome: "connected" });
    expect(garminReturn(new URLSearchParams("garmin=error&reason=garmin_access_denied"))).toEqual({ outcome: "error", reason: "garmin_access_denied" });
    expect(garminReturn(new URLSearchParams("tab=1"))).toBeNull();
  });

  it("words known reasons and falls back for the rest", () => {
    expect(returnReasonKey("oauth_sign_in_expired")).toBe("oauth_sign_in_expired");
    expect(returnReasonKey("boom")).toBe("generic");
    expect(returnReasonKey(null)).toBe("generic");
  });
});

describe("the journal card", () => {
  it("lists new workouts, nights, weigh-ins and what needs an answer", () => {
    expect(summaryParts(summary())).toEqual([
      { key: "activity", count: 2 },
      { key: "pending", count: 1 },
    ]);
    expect(summaryParts(summary({ new_counts: { activity: 0, sleep: 1, weight: 1 }, needs_confirmation: 0, backfill_progress: 40 }))).toEqual([
      { key: "sleep", count: 1 },
      { key: "weight", count: 1 },
      { key: "importing", count: 40 },
    ]);
  });

  it("shows only with something new, or while history comes in", () => {
    expect(showsDeviceCard(summary())).toBe(true);
    expect(showsDeviceCard(summary({ visible: false }))).toBe(false);
    expect(showsDeviceCard(summary({ visible: false, backfill_progress: 40 }))).toBe(true);
    expect(showsDeviceCard(summary({ connected: false }))).toBe(false);
    expect(showsDeviceCard(null)).toBe(false);
  });
});

describe("a watch workout's numbers", () => {
  it("formats duration and distance", () => {
    expect(formatDuration(52 * 60)).toBe("52′");
    expect(formatDuration(20)).toBe("1′");
    expect(formatDuration(3600 + 12 * 60 + 5)).toBe("1:12:05");
    expect(formatDistance(6200, "el")).toBe("6,2 km");
    expect(formatDistance(6200, "en")).toBe("6.2 km");
    expect(formatDistance(850, "en")).toBe("850 m");
  });

  it("orders distance, duration and average heart rate; the detail adds the maximum and never calories", () => {
    const run = { duration_seconds: 34 * 60, distance_meters: 6200, avg_heart_rate: 151, max_heart_rate: 178, calories: 420 };
    expect(metricParts(run, "en").map((part) => part.key)).toEqual(["distance", "duration", "avgHr"]);
    expect(metricParts(run, "en", true).map((part) => part.key)).toEqual(["distance", "duration", "avgHr", "maxHr"]);
    expect(metricParts({ duration_seconds: 600 }, "en")).toEqual([{ key: "duration", value: "10′" }]);
  });

  it("drops distance on a strength class", () => {
    const parts = attachmentParts({ id: "a", provider: "garmin", sport: "strength", started_at: "2026-10-21T18:00:00Z", duration_seconds: 3120, distance_meters: 120, avg_heart_rate: 148 }, "el");
    expect(parts).toEqual([
      { key: "duration", value: "52′" },
      { key: "avgHr", value: "148" },
    ]);
  });

  it("has an icon for every sport and a watch for the unknown", () => {
    expect(sportIcon("run")).toBe("🏃");
    expect(sportIcon("curling")).toBe("⌚");
  });
});
