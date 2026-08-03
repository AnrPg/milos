"use client";

import { CSS } from "@dnd-kit/utilities";
import { useSortable } from "@dnd-kit/sortable";

import { useUiTranslations } from "@/i18n/ui";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import type { DraftExercise, DraftSection } from "@/types/workout";

type Props = {
  header: DraftExercise;
  section: DraftSection;
};

export function HeaderCard({ header, section }: Props) {
  const i18n = useUiTranslations();
  const { deleteExercise, updateExercise } = useWorkoutCreationStore();
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: header.localId,
    data: { type: "exercise", sectionId: section.localId },
  });

  return (
    <div
      ref={setNodeRef}
      className="flex items-center gap-3 border-y px-3 py-2"
      style={{
        borderColor: "var(--border-strong)",
        opacity: isDragging ? 0.4 : 1,
        transform: CSS.Transform.toString(transform),
        transition,
      }}
    >
      <button
        {...attributes}
        {...listeners}
        className="cursor-grab text-base"
        style={{ color: "var(--dim)" }}
        title={i18n("reorderHeader")}
        type="button"
      >
        ⠿
      </button>
      <span className="text-xs font-bold uppercase" style={{ color: "var(--primary)" }}>
        {i18n("headerLabel")}
      </span>
      <input
        className="min-w-0 flex-1 bg-transparent text-sm font-bold outline-none"
        onChange={(event) =>
          updateExercise(section.localId, header.localId, { name: event.target.value })
        }
        placeholder={i18n("headerTextPlaceholder")}
        type="text"
        value={header.name}
      />
      <input
        className="min-w-0 flex-1 bg-transparent text-xs outline-none"
        onChange={(event) =>
          updateExercise(section.localId, header.localId, {
            note: event.target.value || null,
          })
        }
        placeholder={i18n("headerNotePlaceholder")}
        type="text"
        value={header.note ?? ""}
      />
      <button
        className="px-2 py-1 text-xs"
        onClick={() => deleteExercise(section.localId, header.localId)}
        style={{ color: "var(--danger)" }}
        type="button"
      >
        {i18n("removee963907")}
      </button>
    </div>
  );
}
