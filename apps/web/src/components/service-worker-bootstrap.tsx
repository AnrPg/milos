"use client";

import { useEffect } from "react";

import { registerAppServiceWorker } from "@/lib/push-subscription";

export function ServiceWorkerBootstrap() {
  useEffect(() => {
    void registerAppServiceWorker().catch(() => {
      // Keep the app usable even if service-worker registration fails.
    });
  }, []);

  return null;
}
