"use client";

import { useQuery } from "@tanstack/react-query";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";

import { fetchAdminWorkout, fetchWorkoutAuthoringSettings, WOD_ASSISTANT_AVAILABILITY_KEY } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { workoutPublishedHref } from "@/lib/workout-return";
import { useWorkoutCreationStore } from "@/stores/workout-creation";

import { FreeTextWorkoutEditor } from "./FreeTextWorkoutEditor";
import { QuickTextWorkoutEditor } from "./QuickTextWorkoutEditor";
import { SectionedWorkoutEditor } from "./SectionedWorkoutEditor";
import { WorkoutCreationCanvas } from "./WorkoutCreationCanvas";

type AuthoringMode = "structured" | "quick-text" | "free-text" | "sectioned";

/**
 * Free text is the only way to create new workouts. Structured and Quick Text
 * stay in the codebase (and keep editing workouts that were authored with
 * them), but their tabs are hidden. Flip this to bring the switcher back.
 */
const SHOW_AUTHORING_MODE_SWITCHER = false;

type Props = {
  /**
   * Opened from inside another screen (a class form, a member's programming):
   * the editor keeps its draft and mode in its own state instead of the
   * address, so the screen underneath stays exactly as the coach left it.
   */
  embedded?: boolean;
  /** Embedded only: open this draft (e.g. a member's copy of a class WOD) instead of a new one. */
  initialDraftId?: string | null;
  /** Embedded only: the new workout was published. */
  onPublished?: (workoutId: string) => void;
  /** Embedded only: the legacy structured canvas's cancel button. */
  onCancel?: () => void;
};

