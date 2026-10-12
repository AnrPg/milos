"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef } from "react";

import { useSession } from "@/components/session-provider";
import { OUTBOX_SYNC_REQUESTED_EVENT } from "@/lib/device-outbox-db";
import { getOutboxCommandAdapter } from "@/lib/offline-command-adapters";
import { defaultCommandStore, reconcileOutboxCommands } from "@/lib/offline-command-outbox";
import { reconcileStoredMessages } from "@/lib/offline-message-outbox";

const DELIVERED_QUERY_KEYS: Record<string, readonly (readonly string[])[]> = {
  "booking.request": [["schedule"], ["landing"]],
  "booking.approve": [["schedule"]],
  "booking.reject": [["schedule"]],
  "training_log.create": [["training-log"], ["landing"]],
};

/**
 * Root-level reconciliation of the durable device outbox (ADR-067, ADR-110):
 * queued messages and explicitly registered commands of the signed-in user
 * are replayed on bootstrap, `online`, tab focus, and explicit retry.
 */
export function OfflineMessageSyncBridge() {
  const { tokens, currentUser, status } = useSession();
  const queryClient = useQueryClient();
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
        await reconcileStoredMessages(accessToken, userId).catch(() => undefined);

        const store = defaultCommandStore();
        if (store) {
          await reconcileOutboxCommands({
            token: accessToken,
            ownerUserId: userId,
            lookup: getOutboxCommandAdapter,
            store,
            onDelivered: (operation) => {
              for (const queryKey of DELIVERED_QUERY_KEYS[operation.kind] ?? []) {
                void queryClient.invalidateQueries({ queryKey: [...queryKey] });
              }
            },
          }).catch(() => undefined);
        }
      } finally {
        syncingRef.current = false;
      }
    };

    void synchronize();

    const handleSync = () => void synchronize();
    const handleVisibility = () => {
      if (document.visibilityState === "visible") void synchronize();
    };

    window.addEventListener("online", handleSync);
    window.addEventListener(OUTBOX_SYNC_REQUESTED_EVENT, handleSync);
    document.addEventListener("visibilitychange", handleVisibility);
    return () => {
      window.removeEventListener("online", handleSync);
      window.removeEventListener(OUTBOX_SYNC_REQUESTED_EVENT, handleSync);
      document.removeEventListener("visibilitychange", handleVisibility);
    };
  }, [accessToken, queryClient, status, userId]);

  return null;
}
