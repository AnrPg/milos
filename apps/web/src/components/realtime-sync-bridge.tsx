"use client";


import { useEffect, useEffectEvent } from "react";
import { useQueryClient } from "@tanstack/react-query";

import { useSession } from "@/components/session-provider";
import { subscribeToTopic } from "@/lib/realtime";
import { emitUserSync, normalizeUserSyncDetail } from "@/lib/user-sync";

export function RealtimeSyncBridge() {
  
  const { currentUser, tokens } = useSession();
  const queryClient = useQueryClient();

  const handleRefresh = useEffectEvent((payload: unknown) => {
    const detail = normalizeUserSyncDetail(payload);

    if (!detail) {
      return;
    }

    if (detail.scopes.includes("landing")) {
      void queryClient.invalidateQueries({ queryKey: ["landing"] });
      void queryClient.invalidateQueries({ queryKey: ["execution"] });
    }

    if (detail.scopes.includes("admin_challenges")) {
      void queryClient.invalidateQueries({ queryKey: ["admin", "challenges"] });
    }

    if (detail.scopes.includes("admin_settings")) {
      void queryClient.invalidateQueries({ queryKey: ["admin", "settings"] });
    }

    if (detail.scopes.includes("admin_finance")) {
      void queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
      void queryClient.invalidateQueries({ queryKey: ["admin", "dashboard"] });
    }

    if (detail.scopes.includes("admin_analytics")) {
      void queryClient.invalidateQueries({ queryKey: ["admin", "analytics"] });
      void queryClient.invalidateQueries({ queryKey: ["admin", "dashboard"] });
    }

    if (detail.scopes.includes("admin_reviews")) {
      void queryClient.invalidateQueries({ queryKey: ["admin", "reviews"] });
    }

    if (detail.scopes.includes("admin_wellbeing")) {
      void queryClient.invalidateQueries({ queryKey: ["admin", "wellbeing"] });
    }

    if (detail.scopes.includes("admin_athletes") || detail.scopes.includes("admin_coaching")) {
      void queryClient.invalidateQueries({ queryKey: ["admin", "athletes"] });
    }

    if (detail.scopes.includes("my_reviews") || detail.scopes.includes("reviews")) {
      void queryClient.invalidateQueries({ queryKey: ["my", "reviews"] });
      void queryClient.invalidateQueries({ queryKey: ["my", "executions"] });
    }

    if (detail.scopes.includes("my_wellbeing") || detail.scopes.includes("wellbeing")) {
      void queryClient.invalidateQueries({ queryKey: ["my", "wellbeing"] });
    }

    emitUserSync(detail);
  });

  useEffect(() => {
    if (!tokens?.access_token || !currentUser?.id) {
      return;
    }

    return subscribeToTopic(tokens.access_token, "sync:" + (currentUser.id), {
      "sync:refresh": handleRefresh,
    });
  }, [currentUser?.id, tokens?.access_token]);

  return null;
}
