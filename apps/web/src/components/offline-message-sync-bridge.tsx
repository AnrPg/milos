"use client";

import { useEffect, useRef } from "react";

import { useSession } from "@/components/session-provider";
import { reconcileStoredMessages } from "@/lib/offline-message-outbox";

export function OfflineMessageSyncBridge() {
  const { tokens, currentUser, status } = useSession();
  const syncingRef = useRef(false);
  const accessToken = tokens?.access_token;
  const userId = currentUser?.id;

  useEffect(() => {
    const synchronize = async () => {
      if (
        status !== "authenticated" ||
        !accessToken ||
        !userId ||
        syncingRef.current ||
        !navigator.onLine
      ) {
        return;
      }

      syncingRef.current = true;
      try {
        await reconcileStoredMessages(accessToken, userId);
      } catch {
        // A blocked or unavailable browser database must not break session bootstrap.
      } finally {
        syncingRef.current = false;
      }
    };

    void synchronize();

    const handleOnline = () => void synchronize();
    const handleVisibility = () => {
      if (document.visibilityState === "visible") void synchronize();
    };

    window.addEventListener("online", handleOnline);
    document.addEventListener("visibilitychange", handleVisibility);
    return () => {
      window.removeEventListener("online", handleOnline);
      document.removeEventListener("visibilitychange", handleVisibility);
    };
  }, [accessToken, status, userId]);

  return null;
}
