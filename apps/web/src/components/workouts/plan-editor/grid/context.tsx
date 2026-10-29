"use client";

import { useTranslations } from "next-intl";
import { createContext, useContext } from "react";

import type { PlanSection } from "@/lib/structured-plan/types";
import type { ExerciseSuggestion } from "@/components/workouts/structured/editor-context";

import type { Msg } from "./model";
import type { PlanWriter } from "./store-adapter";

/** Which list the one grid popover shows, and next to what. */
export type PickerState = {
  rowId: string;
  mode: "menu" | "struct" | "measure";
  anchor: HTMLElement;
  /** Field to focus again when the list closes without a pick. */
  returnKey: string | null;
};

export type GridContextValue = {
  sectionId: string;
  plan: PlanSection;
  write: PlanWriter;
  phone: boolean;
  /** Focus a field once it is on screen (after the change that adds it renders). */
  focusKey: (key: string) => void;
  notesOpen: ReadonlySet<string>;
  openNote: (rowId: string) => void;
  openPicker: (picker: PickerState) => void;
  catalog: ExerciseSuggestion[];
  usedNames: string[];
};

export const GridContext = createContext<GridContextValue | null>(null);

export function useGrid(): GridContextValue {
  const value = useContext(GridContext);
  if (!value) throw new Error("useGrid must be used inside PlanGrid.");
  return value;
}

/** `PlanGrid` translations, plus a helper for model messages. */
export function useGridT() {
  const t = useTranslations("PlanGrid");
  const msg = (m: Msg | null | undefined) => (m ? t(m.key, m.values) : "");
  /** "sec" / "min" unit tokens are words; others ("/10", "cm") are symbols. */
  const unit = (token: string) => (token === "sec" ? t("unit.sec") : token === "min" ? t("unit.min") : token);
  return { t, msg, unit };
}
