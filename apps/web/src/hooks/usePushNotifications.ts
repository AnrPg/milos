"use client";

import { useEffect, useState } from "react";

import {
  fetchPushNotificationConfig,
  fetchPushSubscriptionStatus,
  savePushSubscription,
  type PushNotificationConfig,
  type PushSubscriptionPayload,
} from "@/api/notifications";
import { clearBrowserPushSubscription, registerAppServiceWorker } from "@/lib/push-subscription";

const PUSH_CONFIG_CACHE = "milos-push-config-v1";
const PUSH_CONFIG_REQUEST = "/__milos_push_config__";

function base64UrlToUint8Array(value: string) {
  const padding = "=".repeat((4 - (value.length % 4)) % 4);
  const base64 = (value + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = window.atob(base64);
  const output = new Uint8Array(raw.length);

  for (let index = 0; index < raw.length; index += 1) {
    output[index] = raw.charCodeAt(index);
  }

  return output;
}

function toPayload(subscription: PushSubscription): PushSubscriptionPayload {
  const json = subscription.toJSON();

  return {
    endpoint: subscription.endpoint,
    expiration_time:
      typeof json.expirationTime === "number" ? new Date(json.expirationTime).toISOString() : null,
    keys: {
      p256dh: json.keys?.p256dh ?? "",
      auth: json.keys?.auth ?? "",
    },
  };
}

async function storeTokenForSW(token: string): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const req = indexedDB.open("milos-sw", 1);
    req.onupgradeneeded = () => {
      req.result.createObjectStore("config", { keyPath: "key" });
    };
    req.onsuccess = () => {
      const tx = req.result.transaction("config", "readwrite");
      tx.objectStore("config").put({ key: "access_token", value: token });
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    };
    req.onerror = () => reject(req.error);
  });
}

async function persistPushConfig(config: PushNotificationConfig) {
  if (typeof window === "undefined" || !("caches" in window) || !config.vapid_public_key) {
    return;
  }

  const cache = await caches.open(PUSH_CONFIG_CACHE);
  await cache.put(
    PUSH_CONFIG_REQUEST,
    new Response(JSON.stringify({ vapidPublicKey: config.vapid_public_key }), {
      headers: { "Content-Type": "application/json" },
    }),
  );

  const registration = await registerAppServiceWorker();
  if (!registration) {
    return;
  }

  registration.active?.postMessage({
    type: "milos:push-config",
    vapidPublicKey: config.vapid_public_key,
  });
}

