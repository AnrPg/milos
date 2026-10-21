import { afterEach, describe, expect, it, vi } from "vitest";

import type { PhoneHealthRow } from "@/api/phone-health";

const ingest = vi.fn();
vi.mock("@/api/phone-health", () => ({ ingestPhoneHealth: (...args: unknown[]) => ingest(...args) }));

import { autoSyncDue, enabledKinds, grantedPrefs, newCount, phoneHealthProvider, plainHealthPlugin, syncPhoneHealth, syncWindow, type PaleeHealthPlugin } from "./health";

function bridge(platform: "ios" | "android", plugins: string[]) {
  (window as unknown as { Capacitor?: unknown }).Capacitor = {
    isNativePlatform: () => true,
    getPlatform: () => platform,
    isPluginAvailable: (name: string) => plugins.includes(name),
  };
}

const row = (overrides: Partial<PhoneHealthRow> = {}): PhoneHealthRow => ({
  provider: "apple_health",
  status: "connected",
  history_days: 30,
  sync_prefs: { activities: true, sleep: true, weight: true, resting_hr: true, steps: true },
  connection: {
    status: "active",
    sync_prefs: { activities: true, sleep: false, weight: true, resting_hr: true, steps: true },
    last_synced_at: null,
    read_from: "2026-10-18T08:00:00Z",
  },
  ...overrides,
});

afterEach(() => {
  delete (window as unknown as { Capacitor?: unknown }).Capacitor;
  ingest.mockReset();
});

describe("phoneHealthProvider", () => {
  it("is this phone's provider only when the plugin ships in the app", () => {
    expect(phoneHealthProvider()).toBeNull();
    bridge("ios", ["PaleeHealth"]);
    expect(phoneHealthProvider()).toBe("apple_health");
    bridge("android", ["PaleeHealth"]);
    expect(phoneHealthProvider()).toBe("health_connect");
    bridge("android", []);
    expect(phoneHealthProvider()).toBeNull();
  });
});

describe("choices and permissions", () => {
  it("lists the kinds that are on", () => {
    expect(enabledKinds({ activities: true, sleep: false })).toEqual(["activities", "weight", "resting_hr", "steps"]);
  });

  it("switches off what Android refused and trusts iOS's silence", () => {
    const prefs = { activities: true, sleep: true, weight: false, resting_hr: true, steps: true };
    expect(grantedPrefs(prefs, { asked: ["activities", "sleep"], granted: ["activities"] })).toEqual({
      activities: true,
      sleep: false,
      weight: false,
      resting_hr: false,
      steps: false,
    });
    expect(grantedPrefs(prefs, { asked: ["activities"], granted: null })).toBe(prefs);
  });
});

describe("when and what to read", () => {
  const now = new Date("2026-10-21T10:00:00Z");

  it("syncs on its own at most every 15 minutes", () => {
    expect(autoSyncDue(null, now)).toBe(true);
    expect(autoSyncDue("2026-10-21T09:50:00Z", now)).toBe(false);
    expect(autoSyncDue("2026-10-21T09:45:00Z", now)).toBe(true);
  });

  it("reads from where the server says, else 30 days back", () => {
    expect(syncWindow(row(), now)).toEqual({ from: "2026-10-18T08:00:00.000Z", to: "2026-10-21T10:00:00.000Z" });
    expect(syncWindow(row({ connection: null }), now).from).toBe("2026-09-21T10:00:00.000Z");
  });
});

describe("syncPhoneHealth", () => {
  it("reads the chosen kinds once and sends the batches", async () => {
    const plugin: PaleeHealthPlugin = {
      availability: vi.fn(),
      requestAuthorization: vi.fn(),
      read: vi.fn().mockResolvedValue({
        workouts: [{ id: "w", start: "2026-10-20T05:00:00Z", end: "2026-10-20T05:30:00Z", type: "RUNNING" }],
        steps: [{ date: "2026-10-20", count: 4000 }],
      }),
    };
    ingest.mockResolvedValue({ counts: { imported: 2 }, row: row() });

    const first = syncPhoneHealth("token", row(), plugin, new Date("2026-10-21T10:00:00Z"));
    const second = syncPhoneHealth("token", row(), plugin);
    expect(second).toBe(first);
    const result = await first;

    expect(plugin.read).toHaveBeenCalledTimes(1);
    expect(plugin.read).toHaveBeenCalledWith({
      kinds: ["activities", "weight", "resting_hr", "steps"],
      from: "2026-10-18T08:00:00.000Z",
      to: "2026-10-21T10:00:00.000Z",
    });
    expect(ingest).toHaveBeenCalledWith("token", "apple_health", {
      activities: [{ id: "w", type: "RUNNING", start: "2026-10-20T05:00:00+00:00", end: "2026-10-20T05:30:00+00:00" }],
      dailies: [{ date: "2026-10-20", steps: 4000 }],
    });
    expect(result.counts).toEqual({ imported: 2 });
    expect(newCount(result.counts)).toBe(2);
  });

  it("still reports an empty read so the last sync moves on", async () => {
    const plugin = { availability: vi.fn(), requestAuthorization: vi.fn(), read: vi.fn().mockResolvedValue({}) } as PaleeHealthPlugin;
    ingest.mockResolvedValue({ counts: {}, row: row() });
    await syncPhoneHealth("token", row(), plugin);
    expect(ingest).toHaveBeenCalledWith("token", "apple_health", {});
  });
});

describe("plainHealthPlugin", () => {
  it("lets a promise resolve to Capacitor's thenable plugin proxy", async () => {
    // Like Capacitor's proxy: every property, `then` included, is a method.
    const native = new Proxy({}, { get: (_target, prop) => (prop === "availability" ? async () => ({ available: true }) : () => new Promise(() => undefined)) });
    const plugin = await Promise.resolve(plainHealthPlugin(native as PaleeHealthPlugin));
    await expect(plugin.availability()).resolves.toEqual({ available: true });
  });
});
