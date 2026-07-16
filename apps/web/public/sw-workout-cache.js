const WORKOUT_CACHE_PREFIX = "milos-workout-runtime-v2-user-";
const LEGACY_WORKOUT_CACHE = "milos-workout-runtime-v1";
const AUTHENTICATED_CACHE_TTL_MS = 15 * 60 * 1000;
let activeUserId = null;

function workoutCacheName(userId) {
  return `${WORKOUT_CACHE_PREFIX}${encodeURIComponent(userId)}`;
}

async function clearWorkoutCaches() {
  const cacheNames = await caches.keys();

  await Promise.all(
    cacheNames
      .filter(
        (cacheName) =>
          cacheName === LEGACY_WORKOUT_CACHE ||
          cacheName.startsWith(WORKOUT_CACHE_PREFIX),
      )
      .map((cacheName) => caches.delete(cacheName)),
  );
}

async function cacheableResponse(response) {
  const headers = new Headers(response.headers);
  headers.set("x-milos-cached-at", String(Date.now()));
  const body = await response.clone().blob();

  return new Response(body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function freshCachedResponse(response) {
  const cachedAt = Number(response?.headers.get("x-milos-cached-at") ?? 0);
  return cachedAt > 0 && Date.now() - cachedAt <= AUTHENTICATED_CACHE_TTL_MS;
}

function shouldCacheWorkoutRequest(request) {
  if (request.method !== "GET") {
    return false;
  }

  const url = new URL(request.url);

  if (url.origin !== self.location.origin) {
    return false;
  }

  return (
    /^\/api\/workouts\/[^/]+$/.test(url.pathname) ||
    /^\/api\/workouts\/[^/]+\/scales$/.test(url.pathname) ||
    /^\/api\/workouts\/[^/]+\/timer-sequence$/.test(url.pathname) ||
    /^\/api\/executions\/[^/]+$/.test(url.pathname)
  );
}

self.addEventListener("install", () => {
  // Keep an updated worker waiting until the user accepts the in-app update prompt.
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    Promise.all([caches.delete(LEGACY_WORKOUT_CACHE), self.clients.claim()]),
  );
});

self.addEventListener("message", (event) => {
  const message = event.data;

  if (message?.type === "SKIP_WAITING") {
    event.waitUntil(self.skipWaiting());
    return;
  }

  if (message?.type === "CLEAR_WORKOUT_CACHE") {
    event.waitUntil(clearWorkoutCaches());
    return;
  }

  if (!message || message.type !== "SET_WORKOUT_CACHE_USER") {
    return;
  }

  const nextUserId =
    typeof message.userId === "string" && message.userId.length > 0
      ? message.userId
      : null;
  const userChanged = activeUserId !== nextUserId;

  activeUserId = nextUserId;

  if (userChanged) {
    event.waitUntil(clearWorkoutCaches());
  }
});

self.addEventListener("fetch", (event) => {
  if (!activeUserId || !shouldCacheWorkoutRequest(event.request)) {
    return;
  }

  const requestUserId = activeUserId;

  event.respondWith(
    (async () => {
      const cache = await caches.open(workoutCacheName(requestUserId));
      const cached = await cache.match(event.request);

      try {
        const response = await fetch(event.request);

        if (response.status === 401 || response.status === 403) {
          await cache.delete(event.request);
          return response;
        }

        if (response.ok && activeUserId === requestUserId) {
          await cache.put(event.request, await cacheableResponse(response));
        }

        return response;
      } catch {
        if (cached && freshCachedResponse(cached)) return cached;
        if (cached) await cache.delete(event.request);
      }

      return new Response(JSON.stringify({ code: "offline", error: "Offline" }), {
        status: 503,
        headers: { "Content-Type": "application/json" },
      });
    })(),
  );
});
