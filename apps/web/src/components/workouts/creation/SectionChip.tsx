"use client";



import {useUiTranslations} from "@/i18n/ui";
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
  const i18n = useUiTranslations();
  const { attributes, listeners, setNodeRef, transform, transition, isDragging, isOver } = useSortable({
    id: section.localId,
    data: { type: "section" },
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
        background: isSelected ? "var(--accent)" : isOver ? "color-mix(in srgb, var(--accent) 20%, var(--card))" : "var(--card)",
        border: `1px solid ${isSelected || isOver ? "var(--accent)" : "var(--dim)"}`,
        color: isSelected ? "var(--bg)" : "var(--text)",
      }}
    >
      <span
        {...attributes}
        {...listeners}
        className="cursor-grab text-sm"
        style={{ color: isSelected ? "var(--bg)" : "var(--dim)" }}
        onClick={(event) => event.stopPropagation()}
      >
        ::
      </span>

      <span className="min-w-0 flex-1 truncate text-sm font-semibold">
        {section.name || i18n("unnamedSection109fa70")}
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
