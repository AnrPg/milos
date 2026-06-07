"use client";

import { useState } from "react";
import {
  DndContext,
  DragOverlay,
  PointerSensor,
  TouchSensor,
  closestCenter,
  useSensor,
  useSensors,
  type DragEndEvent,
  type DragStartEvent,
} from "@dnd-kit/core";
import { SortableContext, verticalListSortingStrategy } from "@dnd-kit/sortable";

import type { ScaleLevel } from "@/api/workouts";
import { useWorkoutCreationStore } from "@/stores/workout-creation";

import { ExerciseCard } from "./ExerciseCard";

type Props = {
  scaleLevels: ScaleLevel[];
};

export function MiddlePanel({ scaleLevels }: Props) {
  const { sections, selectedSectionId, addExercise, reorderExercises, setMobileView } = useWorkoutCreationStore();
  const [activeId, setActiveId] = useState<string | null>(null);

  const selectedSection = sections.find((section) => section.localId === selectedSectionId);
  const sectionOptions = sections.map((section) => ({ id: section.localId, name: section.name }));

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 300, tolerance: 5 } }),
  );

  function handleDragStart({ active }: DragStartEvent) {
    setActiveId(active.id as string);
  }

  function handleDragEnd({ active, over }: DragEndEvent) {
    setActiveId(null);
    if (!selectedSection || !over || active.id === over.id) return;
    reorderExercises(selectedSection.localId, active.id as string, over.id as string);
  }

  return (
    <div className="flex flex-1 flex-col overflow-hidden" style={{ background: "var(--bg)" }}>
      {selectedSection ? (
        <div className="flex shrink-0 items-center gap-3 border-b px-6 py-3" style={{ borderColor: "var(--dim)" }}>
          <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>
            {selectedSection.name || "Unnamed section"}
          </h2>
          <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
            {selectedSection.format.replaceAll("_", " ")}
          </span>
        </div>
      ) : (
        <div className="flex shrink-0 items-center gap-3 border-b px-6 py-3" style={{ borderColor: "var(--dim)" }}>
          <h2 className="text-lg font-bold" style={{ color: "var(--muted)" }}>
            Select a section to add exercises
          </h2>
        </div>
      )}

      <div className="flex flex-1 flex-col gap-3 overflow-y-auto px-6 py-4">
        {!selectedSection ? (
          <div className="flex flex-1 items-center justify-center">
            <p className="text-sm" style={{ color: "var(--dim)" }}>
              Select or add a section first
            </p>
          </div>
        ) : selectedSection.exercises.length === 0 ? (
          <div className="flex flex-1 flex-col items-center justify-center gap-3">
            <p className="text-sm" style={{ color: "var(--dim)" }}>
              No exercises yet
            </p>
            <button
              onClick={() => addExercise(selectedSection.localId)}
              className="rounded-2xl px-5 py-2 text-sm font-semibold"
              style={{ background: "var(--accent)", color: "#0A0A0F" }}
            >
              + Add exercise
            </button>
          </div>
        ) : (
          <>
            <DndContext
              sensors={sensors}
              collisionDetection={closestCenter}
              onDragStart={handleDragStart}
              onDragEnd={handleDragEnd}
            >
              <SortableContext
                items={selectedSection.exercises.map((exercise) => exercise.localId)}
                strategy={verticalListSortingStrategy}
              >
                {selectedSection.exercises.map((exercise) => (
                  <ExerciseCard
                    key={exercise.localId}
                    exercise={exercise}
                    section={selectedSection}
                    scaleLevels={scaleLevels}
                    sectionOptions={sectionOptions}
                  />
                ))}
              </SortableContext>
              <DragOverlay>
                {activeId ? (
                  <div
                    className="rounded-2xl border px-4 py-3 opacity-90"
                    style={{ background: "var(--card)", borderColor: "var(--accent)" }}
                  >
                    {selectedSection.exercises.find((exercise) => exercise.localId === activeId)?.name || "Exercise"}
                  </div>
                ) : null}
              </DragOverlay>
            </DndContext>

            <button
              onClick={() => {
                addExercise(selectedSection.localId);
                setMobileView("exercises");
              }}
              className="self-start rounded-2xl px-4 py-2 text-sm font-semibold"
              style={{ border: "1px dashed var(--dim)", color: "var(--muted)" }}
            >
              + Add exercise
            </button>
          </>
        )}
      </div>
    </div>
  );
}
