"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useMemo } from "react";
import { SortableContext, verticalListSortingStrategy } from "@dnd-kit/sortable";

import type { ScaleLevel } from "@/api/workouts";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import type { DraftSection } from "@/types/workout";
import { getFormatInstruction, type DraftExercise } from "@/types/workout";

import { ExerciseCard } from "./ExerciseCard";
import { FormatTooltip } from "./FormatTooltip";

type Props = {
  scaleLevels: ScaleLevel[];
};

type ExerciseGroup = {
  label: string;
  color: string;
  exercises: DraftExercise[];
};

export function MiddlePanel({ scaleLevels }: Props) {
  const i18n = useUiTranslations();
  const { sections, selectedSectionId, addExercise, setMobileView, updateSection } = useWorkoutCreationStore();

  const selectedSection = sections.find((section) => section.localId === selectedSectionId);
  const sectionOptions = sections.map((section) => ({ id: section.localId, name: section.name }));

  const exerciseGroups = useMemo((): ExerciseGroup[] | null => {
    if (!selectedSection) return null;
    const { format, exercises } = selectedSection;

    if (format === "even_odd") {
      const odd = exercises.filter((e) => e.intervalAssignment === 1);
      const even = exercises.filter((e) => e.intervalAssignment === 2);
      const both = exercises.filter((e) => e.intervalAssignment !== 1 && e.intervalAssignment !== 2);
      return [
        { label: i18n("oddMinutes60s3073e4b"), color: "var(--accent)", exercises: odd },
        { label: i18n("evenMinutes60sde09c9b"), color: "var(--lime)", exercises: even },
        ...(both.length > 0 ? [{ label: i18n("bothUnassigned36e7301"), color: "var(--dim)", exercises: both }] : []),
      ];
    }

    if (format === "complex_emom") {
      const byMinute = new Map<number, DraftExercise[]>();
      const unassigned: DraftExercise[] = [];

      for (const ex of exercises) {
        if (ex.intervalAssignment === null) {
          unassigned.push(ex);
        } else {
          const list = byMinute.get(ex.intervalAssignment) ?? [];
          list.push(ex);
          byMinute.set(ex.intervalAssignment, list);
        }
      }

      const minuteCount = (selectedSection.formatParams.minute_count as number) || 0;
      const maxAssigned = byMinute.size > 0 ? Math.max(...byMinute.keys()) : 0;
      const totalMinutes = Math.max(minuteCount, maxAssigned);

      if (totalMinutes === 0) return null;

      const groups: ExerciseGroup[] = [];
      for (let min = 1; min <= totalMinutes; min++) {
        const exs = byMinute.get(min) ?? [];
        const dur = (selectedSection.formatParams["interval_seconds_" + (min)] as number)
          ?? (selectedSection.formatParams.interval_seconds as number)
          ?? 60;
        const durLabel = dur >= 60
          ? (Math.floor(dur / 60)) + "min" + (dur % 60 > 0 ? `${dur % 60}s` : "")
          : (dur) + "s";
        groups.push({ label: i18n("roundec7b598") + (min) + " · " + (durLabel), color: "var(--accent)", exercises: exs });
      }

      if (unassigned.length > 0) {
        groups.push({ label: i18n("unassignede57016e"), color: "var(--dim)", exercises: unassigned });
      }

      return groups;
    }

    return null;
  }, [selectedSection]);

  return (
    <div className="flex flex-1 flex-col overflow-hidden" style={{ background: "var(--bg)" }}>
      {selectedSection ? (
        <div
          className="flex shrink-0 flex-col border-b px-6 py-3"
          style={{ borderColor: "var(--dim)" }}
        >
          <div className="flex items-center gap-3">
            <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>
              {selectedSection.name || i18n("unnamedSection109fa70")}
            </h2>
            <FormatTooltip format={selectedSection.format}>
              <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
                {selectedSection.format.replaceAll("_", " ")}
              </span>
            </FormatTooltip>
          </div>
          {(() => {
            const instr = getFormatInstruction(selectedSection.format, selectedSection.formatParams);
            return instr ? (
              <div className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
                {instr}
              </div>
            ) : null;
          })()}
          <textarea
            rows={1}
            placeholder={i18n("sectionNoteOptional5ec0d68")}
            className="mt-1 w-full resize-none bg-transparent text-xs outline-none"
            style={{ color: "var(--muted)" }}
            value={selectedSection.note ?? ""}
            onChange={(e) => updateSection(selectedSection.localId, { note: (e.target.value as DraftSection["note"]) || null })}
          />
        </div>
      ) : (
        <div
          className="flex shrink-0 items-center gap-3 border-b px-6 py-3"
          style={{ borderColor: "var(--dim)" }}
        >
          <h2 className="text-lg font-bold" style={{ color: "var(--muted)" }}>
            {i18n("selectASectionToAddExercisese9ab874")}
          </h2>
        </div>
      )}

      <div className="flex flex-1 flex-col gap-3 overflow-y-auto px-6 py-4">
        {!selectedSection ? (
          <div className="flex flex-1 items-center justify-center">
            <p className="text-sm" style={{ color: "var(--dim)" }}>
              {i18n("selectOrAddASectionFirstc66d608")}
            </p>
          </div>
        ) : selectedSection.exercises.length === 0 ? (
          <div className="flex flex-1 flex-col items-center justify-center gap-3">
            <p className="text-sm" style={{ color: "var(--dim)" }}>
              {i18n("noExercisesYet71ff283")}
            </p>
            <button
              onClick={() => addExercise(selectedSection.localId)}
              className="rounded-2xl px-5 py-2 text-sm font-semibold"
              style={{ background: "var(--accent)", color: "var(--bg)" }}
            >
              {i18n("addExercise7d65b0e")}
            </button>
          </div>
        ) : (
          <>
            <SortableContext
              items={selectedSection.exercises.map((exercise) => exercise.localId)}
              strategy={verticalListSortingStrategy}
            >
              {exerciseGroups ? (
                exerciseGroups.map((group) => (
                  <div key={group.label}>
                    {group.exercises.length > 0 || exerciseGroups.length > 1 ? (
                      <div className="mb-2 mt-1 flex items-center gap-2">
                        <span
                          className="text-xs font-bold uppercase tracking-widest"
                          style={{ color: group.color }}
                        >
                          {group.label}
                        </span>
                        <div
                          className="h-px flex-1"
                          style={{ background: group.color, opacity: 0.2 }}
                        />
                      </div>
                    ) : null}
                    <div className="flex flex-col gap-3">
                      {group.exercises.map((exercise) => (
                        <ExerciseCard
                          key={exercise.localId}
                          exercise={exercise}
                          section={selectedSection}
                          scaleLevels={scaleLevels}
                          sectionOptions={sectionOptions}
                        />
                      ))}
                    </div>
                  </div>
                ))
              ) : (
                selectedSection.exercises.map((exercise) => (
                  <ExerciseCard
                    key={exercise.localId}
                    exercise={exercise}
                    section={selectedSection}
                    scaleLevels={scaleLevels}
                    sectionOptions={sectionOptions}
                  />
                ))
              )}
            </SortableContext>

            <button
              onClick={() => {
                addExercise(selectedSection.localId);
                setMobileView("exercises");
              }}
              className="self-start rounded-2xl px-4 py-2 text-sm font-semibold"
              style={{ border: "1px dashed var(--dim)", color: "var(--muted)" }}
            >
              {i18n("addExercise7d65b0e")}
            </button>
          </>
        )}
      </div>
    </div>
  );
}
