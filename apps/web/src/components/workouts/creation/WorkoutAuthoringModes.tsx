"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";

import { useUiTranslations } from "@/i18n/ui";
import { useWorkoutCreationStore } from "@/stores/workout-creation";

import { FreeTextWorkoutEditor } from "./FreeTextWorkoutEditor";
import { QuickTextWorkoutEditor } from "./QuickTextWorkoutEditor";
import { WorkoutCreationCanvas } from "./WorkoutCreationCanvas";

export function WorkoutAuthoringModes() {
  const i18n = useUiTranslations();
  const router = useRouter();
  const searchParams = useSearchParams();
  const storeDraftId = useWorkoutCreationStore((state) => state.draftId);
  const requestedMode = searchParams.get("mode");
  const mode = requestedMode === "quick-text" || requestedMode === "free-text" ? requestedMode : "structured";
  const draftId = searchParams.get("draft") ?? storeDraftId;
  const [modeBarVisible, setModeBarVisible] = useState(false);

  function selectMode(nextMode: "structured" | "quick-text" | "free-text", selectedDraftId = draftId) {
    const params = new URLSearchParams(searchParams.toString());
    params.set("mode", nextMode);

    if (selectedDraftId) {
      params.set("draft", selectedDraftId);
    }

    router.replace(`/admin/workouts/new?${params.toString()}`);
  }

  return (
    <div className="flex min-h-[calc(100dvh-3.25rem)] flex-col" style={{ background: "var(--bg)" }}>
      <div
        className="fixed inset-x-0 top-[3.25rem] z-30 h-16"
        onFocus={() => setModeBarVisible(true)}
        onMouseEnter={() => setModeBarVisible(true)}
        aria-hidden
      />
      <div
        className="fixed inset-x-0 top-[7.25rem] z-30 flex items-center justify-center gap-1 border-b px-4 py-2 transition-transform duration-200"
        onFocus={() => setModeBarVisible(true)}
        onMouseEnter={() => setModeBarVisible(true)}
        onMouseLeave={() => setModeBarVisible(false)}
        style={{
          background: "var(--panel)",
          borderColor: "var(--dim)",
          transform: modeBarVisible ? "translateY(0)" : "translateY(-110%)",
        }}
        data-visible={modeBarVisible}
        role="tablist"
        aria-label={i18n("workoutAuthoringModeLabel")}
      >
        <ModeButton
          active={mode === "structured"}
          onClick={() => selectMode("structured")}
          label={i18n("authoringModeStructured")}
        />
        <ModeButton
          active={mode === "quick-text"}
          onClick={() => selectMode("quick-text")}
          label={i18n("authoringModeQuickText")}
        />
        <ModeButton
          active={mode === "free-text"}
          onClick={() => selectMode("free-text")}
          label={i18n("authoringModeFreeText")}
        />
      </div>

      <div className="min-h-0 flex-1">
        {mode === "quick-text" ? (
          <QuickTextWorkoutEditor
            draftId={draftId}
            onDraftReady={(id) => selectMode("quick-text", id)}
            onSwitchToStructured={(id) => selectMode("structured", id)}
          />
        ) : mode === "free-text" ? (
          <FreeTextWorkoutEditor
            draftId={draftId}
            onDraftReady={(id) => selectMode("free-text", id)}
          />
        ) : (
          <WorkoutCreationCanvas />
        )}
      </div>
    </div>
  );
}

function ModeButton({
  active,
  label,
  onClick,
}: {
  active: boolean;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={active}
      onClick={onClick}
      className="rounded-xl px-4 py-2 text-sm font-bold transition-colors"
      style={{
        background: active ? "var(--primary)" : "transparent",
        color: active ? "var(--primary-foreground, white)" : "var(--muted)",
      }}
    >
      {label}
    </button>
  );
}
