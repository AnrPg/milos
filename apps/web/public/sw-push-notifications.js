self.addEventListener("message", (event) => {
  if (event.data?.type === "milos:push-config" && typeof event.data.vapidPublicKey === "string") {
    event.waitUntil(cachePushConfig(event.data.vapidPublicKey));
  }
});

self.addEventListener("push", (event) => {
  const data = event.data?.json() ?? {};
  const notificationId = data.notification_id ?? null;

  event.waitUntil(
    self.registration.showNotification(data.title ?? "Milos Training", {
      body: data.body ?? "",
      lang: data.locale ?? "en",
      dir: data.locale === "ar" || data.locale === "he" ? "rtl" : "ltr",
      icon: "/globe.svg",
      badge: "/globe.svg",
      data: { url: data.url, notification_id: notificationId },
    }),
  );
});

async function readTokenFromDb() {
  return new Promise((resolve) => {
    const req = indexedDB.open("milos-sw", 1);
    req.onupgradeneeded = () => req.result.createObjectStore("config", { keyPath: "key" });
    req.onsuccess = () => {
      const tx = req.result.transaction("config", "readonly");
      const get = tx.objectStore("config").get("access_token");
      get.onsuccess = () => resolve(get.result?.value ?? null);
      get.onerror = () => resolve(null);
    };
    req.onerror = () => resolve(null);
  });
}

self.addEventListener("pushsubscriptionchange", (event) => {
  event.waitUntil(handlePushSubscriptionChange());
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  event.waitUntil(handleNotificationClick(event.notification.data ?? {}));
});

async function handleNotificationClick(data) {
  const url = data.url || "/";
  const notificationId = data.notification_id || null;

  if (notificationId) {
    await recordNotificationClick(notificationId, url);
  }

  await clients.openWindow(url);
}

async function recordNotificationClick(notificationId, url) {
  const token = await readTokenFromDb();

  if (!token) {
    return;
  }

  await fetch(`${self.location.origin}/api/notifications/${notificationId}/click`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ url }),
  }).catch(() => {});
}

const PUSH_CONFIG_CACHE = "milos-push-config-v1";
const PUSH_CONFIG_REQUEST = "/__milos_push_config__";

function base64UrlToUint8Array(value) {
  const padding = "=".repeat((4 - (value.length % 4)) % 4);
  const base64 = (value + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  const output = new Uint8Array(raw.length);

  for (let index = 0; index < raw.length; index += 1) {
    output[index] = raw.charCodeAt(index);
  }

  return output;
}

async function cachePushConfig(vapidPublicKey) {
  const cache = await caches.open(PUSH_CONFIG_CACHE);
  await cache.put(
    PUSH_CONFIG_REQUEST,
    new Response(JSON.stringify({ vapidPublicKey }), {
      headers: { "Content-Type": "application/json" },
    }),
  );
}

async function readPushConfig() {
  const cache = await caches.open(PUSH_CONFIG_CACHE);
  const response = await cache.match(PUSH_CONFIG_REQUEST);

  if (!response) {
    return null;
  }

  try {
    return await response.json();
  } catch {
    return null;
  }
}

async function broadcastToClients(message) {
  const windowClients = await clients.matchAll({ type: "window", includeUncontrolled: true });

  windowClients.forEach((client) => {
    client.postMessage(message);
  });
}

async function handlePushSubscriptionChange() {
  const config = await readPushConfig();

  if (!config?.vapidPublicKey) {
    await broadcastToClients({ type: "milos:push-subscription-stale" });
    return;
  }

  try {
    await self.registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: base64UrlToUint8Array(config.vapidPublicKey),
    });

    await broadcastToClients({ type: "milos:push-subscription-updated" });
  } catch {
    await broadcastToClients({ type: "milos:push-subscription-stale" });
  }
}
