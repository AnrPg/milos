"use client";

import { useEffect, useState } from "react";

import { ApiError } from "@/api/client";
import { updateDraftWorkout } from "@/api/workouts";
import { DraftSaver, type DraftSaveStatus } from "@/lib/draft-saver";

export function isStaleRevisionError(error: unknown) {
  return error instanceof ApiError && error.payload?.code === "stale_dsl_revision";
}

/**
 * One serialized draft saver per workout editor (see `DraftSaver`). The
 * saver lives as long as the editor; it stops saving when the editor
 * unmounts, so a closed editor never races the one that replaces it.
 */
export function useDraftSaver<P extends object>({
  accessToken,
  draftId,
  onSaved,
}: {
  accessToken: string | undefined;
  draftId: string | null;
  onSaved?: (revision: number) => void;
}) {
  const [status, setStatus] = useState<DraftSaveStatus>("idle");
  const [saver] = useState(() => new DraftSaver<P>({ isConflict: isStaleRevisionError, onStatus: setStatus }));

  // Declared before the editor's own effects, so saves always use the
  // current sign-in token and draft.
  useEffect(() => {
    saver.setTarget({
      send: (payload) =>
        accessToken && draftId
          ? updateDraftWorkout(accessToken, draftId, payload)
          : Promise.reject(new Error("The draft is not ready.")),
      onSaved,
    });
  });

  useEffect(() => {
    saver.reopen();
    return () => saver.close();
  }, [saver]);

  return { saver, status };
}
