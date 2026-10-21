"use client";

// ADR-171: push inside the store apps. Replaces the browser's Web Push there:
// the OS hands the app an APNs (iOS) or FCM (Android) token, which is sent to
// POST /api/notifications/native-push-tokens. One registration per app run,
// whatever number of components ask for it.
import { registerNativePushToken, unregisterNativePushToken } from "@/api/notifications";

import { hasCapability, nativePlatform, nativePushProvider } from "./index";

export type NativePushPermission = NotificationPermission | "unsupported";

const DEVICE_TOKEN_KEY = "palee-native-push-token";

let pendingToken: Promise<string> | null = null;
let listenersReady: Promise<void> | null = null;
let resolveToken: ((token: string) => void) | null = null;
let rejectToken: ((error: unknown) => void) | null = null;

async function plugin() {
  const { PushNotifications } = await import("@capacitor/push-notifications");
  return PushNotifications;
}

function rememberDeviceToken(token: string | null) {
  try {
    if (token) window.localStorage.setItem(DEVICE_TOKEN_KEY, token);
    else window.localStorage.removeItem(DEVICE_TOKEN_KEY);
  } catch {}
}

function rememberedDeviceToken() {
  try {
    return window.localStorage.getItem(DEVICE_TOKEN_KEY);
  } catch {
    return null;
  }
}

function toPermission(state: string): NativePushPermission {
  if (state === "granted") return "granted";
  if (state === "denied") return "denied";
  return "default";
}

export function nativePushSupported() {
  return hasCapability("nativePush");
}

export async function nativePushPermission(): Promise<NativePushPermission> {
  if (!nativePushSupported()) return "unsupported";
  const push = await plugin();
  return toPermission((await push.checkPermissions()).receive);
}

export async function requestNativePushPermission(): Promise<NativePushPermission> {
  if (!nativePushSupported()) return "unsupported";
  const push = await plugin();
  return toPermission((await push.requestPermissions()).receive);
}

async function ensureListeners() {
  listenersReady ??= (async () => {
    const push = await plugin();
    await push.addListener("registration", ({ value }) => {
      resolveToken?.(value);
    });
    await push.addListener("registrationError", ({ error }) => {
      rejectToken?.(new Error(error));
    });
  })();
  return listenersReady;
}

/** Asks the OS for this install's push token (permission must be granted). */
async function deviceToken(): Promise<string> {
  await ensureListeners();
  pendingToken ??= new Promise<string>((resolve, reject) => {
    resolveToken = resolve;
    rejectToken = (error) => {
      pendingToken = null;
      reject(error);
    };
    void plugin().then((push) => push.register()).catch(rejectToken);
  });
  return pendingToken;
}

/** Registers this install for push under the signed-in account. */
export async function registerNativePush(accessToken: string, appVersion?: string | null) {
  const provider = nativePushProvider();
  const platform = nativePlatform();
  if (!provider || !platform) return false;

  const token = await deviceToken();
  await registerNativePushToken(accessToken, {
    provider,
    platform,
    token,
    app_version: appVersion ?? null,
    // Store and TestFlight builds use production APNs, the server's default.
    apns_environment: null,
  });
  rememberDeviceToken(token);
  return true;
}

/** Stops push to this install (sign-out or switching it off). */
export async function unregisterNativePush(accessToken?: string | null) {
  if (!nativePushSupported()) return;
  const token = rememberedDeviceToken();
  if (token && accessToken) {
    try {
      await unregisterNativePushToken(accessToken, token);
    } catch {
      // The server forgets the token the next time a push to it fails.
    }
  }
  rememberDeviceToken(null);
  pendingToken = null;
  try {
    await (await plugin()).unregister();
  } catch {}
}

export function hasRegisteredNativePush() {
  return rememberedDeviceToken() !== null;
}

/** Test hook: forget the module state. */
export function resetNativePushForTests() {
  pendingToken = null;
  listenersReady = null;
  resolveToken = null;
  rejectToken = null;
}
