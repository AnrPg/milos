"use client";

import { deletePushSubscription } from "@/api/notifications";

export async function registerAppServiceWorker() {
  if (typeof window === "undefined" || !("serviceWorker" in navigator)) {
    return null;
  }

  return navigator.serviceWorker.register("/sw.js");
}

export async function setWorkoutCacheUser(userId: string | null) {
  if (typeof window === "undefined" || !("serviceWorker" in navigator)) {
    return;
  }

  const registration = await registerAppServiceWorker();
  const worker =
    navigator.serviceWorker.controller ??
    registration?.active ??
    registration?.waiting ??
    registration?.installing;

  worker?.postMessage({ type: "SET_WORKOUT_CACHE_USER", userId });
}

export async function clearWorkoutCache() {
  if (typeof window === "undefined" || !("serviceWorker" in navigator)) {
    return;
  }

  const registration = await registerAppServiceWorker();
  const worker =
    navigator.serviceWorker.controller ??
    registration?.active ??
    registration?.waiting ??
    registration?.installing;

  worker?.postMessage({ type: "CLEAR_WORKOUT_CACHE" });
}

export async function clearBrowserPushSubscription(accessToken?: string | null) {
  if (
    typeof window === "undefined" ||
    !("serviceWorker" in navigator) ||
    !("PushManager" in window)
  ) {
    return;
  }

  const registration = await registerAppServiceWorker();

  if (!registration) {
    return;
  }

  const subscription = await registration.pushManager.getSubscription();

  if (!subscription) {
    return;
  }

  if (accessToken) {
    try {
      await deletePushSubscription(accessToken, { endpoint: subscription.endpoint });
    } catch {
      // Unsubscribe locally even if the server-side cleanup fails.
    }
  }

  try {
    await subscription.unsubscribe();
  } catch {
    // The local subscription may already be inactive.
  }
}
