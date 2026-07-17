"use client";





import {useUiTranslations} from "@/i18n/ui";
import React, { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useRouter, useSearchParams } from "next/navigation";
import {
  DndContext,
  DragOverlay,
  PointerSensor,
  TouchSensor,
  closestCenter,
  pointerWithin,
  useSensor,
  useSensors,
  type CollisionDetection,
  type DragEndEvent,
  type DragOverEvent,
  type DragStartEvent,
  type UniqueIdentifier,
} from "@dnd-kit/core";

import { createDraftWorkout, fetchAdminWorkout, listScaleLevels, type ScaleLevel, type WorkoutRecord, updateDraftWorkout } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { USER_SYNC_EVENT, type UserSyncDetail } from "@/lib/user-sync";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { FORMAT_EXERCISE_CONTEXT, type DraftExercise, type DraftSection } from "@/types/workout";

import { CanvasHeader } from "./CanvasHeader";
import { LeftPanel } from "./LeftPanel";
import { MobileCanvas } from "./MobileCanvas";
import { MiddlePanel } from "./MiddlePanel";
import { RightPanel } from "./RightPanel";
import { ShortcutsModal } from "./ShortcutsModal";

const AUTOSAVE_DELAY_MS = 1500;

// ── Drag preview components ───────────────────────────────────────────────────

function ExerciseDragPreview({ exercise, section }: { exercise: DraftExercise; section: DraftSection }) {
  const i18n = useUiTranslations();
  const ctx = FORMAT_EXERCISE_CONTEXT[section.format];

  const intervalLabel =
    ctx.intervalMode === "odd_even"
      ? exercise.intervalAssignment === 1 ? i18n("odddc28f5f")
        : exercise.intervalAssignment === 2 ? i18n("even9e767ad")
        : null
      : ctx.intervalMode === "minute" && exercise.intervalAssignment !== null
        ? i18n("min7eb0cee") + (exercise.intervalAssignment)
        : null;

  const hasLoad = ctx.showLoad && exercise.loadMode !== "bw" && exercise.loadValue != null;

  return (
    <div
      className="rounded-2xl"
      style={{
        background: "var(--card, var(--panel-muted))",
        border: "1px solid var(--accent, var(--primary))",
        boxShadow: "0 12px 40px rgba(0,0,0,0.65)",
        opacity: 0.93,
      }}
    >
      <div className="flex flex-wrap items-center gap-3 px-4 py-3">
        <span className="shrink-0 select-none text-base" style={{ color: "var(--dim)" }}>⠿</span>
        {intervalLabel ? (
          <span
            className="shrink-0 rounded-lg px-2 py-0.5 text-xs font-bold"
            style={{ border: "1px solid var(--accent, var(--primary))", color: "var(--accent, var(--primary))" }}
          >
            {intervalLabel}
          </span>
        ) : null}
        <span className="min-w-[8rem] flex-1 text-base font-bold" style={{ color: "var(--text)" }}>
          {exercise.name || "—"}
        </span>
        {ctx.showSets ? (
          <>
            <span className="shrink-0 text-sm font-semibold" style={{ color: "var(--text)" }}>
              {exercise.sets}
            </span>
            <span className="shrink-0 text-sm" style={{ color: "var(--muted)" }}>{i18n("setsd6c8220")}</span>
          </>
        ) : null}
        {ctx.showPrescription ? (
          <>
            <span className="shrink-0 text-sm font-semibold" style={{ color: "var(--text)" }}>
              {exercise.prescriptionValue}
            </span>
            <span className="shrink-0 text-sm" style={{ color: "var(--muted)" }}>
              {exercise.prescriptionUnit}
            </span>
          </>
        ) : null}
        {hasLoad ? (
          <span className="shrink-0 text-sm" style={{ color: "var(--muted)" }}>
            {exercise.loadValue} {exercise.loadMode === "pct_1rm" ? i18n("percentOneRepMaxUnit") : i18n("kilogramsUnit")}
          </span>
        ) : ctx.showLoad && exercise.loadMode === "bw" ? (
          <span className="shrink-0 text-sm" style={{ color: "var(--muted)" }}>{i18n("bw4d64743")}</span>
        ) : null}
      </div>
    </div>
  );
}

