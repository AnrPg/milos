"use client";

import React, { useEffect, useRef, useState } from "react";

import { createDraftWorkout, listScaleLevels, type ScaleLevel, updateDraftWorkout } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { useWorkoutCreationStore } from "@/stores/workout-creation";

import { CanvasHeader } from "./CanvasHeader";
import { LeftPanel } from "./LeftPanel";
import { MobileCanvas } from "./MobileCanvas";
import { MiddlePanel } from "./MiddlePanel";
import { RightPanel } from "./RightPanel";

const AUTOSAVE_DELAY_MS = 1500;

export function WorkoutCreationCanvas() {
  const { tokens } = useSession();
  const draftId = useWorkoutCreationStore((state) => state.draftId);
  const initDraft = useWorkoutCreationStore((state) => state.initDraft);
  const setSaveStatus = useWorkoutCreationStore((state) => state.setSaveStatus);
  const title = useWorkoutCreationStore((state) => state.title);
  const type = useWorkoutCreationStore((state) => state.type);
  const sections = useWorkoutCreationStore((state) => state.sections);
  const toApiPayload = useWorkoutCreationStore((state) => state.toApiPayload);
  const [scaleLevels, setScaleLevels] = useState<ScaleLevel[]>([]);
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (!tokens?.access_token || draftId) return;

    createDraftWorkout(tokens.access_token)
      .then((draft) => {
        initDraft(draft.id);
      })
      .catch(() => {
        setSaveStatus("error");
      });
  }, [draftId, initDraft, setSaveStatus, tokens?.access_token]);

  useEffect(() => {
    if (!tokens?.access_token) return;
    listScaleLevels(tokens.access_token).then(setScaleLevels).catch(() => {});
  }, [tokens?.access_token]);

  useEffect(() => {
    if (!draftId || !tokens?.access_token) return;

    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);

    setSaveStatus("saving");

    saveTimerRef.current = setTimeout(async () => {
      try {
        await updateDraftWorkout(
          tokens.access_token,
          draftId,
          toApiPayload(),
        );
        setSaveStatus("saved");
      } catch {
        setSaveStatus("error");
      }
    }, AUTOSAVE_DELAY_MS);

    return () => {
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    };
  }, [draftId, sections, setSaveStatus, title, toApiPayload, tokens?.access_token, type]);

  return (
    <div
      className="flex h-screen flex-col overflow-hidden"
      style={{
        background: "var(--bg, #0A0A0F)",
        color: "var(--text, #F0EDF8)",
        "--accent": "#9c799c",
      } as React.CSSProperties}
    >
      <CanvasHeader />
      <div className="hidden flex-1 overflow-hidden md:flex">
        <LeftPanel />
        <MiddlePanel scaleLevels={scaleLevels} />
        <RightPanel scaleLevels={scaleLevels} />
      </div>
      <div className="flex flex-1 overflow-hidden md:hidden">
        <MobileCanvas scaleLevels={scaleLevels} />
      </div>
    </div>
  );
}
