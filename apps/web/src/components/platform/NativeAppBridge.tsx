"use client";

// ADR-171: glue between the store apps' shell and the web app. Renders
// nothing and does nothing in a browser; inside the app it opens share links
// the OS hands over (universal links / App Links), follows a tapped push to
// its page, and maps Android's back button to the web history.
import { useRouter } from "next/navigation";
import { useEffect, useRef } from "react";

import { markNotificationClicked } from "@/api/notifications";
import { useSession } from "@/components/session-provider";
import { isNative, nativePlatform } from "@/lib/platform";
import { notificationPath } from "@/lib/platform/app-links";
import { finishCheckout } from "@/lib/platform/checkout";
import { routeDeepLink } from "@/lib/platform/deep-links";
import { nativePushSupported } from "@/lib/platform/native-push";

type Removable = { remove: () => Promise<void> };

export function NativeAppBridge() {
  const router = useRouter();
  const { tokens } = useSession();
  const accessToken = useRef<string | null>(null);

  useEffect(() => {
    accessToken.current = tokens?.access_token ?? null;
  }, [tokens?.access_token]);

  useEffect(() => {
    if (!isNative()) return;
    const root = document.documentElement;
    root.dataset.platform = nativePlatform() ?? "native";

    let disposed = false;
    const handles: Removable[] = [];
    const keep = (handle: Removable) => {
      if (disposed) void handle.remove();
      else handles.push(handle);
    };

    void (async () => {
      const { App } = await import("@capacitor/app");

      keep(
        await App.addListener("appUrlOpen", ({ url }) => {
          const link = routeDeepLink(url, window.location.origin);
          if (!link) return;
          // ADR-256: back from the provider's checkout page in the in-app browser.
          if (link.kind === "payment_return") void finishCheckout();
          router.push(link.path);
        }),
      );

      keep(
        await App.addListener("backButton", ({ canGoBack }) => {
          if (canGoBack) window.history.back();
          else void App.minimizeApp();
        }),
      );

      if (nativePushSupported()) {
        const { PushNotifications } = await import("@capacitor/push-notifications");
        keep(
          await PushNotifications.addListener("pushNotificationActionPerformed", ({ notification }) => {
            const data = (notification.data ?? {}) as Record<string, unknown>;
            const path = notificationPath(data.url, window.location.origin);
            const token = accessToken.current;
            if (token && typeof data.notification_id === "string") {
              void markNotificationClicked(token, data.notification_id, path).catch(() => undefined);
            }
            if (path) router.push(path);
          }),
        );
      }
    })().catch(() => {
      // An app build without these plugins still works as the plain web app.
    });

    return () => {
      disposed = true;
      for (const handle of handles) void handle.remove();
    };
  }, [router]);

  return null;
}
