"use client";



import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useState } from "react";

import { registerAppServiceWorker } from "@/lib/push-subscription";

export function ServiceWorkerBootstrap() {
  const i18n = useUiTranslations();
  const [waitingWorker, setWaitingWorker] = useState<ServiceWorker | null>(null);

  useEffect(() => {
    let cancelled = false;
    let reloading = false;
    let updateInterval: number | undefined;

    const handleControllerChange = () => {
      if (reloading) return;
      reloading = true;
      window.location.reload();
    };

    navigator.serviceWorker?.addEventListener("controllerchange", handleControllerChange);

    void registerAppServiceWorker()
      .then((registration) => {
        if (!registration || cancelled) return;
        if (registration.waiting) setWaitingWorker(registration.waiting);

        registration.addEventListener("updatefound", () => {
          const installing = registration.installing;
          installing?.addEventListener("statechange", () => {
            if (installing.state === "installed" && navigator.serviceWorker.controller) {
              setWaitingWorker(registration.waiting ?? installing);
            }
          });
        });

        updateInterval = window.setInterval(() => void registration.update(), 60 * 60 * 1000);
      })
      .catch(() => {
        // Keep the app usable even if service-worker registration fails.
      });

    return () => {
      cancelled = true;
      if (updateInterval) window.clearInterval(updateInterval);
      navigator.serviceWorker?.removeEventListener("controllerchange", handleControllerChange);
    };
  }, []);

  if (!waitingWorker) return null;

  return (
    <div
      role="status"
      aria-live="polite"
      className="fixed inset-x-4 bottom-4 z-[100] mx-auto flex max-w-xl items-center justify-between gap-4 rounded-2xl border p-4 shadow-2xl"
      style={{ background: "var(--surface)", borderColor: "var(--border)", color: "var(--text)" }}
    >
      <p className="text-sm">{i18n("aSaferNewerVersionOfMilosTrainingIs2462a71")}</p>
      <button
        type="button"
        className="shrink-0 rounded-xl px-4 py-2 text-sm font-semibold"
        style={{ background: "var(--primary)", color: "var(--bg)" }}
        onClick={() => waitingWorker.postMessage({ type: "SKIP_WAITING" })}
      >
        {i18n("updateNowc4cbac0")}
      </button>
    </div>
  );
}