export function usePushNotifications(accessToken: string | null | undefined) {
  type PushSyncState =
    | "idle"
    | "checking"
    | "ready"
    | "blocked"
    | "enabling"
    | "enabled"
    | "error";
  type PushSyncStep =
    | "idle"
    | "fetch-config"
    | "register-worker"
    | "browser-subscription"
    | "server-save"
    | "server-verify"
    | "complete";

  const [supported] = useState(() => {
    if (typeof window === "undefined") {
      return false;
    }

    return (
      "serviceWorker" in navigator &&
      "PushManager" in window &&
      "Notification" in window
    );
  });
  const [enabled, setEnabled] = useState(false);
  const [configured, setConfigured] = useState<boolean | null>(null);
  const [permission, setPermission] = useState<NotificationPermission | "unsupported">(() => {
    if (
      typeof window === "undefined" ||
      !("serviceWorker" in navigator) ||
      !("PushManager" in window) ||
      !("Notification" in window)
    ) {
      return "unsupported";
    }

    return Notification.permission;
  });
  const [busy, setBusy] = useState(false);
  const [state, setState] = useState<PushSyncState>(supported ? "idle" : "blocked");
  const [step, setStep] = useState<PushSyncStep>("idle");
  const [error, setError] = useState<string | null>(null);

  async function syncSubscription(token: string, allowSubscribe: boolean) {
    setError(null);
    setState(allowSubscribe ? "enabling" : "checking");
    setStep("fetch-config");

    const config = await fetchPushNotificationConfig(token);

    if (!config.enabled || !config.vapid_public_key) {
      setConfigured(false);
      setEnabled(false);
      setState("ready");
      setStep("fetch-config");
      setError("Browser push is not configured on the server yet.");
      return false;
    }

    setConfigured(true);
    await persistPushConfig(config);

    setStep("register-worker");
    const registration = await registerAppServiceWorker();

    if (!registration) {
      setEnabled(false);
      setState("error");
      setStep("register-worker");
      setError("The service worker could not be registered in this browser.");
      return false;
    }

    setStep("browser-subscription");
    const existing = await registration.pushManager.getSubscription();

    if (existing) {
      setStep("server-save");
      await savePushSubscription(token, toPayload(existing));
      setStep("server-verify");

      const status = await fetchPushSubscriptionStatus(token, existing.endpoint);

      if (!status.registered) {
        setEnabled(false);
        setState("error");
        setError("The browser subscription was created, but the server did not confirm persistence.");
        return false;
      }

      setEnabled(true);
      setState("enabled");
      setStep("complete");
      return true;
    }

    if (!allowSubscribe) {
      setEnabled(false);
      setState(Notification.permission === "denied" ? "blocked" : "ready");
      setStep("browser-subscription");
      return false;
    }

    const created = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: base64UrlToUint8Array(config.vapid_public_key),
    });

    setStep("server-save");
    await savePushSubscription(token, toPayload(created));
    setStep("server-verify");

    const status = await fetchPushSubscriptionStatus(token, created.endpoint);

    if (!status.registered) {
      setEnabled(false);
      setState("error");
      setError("The browser subscription was created, but the server did not confirm persistence.");
      return false;
    }

    setEnabled(true);
    setState("enabled");
    setStep("complete");
    return true;
  }

  useEffect(() => {
    if (!accessToken || !supported) return;

    const token = accessToken;
    let cancelled = false;

    void storeTokenForSW(token);

    async function syncExistingSubscription() {
      try {
        await syncSubscription(token, Notification.permission === "granted");
        if (cancelled) return;
      } catch (caught) {
        if (!cancelled) {
          setEnabled(false);
          setState("error");
          setError(caught instanceof Error ? caught.message : "Unable to initialize browser push.");
        }
      }
    }

    void syncExistingSubscription();

    return () => {
      cancelled = true;
    };
  }, [accessToken, supported]);

  useEffect(() => {
    if (!accessToken || !supported || !("serviceWorker" in navigator)) return;

    const token = accessToken;

    function handleWorkerMessage(event: MessageEvent) {
      if (
        event.data?.type === "milos:push-subscription-stale" ||
        event.data?.type === "milos:push-subscription-updated"
      ) {
        void syncSubscription(token, Notification.permission === "granted").catch((caught) => {
          setState("error");
          setError(caught instanceof Error ? caught.message : "Unable to synchronize browser push.");
        });
      }
    }

    navigator.serviceWorker.addEventListener("message", handleWorkerMessage);

    return () => {
      navigator.serviceWorker.removeEventListener("message", handleWorkerMessage);
    };
  }, [accessToken, supported]);

  async function enablePush() {
    if (!accessToken || !supported) return false;
    const token = accessToken;
    setBusy(true);
    setError(null);

    try {
      const nextPermission = await Notification.requestPermission();
      setPermission(nextPermission);

      if (nextPermission !== "granted") {
        setEnabled(false);
        setState(nextPermission === "denied" ? "blocked" : "ready");
        setStep("browser-subscription");
        return false;
      }

      return syncSubscription(token, true);
    } catch (caught) {
      setEnabled(false);
      setState("error");
      setError(caught instanceof Error ? caught.message : "Unable to enable browser push.");
      return false;
    } finally {
      setBusy(false);
    }
  }

  async function disablePush() {
    if (!accessToken || !supported) return false;
    const token = accessToken;
    setBusy(true);
    setError(null);

    try {
      await clearBrowserPushSubscription(token);
      setEnabled(false);
      setState("ready");
      setStep("idle");
      return true;
    } catch (caught) {
      setState("error");
      setError(caught instanceof Error ? caught.message : "Unable to disable browser push.");
      return false;
    } finally {
      setBusy(false);
    }
  }

  return {
    supported,
    enabled,
    configured,
    permission,
    busy,
    state,
    step,
    error,
    enablePush,
    disablePush,
  };
}
