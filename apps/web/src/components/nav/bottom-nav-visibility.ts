"use client";

import { useEffect, useSyncExternalStore } from "react";

// Screens that ask the bottom bar to step aside (lib/bottom-nav.ts holds the
// routes that never show it). A count, so nested requests (a media preview
// opened from the composer) keep it hidden until the last one closes.

let requests = 0;
const listeners = new Set<() => void>();

function publish() {
  listeners.forEach((listener) => listener());
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/**
 * Hides the member app's bottom bar while the calling component is mounted
 * (and `active`). For focused, full-screen moments that are not routes of
 * their own: the camera, a media preview, the composer, the avatar editor.
 * ui/Layer and ui/Dialog call it for every layer they open.
 */
export function useHideBottomNav(active = true) {
  useEffect(() => {
    if (!active) return;
    requests += 1;
    publish();
    return () => {
      requests -= 1;
      publish();
    };
  }, [active]);
}

/** True while any screen asks the bar to hide. */
export function useBottomNavHiddenByScreen() {
  return useSyncExternalStore(subscribe, () => requests > 0, () => false);
}
