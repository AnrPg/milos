"use client";

import { createContext, useContext } from "react";

import type { ScaleLevel, WorkoutDslManual } from "@/api/workouts";
import type { GridCell } from "@/lib/structured-wod/grid";

export type ExerciseSuggestion = { id: string; label: string; aliases: string[] };

/** What every part of the structured editor shares (ADR-270). */
export type StructuredEditorContextValue = {
  mac: boolean;
  scaleLevels: ScaleLevel[];
  exerciseCatalog: ExerciseSuggestion[];
  bodyweightLabel: string;
  /** Moves the caret to a field once it is on screen (after a row was added, say). */
  focusCell: (cell: GridCell) => void;
  /** Rows and sections whose details are open, by row key. */
  openDetails: ReadonlySet<string>;
  toggleDetails: (rowKey: string, open?: boolean) => void;
  /** Rows and sections showing their note field, by row key. */
  openNotes: ReadonlySet<string>;
  toggleNote: (rowKey: string, open?: boolean) => void;
};

export const StructuredEditorContext = createContext<StructuredEditorContextValue | null>(null);

export function useStructuredEditor(): StructuredEditorContextValue {
  const value = useContext(StructuredEditorContext);
  if (!value) throw new Error("useStructuredEditor must be used inside the structured WOD editor.");
  return value;
}

export function catalogFromManual(manual: Pick<WorkoutDslManual, "vocabulary"> | null): ExerciseSuggestion[] {
  const catalog = (manual?.vocabulary as { exercise_catalog?: Array<{ id: string; label: string; aliases?: string[] }> } | undefined)
    ?.exercise_catalog;
  return (catalog ?? []).map((entry) => ({ id: entry.id, label: entry.label, aliases: entry.aliases ?? [] }));
}

function fold(text: string) {
  return text
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .trim();
}

/**
 * Exercise names for what the coach typed: names already used in this
 * workout first (a coach repeats movements), then the exercise catalog by
 * label or alias; prefix matches before matches inside a word.
 */
export function suggestExercises(query: string, catalog: ExerciseSuggestion[], used: string[], limit = 8): ExerciseSuggestion[] {
  const text = fold(query);
  if (!text) return [];
  const seen = new Set<string>();
  const rank = (names: string[]) => {
    let best = Infinity;
    for (const name of names.map(fold)) {
      if (name === text) best = Math.min(best, 0);
      else if (name.startsWith(text)) best = Math.min(best, 1);
      else if (name.split(/[\s-]+/).some((word) => word.startsWith(text))) best = Math.min(best, 2);
      else if (name.includes(text)) best = Math.min(best, 3);
    }
    return best;
  };
  const own = used
    .filter((name) => name.trim())
    .map((name) => ({ id: `used:${fold(name)}`, label: name.trim(), aliases: [] as string[] }));
  return [...own.map((item) => ({ item, rank: rank([item.label]) - 0.5 })), ...catalog.map((item) => ({ item, rank: rank([item.label, ...item.aliases]) }))]
    .filter(({ rank: value }) => Number.isFinite(value))
    .sort((a, b) => a.rank - b.rank)
    .filter(({ item }) => {
      const key = fold(item.label);
      if (seen.has(key) || item.label === query.trim()) return false;
      seen.add(key);
      return true;
    })
    .slice(0, limit)
    .map(({ item }) => item);
}
