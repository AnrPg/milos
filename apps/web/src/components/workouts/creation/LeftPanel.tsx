"use client";

import {
  DndContext,
  PointerSensor,
  TouchSensor,
  closestCenter,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import { SortableContext, verticalListSortingStrategy } from "@dnd-kit/sortable";

import { useWorkoutCreationStore } from "@/stores/workout-creation";

import { SectionChip } from "./SectionChip";
import { SectionConfig } from "./SectionConfig";

type Props = {
  onSectionSelected?: () => void;
  mobile?: boolean;
};

export function LeftPanel({ onSectionSelected, mobile = false }: Props) {
  const { sections, selectedSectionId, leftCollapsed, addSection, selectSection, reorderSections, setLeftCollapsed } =
    useWorkoutCreationStore();

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 300, tolerance: 5 } }),
  );

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (over && active.id !== over.id) {
      reorderSections(active.id as string, over.id as string);
    }
  }

  const selectedSection = sections.find((section) => section.localId === selectedSectionId) ?? null;

  if (!mobile && leftCollapsed) {
    return (
      <div
        className="flex w-10 shrink-0 cursor-pointer flex-col items-center justify-center"
        style={{ background: "var(--panel)", borderRight: "1px solid var(--dim)" }}
        onClick={() => setLeftCollapsed(false)}
      >
        <span
          className="text-xs font-bold uppercase tracking-widest"
          style={{
            writingMode: "vertical-rl",
            transform: "rotate(180deg)",
            color: "var(--muted)",
          }}
        >
          Sections
        </span>
        <span className="mt-2 text-xs" style={{ color: "var(--muted)" }}>
          &gt;
        </span>
      </div>
    );
  }

  return (
    <div
      className={`flex ${mobile ? "w-full" : "w-64 shrink-0"} flex-col overflow-hidden`}
      style={{ background: "var(--panel)", borderRight: "1px solid var(--dim)" }}
    >
      <div className="flex shrink-0 items-center justify-between px-4 py-3">
        <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          Sections
        </span>
        {!mobile ? (
          <button onClick={() => setLeftCollapsed(true)} className="text-xs" style={{ color: "var(--dim)" }}>
            &lt;
          </button>
        ) : null}
      </div>

      <div className="flex flex-1 flex-col gap-2 overflow-y-auto px-3 pb-3">
        <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
          <SortableContext items={sections.map((section) => section.localId)} strategy={verticalListSortingStrategy}>
            {sections.map((section) => (
              <SectionChip
                key={section.localId}
                section={section}
                isSelected={section.localId === selectedSectionId}
                onSelect={() => {
                  const nextId = section.localId === selectedSectionId ? null : section.localId;
                  selectSection(nextId);
                  if (nextId && onSectionSelected) onSectionSelected();
                }}
              />
            ))}
          </SortableContext>
        </DndContext>

        <button
          onClick={addSection}
          className="rounded-2xl px-3 py-2 text-center text-sm font-semibold transition-colors"
          style={{
            border: "1px dashed var(--dim)",
            color: "var(--muted)",
          }}
        >
          + Add section
        </button>
      </div>

      {selectedSection ? (
        <div className="shrink-0 overflow-y-auto border-t" style={{ borderColor: "var(--dim)", maxHeight: "60%" }}>
          <SectionConfig section={selectedSection} />
        </div>
      ) : null}
    </div>
  );
}
