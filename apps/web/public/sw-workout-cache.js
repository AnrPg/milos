const WORKOUT_CACHE_PREFIX = "milos-workout-runtime-v2-user-";
const LEGACY_WORKOUT_CACHE = "milos-workout-runtime-v1";
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

self.addEventListener("install", (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    Promise.all([caches.delete(LEGACY_WORKOUT_CACHE), self.clients.claim()]),
  );
});

self.addEventListener("message", (event) => {
  const message = event.data;

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

      const networkPromise = fetch(event.request)
        .then((response) => {
          if (response.ok && activeUserId === requestUserId) {
            void cache.put(event.request, response.clone());
          }

          return response;
        })
        .catch(() => null);

      if (cached) {
        void networkPromise;
        return cached;
      }

      const networkResponse = await networkPromise;

      if (networkResponse) {
        return networkResponse;
      }

      return new Response(JSON.stringify({ error: "Offline" }), {
        status: 503,
        headers: { "Content-Type": "application/json" },
      });
    })(),
  );
});