export function WorkoutAuthoringModes({ embedded = false, initialDraftId = null, onPublished, onCancel }: Props = {}) {
  const i18n = useUiTranslations();
  const router = useRouter();
  const organizationSlug = useOrganizationSlug();
  const searchParams = useSearchParams();
  const { tokens } = useSession();
  const storeDraftId = useWorkoutCreationStore((state) => state.draftId);
  // Embedded: the draft lives here, never in the address of the screen below.
  const [embeddedDraftId, setEmbeddedDraftId] = useState<string | null>(initialDraftId);
  const requestedMode = embedded ? null : searchParams.get("mode");
  const draftId = embedded ? embeddedDraftId : (searchParams.get("draft") ?? storeDraftId);
  const switcherMode: AuthoringMode =
    requestedMode === "quick-text" || requestedMode === "free-text" ? requestedMode : "structured";

  // Existing drafts open in the editor they were authored with, so legacy
  // structured or Quick Text content is never overwritten by a free-text save.
  const draftQuery = useQuery({
    queryKey: ["admin-workout-authoring-mode", draftId],
    enabled: !SHOW_AUTHORING_MODE_SWITCHER && Boolean(draftId && tokens?.access_token),
    queryFn: () => fetchAdminWorkout(tokens!.access_token, draftId!),
    staleTime: Infinity,
  });
  // ADR-180: the gym may switch the WOD assistant off; then every workout is
  // written in text sections. With it on, the coach can still switch it off
  // for one workout (the editor's «AI assistant» switch).
  const availability = useQuery({
    queryKey: WOD_ASSISTANT_AVAILABILITY_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchWorkoutAuthoringSettings(tokens!.access_token),
    staleTime: 60_000,
  });
  const assistantAvailable = availability.data?.wod_assistant_enabled !== false;
  // The coach's switch for this visit, keyed by draft so another draft starts fresh.
  const [assistantChoice, setAssistantChoice] = useState<{ draftId: string | null; useAssistant: boolean } | null>(null);
  const storedMode: AuthoringMode = SHOW_AUTHORING_MODE_SWITCHER
    ? switcherMode
    : draftId
      ? legacyEditorFor(draftQuery.data)
      : "free-text";
  const textMode = storedMode === "free-text" || storedMode === "sectioned";
  const chosen =
    assistantChoice && (assistantChoice.draftId === draftId || assistantChoice.draftId === null)
      ? assistantChoice.useAssistant
        ? "free-text"
        : "sectioned"
      : storedMode;
  const mode: AuthoringMode = textMode && !assistantAvailable ? "sectioned" : textMode ? chosen : storedMode;
  const resolvingDraft =
    (!SHOW_AUTHORING_MODE_SWITCHER && Boolean(draftId) && draftQuery.isPending) || availability.isLoading;

  // New workouts started from inside a library folder are created in that folder.
  const folderId = embedded ? null : searchParams.get("folder");
  const [modeBarVisible, setModeBarVisible] = useState(false);
  const hideTimerRef = useRef<number | null>(null);

  useEffect(() => {
    function clearHideTimer() {
      if (hideTimerRef.current !== null) {
        window.clearTimeout(hideTimerRef.current);
        hideTimerRef.current = null;
      }
    }

    function revealTemporarily() {
      clearHideTimer();
      setModeBarVisible(true);
      hideTimerRef.current = window.setTimeout(() => {
        setModeBarVisible(false);
      }, 1_400);
    }

    window.addEventListener("scroll", revealTemporarily, { capture: true, passive: true });
    return () => {
      window.removeEventListener("scroll", revealTemporarily, { capture: true });
      clearHideTimer();
    };
  }, []);

  function revealModeBar() {
    if (hideTimerRef.current !== null) {
      window.clearTimeout(hideTimerRef.current);
      hideTimerRef.current = null;
    }
    setModeBarVisible(true);
  }

  function hideModeBar() {
    if (hideTimerRef.current !== null) {
      window.clearTimeout(hideTimerRef.current);
      hideTimerRef.current = null;
    }
    setModeBarVisible(false);
  }

  function selectMode(nextMode: AuthoringMode, selectedDraftId = draftId) {
    if (embedded) {
      setEmbeddedDraftId(selectedDraftId);
      return;
    }
    const params = new URLSearchParams(searchParams.toString());
    params.set("mode", nextMode);

    if (selectedDraftId) {
      params.set("draft", selectedDraftId);
    }

    router.replace(adminHref(`/admin/workouts/new?${params.toString()}`, organizationSlug));
  }

  // Published: back to whoever opened the editor. A page visit goes to the
  // form it came from (`?return_to=`, ADR-176) or to the library.
  function published(workoutId: string) {
    if (embedded) {
      onPublished?.(workoutId);
      return;
    }
    router.push(workoutPublishedHref(new URLSearchParams(window.location.search), workoutId, adminHref("/admin/workouts", organizationSlug)));
  }

  if (resolvingDraft) {
    return <div className="min-h-[calc(100dvh-3.25rem)]" style={{ background: "var(--bg)" }} aria-busy="true" />;
  }

  return (
    <div className="flex min-h-[calc(100dvh-3.25rem)] flex-col" style={{ background: "var(--bg)" }}>
      {SHOW_AUTHORING_MODE_SWITCHER ? (
      <>
      <div
        className="fixed inset-x-0 top-[3.25rem] z-(--z-sticky) h-3"
        onFocus={revealModeBar}
        onMouseEnter={revealModeBar}
        aria-hidden
      />
      <div
        className="fixed inset-x-0 top-[3.25rem] z-(--z-nav) flex items-center justify-center gap-1 border-b px-4 py-2 shadow-lg transition-[opacity,transform] duration-200"
        onFocus={revealModeBar}
        onMouseEnter={revealModeBar}
        onMouseLeave={hideModeBar}
        onBlur={(event) => {
          if (!event.currentTarget.contains(event.relatedTarget as Node | null)) {
            hideModeBar();
          }
        }}
        style={{
          background: "var(--panel)",
          borderColor: "var(--dim)",
          boxShadow: "0 10px 24px color-mix(in srgb, var(--bg) 65%, transparent)",
          opacity: modeBarVisible ? 1 : 0,
          pointerEvents: modeBarVisible ? "auto" : "none",
          transform: modeBarVisible ? "translateY(0)" : "translateY(calc(-100% - 1px))",
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
      </>
      ) : null}

      <div className="min-h-0 flex-1">
        {mode === "quick-text" ? (
          <QuickTextWorkoutEditor
            draftId={draftId}
            folderId={folderId}
            onDraftReady={(id) => selectMode("quick-text", id)}
            onPublished={published}
            onSwitchToStructured={(id) => selectMode("structured", id)}
          />
        ) : mode === "free-text" ? (
          <FreeTextWorkoutEditor
            key="free-text"
            draftId={draftId}
            folderId={folderId}
            onDraftReady={(id) => selectMode("free-text", id)}
            onPublished={published}
            onUseSections={() => setAssistantChoice({ draftId, useAssistant: false })}
          />
        ) : mode === "sectioned" ? (
          <SectionedWorkoutEditor
            key="sectioned"
            draftId={draftId}
            folderId={folderId}
            onDraftReady={(id) => {
              setAssistantChoice((current) => (current && current.draftId === null ? { ...current, draftId: id } : current));
              selectMode("free-text", id);
            }}
            onPublished={published}
            assistantAvailable={assistantAvailable}
            onUseAssistant={() => setAssistantChoice({ draftId, useAssistant: true })}
          />
        ) : (
          embedded ? (
            <WorkoutCreationCanvas embedded initialDraftId={draftId} onCancel={onCancel} onPublished={(workout) => published(workout.id)} />
          ) : (
            <WorkoutCreationCanvas />
          )
        )}
      </div>
    </div>
  );
}

function legacyEditorFor(workout: Awaited<ReturnType<typeof fetchAdminWorkout>> | undefined): AuthoringMode {
  if (!workout) return "free-text";
  if (workout.authoring_mode === "quick_text") return "quick-text";
  if (workout.authoring_mode === "sectioned_text") return "sectioned";
  // New drafts default to "structured" before their first save; only drafts
  // that already hold structured sections need the structured canvas.
  const draftSections = (workout.draft_data as { sections?: unknown[] } | null | undefined)?.sections;
  if (workout.authoring_mode === "structured" && ((workout.sections?.length ?? 0) > 0 || (draftSections?.length ?? 0) > 0)) {
    return "structured";
  }
  return "free-text";
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
        color: active ? "var(--primary-contrast)" : "var(--muted)",
      }}
    >
      {label}
    </button>
  );
}
