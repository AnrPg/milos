import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { GeofenceRegion } from "@/api/check-in";

const issue = vi.fn();
const revoke = vi.fn();
vi.mock("@/api/widgets", () => ({
  issueWidgetToken: (...args: unknown[]) => issue(...args),
  revokeWidgetToken: (...args: unknown[]) => revoke(...args),
}));

import { forgetGeofences, reminderEnabled, setReminderEnabled, syncGeofences, toNativeRegions, type PaleeGeofencePlugin } from "./geofence";
import { nfcWriter, writeNfcTag, type PaleeNfcPlugin } from "./nfc";
import { forgetWidgets, renewalDue, syncWidgets, WIDGET_PATHS, type PaleeWidgetsPlugin, type WidgetLabels } from "./widgets";

function bridge(platform: "ios" | "android", plugins: string[]) {
  (window as unknown as { Capacitor?: unknown }).Capacitor = {
    isNativePlatform: () => true,
    getPlatform: () => platform,
    isPluginAvailable: (name: string) => plugins.includes(name),
  };
}

const labels = { water: "Νερό" } as WidgetLabels;
const NOW = new Date("2026-11-23T17:00:00Z");

beforeEach(() => window.localStorage.clear());

afterEach(() => {
  delete (window as unknown as { Capacitor?: unknown }).Capacitor;
  delete (window as unknown as { NDEFReader?: unknown }).NDEFReader;
  issue.mockReset();
  revoke.mockReset();
});

describe("widgets", () => {
  const plugin = (): PaleeWidgetsPlugin & { setSession: ReturnType<typeof vi.fn>; clear: ReturnType<typeof vi.fn> } => ({
    setSession: vi.fn().mockResolvedValue(undefined),
    clear: vi.fn().mockResolvedValue(undefined),
  });

  it("renews when there is no token, another person's, or an old one", () => {
    const stored = { id: "w1", token: "t", userId: "u1", issuedAt: "2026-11-01T00:00:00Z" };
    expect(renewalDue(null, "u1", NOW)).toBe(true);
    expect(renewalDue(stored, "u2", NOW)).toBe(true);
    expect(renewalDue(stored, "u1", NOW)).toBe(false);
    expect(renewalDue({ ...stored, issuedAt: "2026-10-01T00:00:00Z" }, "u1", NOW)).toBe(true);
  });

  it("issues once, then hands the stored token with the host, words and paths", async () => {
    bridge("ios", ["PaleeWidgets"]);
    issue.mockResolvedValue({ id: "w1", token: "widget-token", expires_at: "2027-05-01T00:00:00Z" });
    const native = plugin();

    await syncWidgets("access", "u1", labels, { plugin: native, origin: "https://palee.test", now: NOW });
    await syncWidgets("access", "u1", labels, { plugin: native, origin: "https://palee.test", now: NOW });

    expect(issue).toHaveBeenCalledTimes(1);
    expect(issue).toHaveBeenCalledWith("access", "ios", null);
    expect(native.setSession).toHaveBeenLastCalledWith({ token: "widget-token", baseUrl: "https://palee.test", labels, paths: WIDGET_PATHS });
  });

  it("replaces the install's own token when it gets old, and forgets it on sign-out", async () => {
    bridge("android", ["PaleeWidgets"]);
    issue.mockResolvedValueOnce({ id: "w1", token: "one" }).mockResolvedValueOnce({ id: "w2", token: "two" });
    const native = plugin();

    await syncWidgets("access", "u1", labels, { plugin: native, origin: "o", now: new Date("2026-09-01T00:00:00Z") });
    await syncWidgets("access", "u1", labels, { plugin: native, origin: "o", now: NOW });
    expect(issue).toHaveBeenLastCalledWith("access", "android", "w1");

    await forgetWidgets("access", native);
    expect(native.clear).toHaveBeenCalled();
    expect(revoke).toHaveBeenCalledWith("access", "w2");
    expect(window.localStorage.getItem("palee-widget-token")).toBeNull();
  });
});

describe("geofence", () => {
  const region: GeofenceRegion = {
    id: "palee-loc",
    organization_id: "org",
    box_name: "Box",
    location_id: "loc",
    location_name: "Κεντρικό",
    latitude: 37.9,
    longitude: 23.7,
    radius_m: 150,
    token: "a.b.c",
    windows: [{ booking_id: "b", class_name: "WOD", starts_at: "2026-11-23T18:00:00Z", opens_at: "2026-11-23T17:30:00Z", closes_at: "2026-11-23T18:15:00Z" }],
  };
  const words = ({ box, className, time }: { box: string; className: string; time: string }) => ({ title: box, body: `${className} ${time}` });

  it("turns the server's regions into what the phone watches", () => {
    expect(toNativeRegions([region], words, () => "20:00", "https://palee.test")).toEqual([
      {
        id: "palee-loc",
        latitude: 37.9,
        longitude: 23.7,
        radius: 150,
        url: "https://palee.test/c/loc/g/a.b.c",
        windows: [{ from: Date.parse("2026-11-23T17:30:00Z"), to: Date.parse("2026-11-23T18:15:00Z"), title: "Box", body: "WOD 20:00" }],
      },
    ]);
  });

  it("clears while off and syncs once on; sign-out turns it off", async () => {
    const native: PaleeGeofencePlugin = {
      checkPermissions: vi.fn(),
      requestPermissions: vi.fn(),
      setRegions: vi.fn().mockResolvedValue({ monitored: 1 }),
      clear: vi.fn().mockResolvedValue(undefined),
    };
    const fetch = vi.fn().mockResolvedValue({ regions: [region], valid_until: "x" });

    expect(await syncGeofences("access", words, () => "t", { plugin: native, origin: "o", fetch })).toBe(0);
    expect(native.clear).toHaveBeenCalledTimes(1);
    expect(fetch).not.toHaveBeenCalled();

    setReminderEnabled(true);
    expect(await syncGeofences("access", words, () => "t", { plugin: native, origin: "o", fetch })).toBe(1);
    expect(fetch).toHaveBeenCalledWith("access");

    await forgetGeofences(native);
    expect(reminderEnabled()).toBe(false);
  });
});

describe("nfc", () => {
  it("writes through the app's plugin, else Web NFC, else not at all", async () => {
    expect(nfcWriter()).toBeNull();
    await expect(writeNfcTag("https://x/c/l/n/c")).rejects.toThrow("nfc_unavailable");

    const write = vi.fn().mockResolvedValue(undefined);
    (window as unknown as { NDEFReader?: unknown }).NDEFReader = class {
      write = write;
    };
    expect(nfcWriter()).toBe("web");
    await writeNfcTag("https://x/c/l/n/c");
    expect(write).toHaveBeenCalledWith({ records: [{ recordType: "url", data: "https://x/c/l/n/c" }] });

    bridge("android", ["PaleeNfc"]);
    expect(nfcWriter()).toBe("app");
    const plugin: PaleeNfcPlugin = { isAvailable: vi.fn(), write: vi.fn().mockResolvedValue(undefined) };
    await writeNfcTag("https://x/c/l/n/c", "app", plugin);
    expect(plugin.write).toHaveBeenCalledWith({ url: "https://x/c/l/n/c" });
  });
});
