"use client";

import { useTranslations } from "next-intl";
import { createContext, useContext, useSyncExternalStore } from "react";

import type { PlanSection } from "@/lib/structured-plan/types";
import type { ExerciseSuggestion } from "./exercise-catalog";

import { isMacPlatform, keyLabel } from "../keymap";

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
  // Only PlanGrid renders the parts that call this, inside its provider.
  return useContext(GridContext)!;
}

/** The grid's shortcuts, lower case (`kbd` writes them as the keyboard shows them). */
const SHORTCUTS = [
  ["menu", "alt+m"],
  ["struct", "alt+t"],
  ["measure", "alt+p"],
  ["perRound", "alt+v"],
  ["note", "alt+n"],
  ["superset", "alt+g"],
  ["rest", "alt+r"],
  ["round", "alt+s"],
  ["enter", "enter"],
] as const;
export const SHORTCUT = Object.fromEntries(SHORTCUTS) as Record<(typeof SHORTCUTS)[number][0], string>;

const noSubscribe = () => () => {};
const CORE_UNITS = new Set(["per500m", "outOf10", "repsLeft", "zone", "cm", "m", "sec"]);

/** `PlanGrid` and `PlanCore` translations, plus helpers for model messages and unit codes. */
export function useGridT() {
  const t = useTranslations("PlanGrid");
  const core = useTranslations("PlanCore");
  const msg = (m: Msg | null | undefined) => (m ? t(m.key, m.values) : "");
  /** Unit codes: the library's (`PlanCore.unit.*`), "min", or a literal ("cal"). */
  const unit = (token: string) => (CORE_UNITS.has(token) ? core(`unit.${token}`) : token === "min" ? t("unit.min") : token);
  const mac = useSyncExternalStore(noSubscribe, isMacPlatform, () => false);
  /** A shortcut as this keyboard writes it ("Alt+S", "⌥S"). */
  const kbd = (keys: string) => keyLabel(keys.replace(/\b\w/g, (c) => c.toUpperCase()), mac);
  return { t, core, msg, unit, kbd };
}
