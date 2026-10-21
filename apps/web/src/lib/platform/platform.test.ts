import { afterEach, describe, expect, it } from "vitest";

import { getCapabilities, hasCapability, isNative, nativePlatform, nativePushProvider } from "./index";
import { integrationStatusKey, visibleIntegrations } from "./device-rows";

type Bridge = {
  isNativePlatform: () => boolean;
  getPlatform: () => string;
  isPluginAvailable: (name: string) => boolean;
};

function installBridge(platform: "ios" | "android" | "web", plugins: string[] = []) {
  (window as unknown as { Capacitor?: Bridge }).Capacitor = {
    isNativePlatform: () => platform !== "web",
    getPlatform: () => platform,
    isPluginAvailable: (name) => plugins.includes(name),
  };
}

afterEach(() => {
  delete (window as unknown as { Capacitor?: Bridge }).Capacitor;
});

describe("platform capability layer", () => {
  it("is the web, with every capability off, when there is no native bridge", () => {
    expect(isNative()).toBe(false);
    expect(nativePlatform()).toBeNull();
    expect(nativePushProvider()).toBeNull();
    expect(Object.values(getCapabilities()).every((value) => value === false)).toBe(true);
    expect(Object.keys(getCapabilities()).sort()).toEqual(
      ["geofence", "healthConnect", "healthKit", "nativePush", "nfc", "widgets"].sort(),
    );
  });

  it("treats Capacitor's web fallback as the web", () => {
    installBridge("web", ["PushNotifications"]);
    expect(isNative()).toBe(false);
    expect(hasCapability("nativePush")).toBe(false);
  });

  it("reads the platform and the plugins of the iOS app", () => {
    installBridge("ios", ["PushNotifications"]);
    expect(isNative()).toBe(true);
    expect(nativePlatform()).toBe("ios");
    expect(nativePushProvider()).toBe("apns");
    expect(getCapabilities()).toMatchObject({ nativePush: true, healthKit: false, widgets: false });
  });

  it("limits a capability to its platforms", () => {
    installBridge("android", ["PushNotifications", "MilosHealth"]);
    expect(nativePushProvider()).toBe("fcm");
    expect(hasCapability("healthConnect")).toBe(true);
    expect(hasCapability("healthKit")).toBe(false);
  });

  it("survives a broken bridge", () => {
    (window as unknown as { Capacitor?: unknown }).Capacitor = {
      isNativePlatform: () => {
        throw new Error("boom");
      },
    };
    expect(isNative()).toBe(false);
    expect(hasCapability("nativePush")).toBe(false);
  });
});

describe("phone-health rows", () => {
  const rows = [
    { provider: "garmin", status: "disconnected" },
    { provider: "apple_health", status: "native_only" },
    { provider: "health_connect", status: "native_only" },
  ];
  const off = { nativePush: true, healthKit: false, healthConnect: false, widgets: false, geofence: false, nfc: false };

  it("keeps both rows and their status on the web", () => {
    expect(visibleIntegrations(rows, null)).toHaveLength(3);
    expect(integrationStatusKey(rows[1], null, off)).toBe("native_only");
  });

  it("shows only this phone's row inside the app, as «Σύντομα» until the plugin ships", () => {
    expect(visibleIntegrations(rows, "ios").map((row) => row.provider)).toEqual(["garmin", "apple_health"]);
    expect(visibleIntegrations(rows, "android").map((row) => row.provider)).toEqual(["garmin", "health_connect"]);
    expect(integrationStatusKey(rows[1], "ios", off)).toBe("native_soon");
    expect(integrationStatusKey(rows[1], "ios", { ...off, healthKit: true })).toBe("native_only");
    expect(integrationStatusKey(rows[0], "ios", off)).toBe("disconnected");
  });
});
