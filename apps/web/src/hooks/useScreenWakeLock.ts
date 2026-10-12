"use client";

import { useEffect } from "react";

type WakeLockSentinelLike = { released: boolean; release: () => Promise<void> };
type WakeLockLike = { request: (type: "screen") => Promise<WakeLockSentinelLike> };

/**
 * Keeps the screen on while `enabled` (e.g. during a workout). Browsers drop
 * the lock whenever the page is hidden, so it is re-acquired when the page
 * becomes visible again. Silently does nothing where unsupported.
 */
export function useScreenWakeLock(enabled: boolean) {
  useEffect(() => {
    if (!enabled || typeof navigator === "undefined") return;

    const wakeLock = (navigator as Navigator & { wakeLock?: WakeLockLike }).wakeLock;
    if (!wakeLock) return;

    let sentinel: WakeLockSentinelLike | null = null;
    let disposed = false;

    const acquire = async () => {
      if (document.visibilityState !== "visible" || (sentinel && !sentinel.released)) return;
      try {
        const next = await wakeLock.request("screen");
        if (disposed) {
          void next.release().catch(() => undefined);
          return;
        }
        sentinel = next;
      } catch {
        // Denied (battery saver, permissions policy) — the workout still runs.
      }
    };

    const onVisibilityChange = () => {
      void acquire();
    };

    void acquire();
    document.addEventListener("visibilitychange", onVisibilityChange);

    return () => {
      disposed = true;
      document.removeEventListener("visibilitychange", onVisibilityChange);
      if (sentinel && !sentinel.released) void sentinel.release().catch(() => undefined);
    };
  }, [enabled]);
}
