"use client";

import React, { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";

import { fetchExecution, fetchTimerSequence } from "@/api/executions";
import { AuthGuard } from "@/components/auth-guard";
import { ExecutionMode } from "@/components/workouts/execution/ExecutionMode";
import { useSession } from "@/components/session-provider";
import { useExecutionStore } from "@/stores/execution";

function ExecutePageContent() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const { tokens } = useSession();
  const executionId = params.id;

  const {
    executionId: storedExecutionId,
    segments,
    hydrateFromExecution,
  } = useExecutionStore();

  const hasReadyStore = storedExecutionId === executionId && segments.length > 0;
  const [recoveryState, setRecoveryState] = useState<"loading" | "done">(
    hasReadyStore ? "done" : "loading",
  );

  useEffect(() => {
    if (!executionId) {
      router.replace("/workouts");
      return;
    }

    if (!tokens?.access_token) return;

    const accessToken = tokens.access_token;
    let cancelled = false;

    async function recoverExecution() {
      try {
        const execution = await fetchExecution(accessToken, executionId);

        if (!execution.master_workout_id) {
          router.replace("/workouts");
          return;
        }

        const recoveredSegments = await fetchTimerSequence(
          accessToken,
          execution.master_workout_id,
          {
            scaleSlug: execution.scale_level_slug,
            source: execution.source as "class_booking" | "assigned" | "self_selected",
            sourceReferenceId: execution.source_reference_id,
          },
        );

        if (cancelled) return;

        hydrateFromExecution(execution, recoveredSegments);

        setRecoveryState("done");
      } catch {
        if (!cancelled) router.replace("/workouts");
      }
    }

    void recoverExecution();

    return () => {
      cancelled = true;
    };
  }, [
    executionId,
    hydrateFromExecution,
    router,
    tokens?.access_token,
  ]);

  if (!hasReadyStore && recoveryState === "loading") {
    return (
      <div
        className="flex min-h-screen items-center justify-center px-6 text-sm"
        style={{ background: "var(--bg)", color: "var(--muted)" }}
      >
        Recovering workout session…
      </div>
    );
  }

  return <ExecutionMode />;
}

export default function ExecutePage() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <ExecutePageContent />
    </AuthGuard>
  );
}