function SectionDragPreview({ name }: { name: string }) {
  const i18n = useUiTranslations();
  return (
    <div
      className="rounded-2xl px-4 py-2.5 text-sm font-semibold"
      style={{
        background: "var(--panel, var(--panel))",
        border: "1px solid var(--accent, var(--primary))",
        color: "var(--text)",
        boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
        opacity: 0.93,
      }}
    >
      {name || i18n("unnamedSection109fa70")}
    </div>
  );
}

// ── Main canvas ───────────────────────────────────────────────────────────────

type ActiveDrag = {
  id: string;
  type: "section" | "exercise";
  name: string;
  width?: number;
  exercise?: DraftExercise;
  exerciseSection?: DraftSection;
};

type Props = {
  embedded?: boolean;
  onCancel?: () => void;
  onPublished?: (workout: WorkoutRecord) => void;
};

export function WorkoutCreationCanvas({ embedded = false, onCancel, onPublished }: Props) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const router = useRouter();
  const searchParams = useSearchParams();
  const urlDraftId = embedded ? null : searchParams.get("draft");
  const draftId = useWorkoutCreationStore((state) => state.draftId);
  const initDraft = useWorkoutCreationStore((state) => state.initDraft);
  const resetDraft = useWorkoutCreationStore((state) => state.resetDraft);
  const loadFromDraftData = useWorkoutCreationStore((state) => state.loadFromDraftData);
  const setSaveStatus = useWorkoutCreationStore((state) => state.setSaveStatus);
  const title = useWorkoutCreationStore((state) => state.title);
  const type = useWorkoutCreationStore((state) => state.type);
  const sections = useWorkoutCreationStore((state) => state.sections);
  const toApiPayload = useWorkoutCreationStore((state) => state.toApiPayload);
  const reorderSections = useWorkoutCreationStore((state) => state.reorderSections);
  const reorderExercises = useWorkoutCreationStore((state) => state.reorderExercises);
  const updateExercise = useWorkoutCreationStore((state) => state.updateExercise);
  const moveExercise = useWorkoutCreationStore((state) => state.moveExercise);
  const selectedSectionId = useWorkoutCreationStore((state) => state.selectedSectionId);
  const selectSection = useWorkoutCreationStore((state) => state.selectSection);

  const [scaleLevels, setScaleLevels] = useState<ScaleLevel[]>([]);
  const [activeDrag, setActiveDrag] = useState<ActiveDrag | null>(null);
  const [showShortcuts, setShowShortcuts] = useState(false);

  const addSection = useWorkoutCreationStore((state) => state.addSection);
  const addExercise = useWorkoutCreationStore((state) => state.addExercise);

  // Drag preview overlay: track pointer via DOM ref to avoid re-renders on every move
  const overlayRef = useRef<HTMLDivElement>(null);
  const [overlayInitPos, setOverlayInitPos] = useState({ x: -9999, y: -9999 });
  // Original selected section at drag start — restored if drag is cancelled
  const dragOriginalSectionIdRef = useRef<string | null>(null);
  // Guard against autosaving before the draft data has been loaded from the API
  const draftLoadedRef = useRef(false);
  const [editorSessionId] = useState(() =>
    typeof crypto !== "undefined" && typeof crypto.randomUUID === "function"
      ? crypto.randomUUID()
      : "editor-" + (Date.now()) + "-" + (Math.random().toString(16).slice(2)),
  );
  const editorSessionIdRef = useRef(editorSessionId);

  useEffect(() => {
    if (!activeDrag) return;

    function onPointerMove(e: PointerEvent) {
      if (overlayRef.current) {
        overlayRef.current.style.transform = "translate(" + (e.clientX + 10) + "px, " + (e.clientY - 18) + "px)";
      }
    }

    window.addEventListener("pointermove", onPointerMove, { passive: true });
    return () => window.removeEventListener("pointermove", onPointerMove);
  }, [activeDrag]);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 300, tolerance: 5 } }),
  );

  // Custom collision: for exercise drags, use the start-center point of the draggable
  // rect to detect hover over section chips in the LeftPanel. This lets the section
  // open as soon as the card's leading edge crosses into the chip — before the pointer
  // physically reaches the LeftPanel. For everything else, fall back to pointer-within
  // then closest-center.
  const collisionDetection = useCallback<CollisionDetection>((args) => {
    const { active, collisionRect, droppableContainers, droppableRects } = args;

    if (active.data.current?.type === "exercise") {
      const lcX = collisionRect.left;
      const lcY = (collisionRect.top + collisionRect.bottom) / 2;

      let bestId: UniqueIdentifier | null = null;
      let bestDy = Infinity;

      for (const [id, rect] of droppableRects) {
        if (droppableContainers.find((c) => c.id === id)?.data.current?.type !== "section") continue;
        if (lcX >= rect.left && lcX <= rect.right && lcY >= rect.top && lcY <= rect.bottom) {
          const dy = Math.abs(lcY - (rect.top + rect.bottom) / 2);
          if (dy < bestDy) { bestDy = dy; bestId = id; }
        }
      }

      if (bestId !== null) return [{ id: bestId }];
    }

    const hits = pointerWithin(args);
    return hits.length > 0 ? hits : closestCenter(args);
  }, []);

  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // When navigating to a different draft, reset the store so the load effect can run.
  useEffect(() => {
    if (urlDraftId && draftId && urlDraftId !== draftId) {
      resetDraft();
    }
  }, [urlDraftId, draftId, resetDraft]);

  // Resume an existing draft from URL, or create a fresh one.
  useEffect(() => {
    if (!tokens?.access_token || draftId) return;

    draftLoadedRef.current = false;

    if (urlDraftId) {
      initDraft(urlDraftId);
      fetchAdminWorkout(tokens.access_token, urlDraftId)
        .then((workout) => {
          loadFromDraftData(workout);
          draftLoadedRef.current = true;
        })
        .catch(() => { draftLoadedRef.current = true; });
    } else {
      createDraftWorkout(tokens.access_token)
        .then((draft) => {
          initDraft(draft.id);
          draftLoadedRef.current = true;
          if (!embedded) {
            router.replace(`/admin/workouts/new?draft=${draft.id}`);
          }
        })
        .catch(() => {
          setSaveStatus("error");
        });
    }
  }, [draftId, embedded, initDraft, loadFromDraftData, router, setSaveStatus, tokens?.access_token, urlDraftId]);

  // On remount (navigated away and back to the same draft URL), draftId is already set in
  // the Zustand store but draftLoadedRef is false (refs reset on unmount). Re-fetch to
  // restore fresh data and unblock autosave.
  useEffect(() => {
    if (!tokens?.access_token || !draftId || !urlDraftId || draftId !== urlDraftId) return;
    if (draftLoadedRef.current) return;

    fetchAdminWorkout(tokens.access_token, draftId)
      .then((workout) => {
        loadFromDraftData(workout);
        draftLoadedRef.current = true;
      })
      .catch(() => {
        draftLoadedRef.current = true;
      });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tokens?.access_token, draftId, urlDraftId]);

  useEffect(() => {
    if (!tokens?.access_token) return;
    listScaleLevels(tokens.access_token).then(setScaleLevels).catch(() => {});
  }, [tokens?.access_token]);

  useEffect(() => {
    function handleKey(e: KeyboardEvent) {
      const target = e.target as HTMLElement;
      const inInput = target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable;
      if (e.altKey && e.key === "e") {
        e.preventDefault();
        if (selectedSectionId) addExercise(selectedSectionId);
      } else if (e.altKey && e.key === "n") {
        e.preventDefault();
        addSection();
      } else if (!inInput && e.key === "?") {
        setShowShortcuts((prev) => !prev);
      }
    }
    document.addEventListener("keydown", handleKey);
    return () => document.removeEventListener("keydown", handleKey);
  }, [addExercise, addSection, selectedSectionId]);

  useEffect(() => {
    if (!tokens?.access_token) return;
    const accessToken = tokens.access_token;

    async function refreshCurrentDraft() {
      if (!draftId) return;

      try {
        const workout = await fetchAdminWorkout(accessToken, draftId);
        loadFromDraftData(workout);
        draftLoadedRef.current = true;
      } catch {
        // Ignore background refresh failures and keep the local draft state.
      }
    }

    function handleUserSync(event: Event) {
      const detail = (event as CustomEvent<UserSyncDetail>).detail;

      if (!detail?.scopes.includes("admin_workouts")) {
        return;
      }

      void listScaleLevels(accessToken).then(setScaleLevels).catch(() => {});

      const payloadDraftId =
        typeof detail.payload?.draft_id === "string"
          ? detail.payload.draft_id
          : typeof detail.payload?.workout_id === "string"
            ? detail.payload.workout_id
            : null;
      const payloadEditorSessionId =
        typeof detail.payload?.editor_session_id === "string" ? detail.payload.editor_session_id : null;

      if (
        draftId &&
        payloadDraftId === draftId &&
        payloadEditorSessionId !== editorSessionIdRef.current
      ) {
        void refreshCurrentDraft();
      }
    }

    window.addEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);

    return () => {
      window.removeEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);
    };
  }, [draftId, loadFromDraftData, tokens?.access_token]);

  useEffect(() => {
    if (!draftId || !tokens?.access_token || !draftLoadedRef.current) return;

    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);

    setSaveStatus("saving");

    saveTimerRef.current = setTimeout(async () => {
      try {
        await updateDraftWorkout(
          tokens.access_token,
          draftId,
          toApiPayload(),
          { editorSessionId: editorSessionIdRef.current },
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

  function handleDragStart({ active, activatorEvent }: DragStartEvent) {
    const dragType = active.data.current?.type as "section" | "exercise" | undefined;
    if (!dragType) return;

    // Remember which section was active so we can restore it if the drag is cancelled
    dragOriginalSectionIdRef.current = selectedSectionId;

    // Capture initial pointer position from the activator event for the preview overlay
    const pe = activatorEvent as PointerEvent;
    const initX = pe.clientX ?? -9999;
    const initY = pe.clientY ?? -9999;
    setOverlayInitPos({ x: initX + 10, y: initY - 18 });

    const width = active.rect.current.initial?.width;

    let name = "";
    let exercise: DraftExercise | undefined;
    let exerciseSection: DraftSection | undefined;

    if (dragType === "section") {
      name = sections.find((s) => s.localId === active.id)?.name ?? "";
    } else {
      for (const s of sections) {
        const ex = s.exercises.find((e) => e.localId === active.id);
        if (ex) {
          name = ex.name;
          exercise = ex;
          exerciseSection = s;
          break;
        }
      }
    }

    setActiveDrag({ id: active.id as string, type: dragType, name, width, exercise, exerciseSection });
  }

  // When an exercise is hovered over a section chip, open that section in the MiddlePanel
  // so the user can see where the exercise will land before releasing.
  function handleDragOver({ active, over }: DragOverEvent) {
    if (active.data.current?.type !== "exercise") return;
    if (over?.data.current?.type === "section") {
      selectSection(over.id as string);
    }
  }

  function handleDragEnd({ active, over }: DragEndEvent) {
    setActiveDrag(null);

    if (!over || active.id === over.id) {
      // Drag cancelled — restore the section that was open before the drag
      if (dragOriginalSectionIdRef.current) {
        selectSection(dragOriginalSectionIdRef.current);
      }
      return;
    }

    const activeType = active.data.current?.type as string | undefined;
    const overType = over.data.current?.type as string | undefined;

    if (activeType === "section") {
      if (overType === "section") {
        reorderSections(active.id as string, over.id as string);
      }
      return;
    }

    if (activeType === "exercise") {
      const activeSectionId = active.data.current?.sectionId as string;

      if (overType === "section") {
        const targetSectionId = over.id as string;
        if (activeSectionId !== targetSectionId) {
          moveExercise(active.id as string, activeSectionId, targetSectionId);
          selectSection(targetSectionId);
        }
        return;
      }

      if (overType === "exercise") {
        const overSectionId = over.data.current?.sectionId as string;

        if (activeSectionId === overSectionId) {
          reorderExercises(activeSectionId, active.id as string, over.id as string);

          // In complex_emom / even_odd, crossing group boundaries updates intervalAssignment
          const section = sections.find((s) => s.localId === activeSectionId);
          if (section && (section.format === "even_odd" || section.format === "complex_emom")) {
            const activeEx = section.exercises.find((e) => e.localId === active.id);
            const overEx = section.exercises.find((e) => e.localId === over.id);
            if (activeEx && overEx && activeEx.intervalAssignment !== overEx.intervalAssignment) {
              updateExercise(activeSectionId, active.id as string, {
                intervalAssignment: overEx.intervalAssignment,
              });
            }
          }
        } else {
          moveExercise(active.id as string, activeSectionId, overSectionId);
          selectSection(overSectionId);
        }
      }
    }
  }

  return (
    <div
      className={embedded ? "relative flex h-[min(88vh,54rem)] flex-col overflow-hidden" : "relative flex h-[calc(100dvh-3.25rem)] flex-col overflow-hidden"}
      style={{
        background: "var(--bg)",
        color: "var(--text)",
        "--accent": "var(--primary)",
      } as React.CSSProperties}
    >
      <CanvasHeader embedded={embedded} onCancel={onCancel} onPublished={onPublished} />
      <DndContext
        sensors={sensors}
        collisionDetection={collisionDetection}
        onDragStart={handleDragStart}
        onDragOver={handleDragOver}
        onDragEnd={handleDragEnd}
      >
        <div className="hidden flex-1 overflow-hidden md:flex">
          <LeftPanel showAllSections={activeDrag?.type === "exercise"} />
          <MiddlePanel scaleLevels={scaleLevels} />
          <RightPanel scaleLevels={scaleLevels} />
        </div>
        <div className="flex flex-1 overflow-hidden md:hidden">
          <MobileCanvas scaleLevels={scaleLevels} />
        </div>
        {/* Keep DragOverlay empty — position is handled by our manual portal below */}
        <DragOverlay dropAnimation={null} />
      </DndContext>

      {/* Keyboard shortcuts hint */}
      <button
        type="button"
        onClick={() => setShowShortcuts(true)}
        className={(embedded ? "absolute" : "fixed") + " bottom-4 end-4 z-40 hidden h-8 w-8 items-center justify-center rounded-full text-sm font-bold md:flex"}
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--muted)" }}
        title={i18n("keyboardShortcuts72933ee")}
      >
        ?
      </button>

      {showShortcuts && <ShortcutsModal onClose={() => setShowShortcuts(false)} />}

      {/* Manual drag preview: positioned via pointermove on window, bypasses dnd-kit coordinate issues */}
      {activeDrag
        ? createPortal(
            <div
              ref={overlayRef}
              style={{
                position: "fixed",
                top: 0,
                left: 0,
                transform: "translate(" + (overlayInitPos.x) + "px, " + (overlayInitPos.y) + "px)",
                zIndex: 9999,
                pointerEvents: "none",
                width: activeDrag.width,
                minWidth: "14rem",
                "--accent": "var(--primary)",
              } as React.CSSProperties}
            >
              {activeDrag.type === "exercise" && activeDrag.exercise && activeDrag.exerciseSection ? (
                <ExerciseDragPreview exercise={activeDrag.exercise} section={activeDrag.exerciseSection} />
              ) : (
                <SectionDragPreview name={activeDrag.name} />
              )}
            </div>,
            document.body,
          )
        : null}
    </div>
  );
}
