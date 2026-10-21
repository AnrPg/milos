import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const listeners: Record<string, (event: unknown) => void> = {};

const push = vi.hoisted(() => ({
  checkPermissions: vi.fn(),
  requestPermissions: vi.fn(),
  register: vi.fn(),
  unregister: vi.fn(),
  addListener: vi.fn(),
}));

const api = vi.hoisted(() => ({
  registerNativePushToken: vi.fn(),
  unregisterNativePushToken: vi.fn(),
}));

vi.mock("@capacitor/push-notifications", () => ({ PushNotifications: push }));
vi.mock("@/api/notifications", () => api);

import {
  hasRegisteredNativePush,
  nativePushPermission,
  nativePushSupported,
  registerNativePush,
  requestNativePushPermission,
  resetNativePushForTests,
  unregisterNativePush,
} from "./native-push";

function installBridge(platform: "ios" | "android") {
  (window as unknown as { Capacitor?: unknown }).Capacitor = {
    isNativePlatform: () => true,
    getPlatform: () => platform,
    isPluginAvailable: (name: string) => name === "PushNotifications",
  };
}

beforeEach(() => {
  resetNativePushForTests();
  window.localStorage.clear();
  push.addListener.mockImplementation(async (event: string, callback: (event: unknown) => void) => {
    listeners[event] = callback;
    return { remove: async () => undefined };
  });
  push.register.mockImplementation(async () => {
    listeners.registration?.({ value: "device-token-123456789" });
  });
  push.unregister.mockResolvedValue(undefined);
  api.registerNativePushToken.mockResolvedValue({ native_push_token: { id: "t-1" } });
  api.unregisterNativePushToken.mockResolvedValue({ deleted: true });
});

afterEach(() => {
  delete (window as unknown as { Capacitor?: unknown }).Capacitor;
  vi.clearAllMocks();
});

describe("native push", () => {
  it("does nothing on the web", async () => {
    expect(nativePushSupported()).toBe(false);
    expect(await nativePushPermission()).toBe("unsupported");
    expect(await registerNativePush("access")).toBe(false);
    await unregisterNativePush("access");
    expect(push.register).not.toHaveBeenCalled();
    expect(api.unregisterNativePushToken).not.toHaveBeenCalled();
  });

  it("maps the OS permission to the browser's words", async () => {
    installBridge("android");
    push.checkPermissions.mockResolvedValue({ receive: "prompt-with-rationale" });
    expect(await nativePushPermission()).toBe("default");
    push.requestPermissions.mockResolvedValue({ receive: "denied" });
    expect(await requestNativePushPermission()).toBe("denied");
  });

  it("registers the Android install's FCM token once per run", async () => {
    installBridge("android");
    expect(await registerNativePush("access", "1.0.0")).toBe(true);
    expect(await registerNativePush("access", "1.0.0")).toBe(true);

    expect(push.register).toHaveBeenCalledTimes(1);
    expect(api.registerNativePushToken).toHaveBeenCalledWith("access", {
      provider: "fcm",
      platform: "android",
      token: "device-token-123456789",
      app_version: "1.0.0",
      apns_environment: null,
    });
    expect(hasRegisteredNativePush()).toBe(true);
  });

  it("registers an iPhone as APNs", async () => {
    installBridge("ios");
    await registerNativePush("access");
    expect(api.registerNativePushToken).toHaveBeenCalledWith("access", expect.objectContaining({ provider: "apns", platform: "ios" }));
  });

  it("a registration error can be retried", async () => {
    installBridge("ios");
    push.register.mockImplementationOnce(async () => {
      listeners.registrationError?.({ error: "no entitlement" });
    });
    await expect(registerNativePush("access")).rejects.toThrow("no entitlement");
    expect(await registerNativePush("access")).toBe(true);
  });

  it("sign-out forgets the install on the server and on the device", async () => {
    installBridge("android");
    await registerNativePush("access");
    await unregisterNativePush("access");
    expect(api.unregisterNativePushToken).toHaveBeenCalledWith("access", "device-token-123456789");
    expect(push.unregister).toHaveBeenCalled();
    expect(hasRegisteredNativePush()).toBe(false);
  });
});
