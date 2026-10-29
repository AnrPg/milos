/**
 * ADR-270: the structured WOD editor's keyboard map, in one place. The
 * editor's single key handler (`PlanEditor`), the shortcut sheet («?») and
 * the hint bar read it, so a key shown to the coach is the key that works.
 *
 * Letter shortcuts use Alt and are matched on the physical key (`code`)
 * because Option+letter types a special character on a Mac. «Mod» is ⌘ on a
 * Mac and Ctrl elsewhere.
 */
import { isMacPlatform } from "@/lib/structured-wod/keymap";

export { isMacPlatform };

export type PlanShortcutId =
  | "undo"
  | "redo"
  | "sheet"
  | "newSection"
  | "close"
  | "nextStep"
  | "prevStep"
  | "jumpStep"
  | "moveSectionUp"
  | "moveSectionDown"
  | "newExercise"
  | "actions"
  | "superset"
  | "structure"
  | "measure"
  | "perRound"
  | "rest"
  | "differentRound"
  | "note"
  | "deleteRow";

type KeyEventLike = Pick<KeyboardEvent, "key" | "code" | "ctrlKey" | "metaKey" | "shiftKey" | "altKey">;

/** What a key event means, or null. `inText`: typed in a text field (then «?» is just a character). */
export function matchPlanShortcut(e: KeyEventLike, { mac, inText }: { mac: boolean; inText: boolean }): { id: PlanShortcutId; step?: number } | null {
  const mod = mac ? e.metaKey : e.ctrlKey;
  const foreign = mac ? e.ctrlKey : e.metaKey;
  if (foreign) return null;
  if (mod && !e.altKey) {
    if (e.code === "KeyZ") return { id: e.shiftKey ? "redo" : "undo" };
    if (e.code === "KeyY") return { id: "redo" };
    if (e.code === "Slash") return { id: "sheet" };
    return null;
  }
  if (e.altKey && !mod) {
    if (e.key === "ArrowRight") return { id: "nextStep" };
    if (e.key === "ArrowLeft") return { id: "prevStep" };
    if (e.key === "ArrowUp") return { id: "moveSectionUp" };
    if (e.key === "ArrowDown") return { id: "moveSectionDown" };
    const digit = /^Digit([1-4])$/.exec(e.code);
    if (digit) return { id: "jumpStep", step: Number(digit[1]) - 1 };
    const letters: Record<string, PlanShortcutId> = {
      KeyM: "actions",
      KeyG: "superset",
      KeyT: "structure",
      KeyP: "measure",
      KeyV: "perRound",
      KeyR: "rest",
      KeyS: "differentRound",
      KeyN: "note",
    };
    return letters[e.code] ? { id: letters[e.code] } : null;
  }
  if (mod || e.altKey) return null;
  if (e.key === "?" && !inText) return { id: "sheet" };
  if (e.key === "Enter") return { id: e.shiftKey ? "newSection" : "newExercise" };
  if (e.key === "Escape") return { id: "close" };
  if (e.key === "Backspace") return { id: "deleteRow" };
  return null;
}

/** Key labels as the coach's keyboard shows them. */
export function keyLabel(keys: string, mac: boolean): string {
  return keys
    .replace(/Mod\+/g, mac ? "⌘" : "Ctrl+")
    .replace(/Alt\+/g, mac ? "⌥" : "Alt+")
    .replace(/Shift\+/g, mac ? "⇧" : "Shift+");
}

/** The shortcut sheet: groups of [keys, message key under `PlanEditor.sheet`]. */
export const SHEET: { group: "groupSection" | "groupExercises" | "groupGeneral"; rows: [string, string][] }[] = [
  {
    group: "groupSection",
    rows: [
      ["Shift+Enter", "newSection"],
      ["Alt+→ / Alt+←", "steps"],
      ["Alt+1 … 4", "jumpStep"],
      ["Esc", "close"],
      ["↑ ↓ Enter", "cards"],
      ["Alt+↑ / Alt+↓", "moveSection"],
    ],
  },
  {
    group: "groupExercises",
    rows: [
      ["Enter", "newExercise"],
      ["Alt+M", "actions"],
      ["Alt+G", "superset"],
      ["Alt+T", "structure"],
      ["Alt+P", "measure"],
      ["Alt+V", "perRound"],
      ["Alt+R", "rest"],
      ["Alt+S", "differentRound"],
      ["Alt+N", "note"],
      ["@keyEmptyCell", "emptyCell"],
      ["+5 / -0:05", "plus"],
      ["60→80", "spread"],
      ["@keyUnit", "unit"],
      ["@keyDeleteRow", "deleteRow"],
      ["Tab, ↑ ↓", "move"],
    ],
  },
  {
    group: "groupGeneral",
    rows: [
      ["Mod+Z", "undo"],
      ["Mod+Shift+Z", "redo"],
      ["?", "sheet"],
    ],
  },
];
