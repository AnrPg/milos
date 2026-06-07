"use client";

import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";

import { isSectionComplete } from "@/stores/workout-creation";
import type { DraftSection } from "@/types/workout";

type SectionChipProps = {
  section: DraftSection;
  isSelected: boolean;
  onSelect: () => void;
};

export function SectionChip({ section, isSelected, onSelect }: SectionChipProps) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: section.localId,
  });

  const complete = isSectionComplete(section);
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : 1,
  };

  return (
    <div
      ref={setNodeRef}
      onClick={onSelect}
      className="flex cursor-pointer select-none items-center gap-2 rounded-2xl px-3 py-2 transition-colors"
      style={{
        ...style,
        background: isSelected ? "var(--accent)" : "var(--card)",
        border: `1px solid ${isSelected ? "var(--accent)" : "var(--dim)"}`,
        color: isSelected ? "#0A0A0F" : "var(--text)",
      }}
    >
      <span
        {...attributes}
        {...listeners}
        className="cursor-grab text-sm"
        style={{ color: isSelected ? "#0A0A0F" : "var(--dim)" }}
        onClick={(event) => event.stopPropagation()}
      >
        ::
      </span>

      <span className="min-w-0 flex-1 truncate text-sm font-semibold">
        {section.name || "Unnamed section"}
      </span>

      <span
        className="shrink-0 text-xs font-bold"
        style={{ color: complete ? "var(--lime)" : "var(--amber)" }}
      >
        {complete ? "✓" : "!"}
      </span>
    </div>
  );
}
