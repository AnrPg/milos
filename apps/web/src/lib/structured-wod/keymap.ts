/**
 * ADR-270: every keyboard shortcut of the structured WOD editor, in one
 * place. The editor's key handler, the shortcut sheet («?»), the command
 * palette and the button tooltips all read this list, so a key shown to the
 * coach is always the key that works.
 *
 * Conventions (see the ADR for sources): Ctrl/⌘+K opens the command palette,
 * «?» the shortcut sheet, Esc closes; Ctrl/⌘ is written «Mod». Shortcuts that
 * edit the workout use Alt, never a bare letter, so they never fire while the
 * coach types; letter keys are matched on the physical key (`code`) because
 * Option+letter types a special character on a Mac.
 */

export type ShortcutId =
  | "palette"
  | "shortcuts"
  | "publish"
  | "saveNow"
  | "undo"
  | "redo"
  | "newRow"
  | "newSection"
  | "newHeading"
  | "deleteRow"
  | "deleteEmptyRow"
  | "rowAbove"
  | "rowBelow"
  | "moveUp"
  | "moveDown"
  | "duplicate"
  | "previousSection"
  | "nextSection"
  | "superset"
  | "details"
  | "note"
  | "preview"
  | "nextField"
  | "close";

export type ShortcutGroup = "general" | "write" | "move" | "row";

export type KeyCombo = {
  /** `KeyboardEvent.key` for named keys ("Enter", "ArrowUp", "?") or a letter matched on `code` ("k" → KeyK). */
  key: string;
  mod?: boolean;
  shift?: boolean;
  alt?: boolean;
};

export type Shortcut = {
  id: ShortcutId;
  group: ShortcutGroup;
  combos: KeyCombo[];
  /** Listed in the sheet only: the field or the browser handles it. */
  documentOnly?: boolean;
  /** Fires even while the coach types in a text field. */
  inFields: boolean;
  /** Fires outside text fields only (single keys such as «?»). */
  outsideFieldsOnly?: boolean;
};

export const SHORTCUTS: Shortcut[] = [
  { id: "palette", group: "general", combos: [{ key: "k", mod: true }], inFields: true },
  { id: "shortcuts", group: "general", combos: [{ key: "?", shift: true }, { key: "/", mod: true }], inFields: true },
  { id: "saveNow", group: "general", combos: [{ key: "s", mod: true }], inFields: true },
  { id: "publish", group: "general", combos: [{ key: "Enter", mod: true }], inFields: true },
  { id: "undo", group: "general", combos: [{ key: "z", mod: true }], inFields: true },
  { id: "redo", group: "general", combos: [{ key: "z", mod: true, shift: true }, { key: "y", mod: true }], inFields: true },
  { id: "preview", group: "general", combos: [{ key: "p", alt: true }], inFields: true },
  { id: "close", group: "general", combos: [{ key: "Escape" }], inFields: true, documentOnly: true },

  { id: "newRow", group: "write", combos: [{ key: "Enter" }], inFields: true },
  { id: "newSection", group: "write", combos: [{ key: "Enter", shift: true }], inFields: true },
  { id: "newHeading", group: "write", combos: [{ key: "h", alt: true }], inFields: true },
  { id: "nextField", group: "write", combos: [{ key: "Tab" }], inFields: true, documentOnly: true },
  { id: "deleteEmptyRow", group: "write", combos: [{ key: "Backspace" }], inFields: true, documentOnly: true },
  { id: "deleteRow", group: "write", combos: [{ key: "Backspace", mod: true, shift: true }], inFields: true },

  { id: "rowAbove", group: "move", combos: [{ key: "ArrowUp" }], inFields: true },
  { id: "rowBelow", group: "move", combos: [{ key: "ArrowDown" }], inFields: true },
  { id: "previousSection", group: "move", combos: [{ key: "ArrowUp", mod: true, shift: true }], inFields: true },
  { id: "nextSection", group: "move", combos: [{ key: "ArrowDown", mod: true, shift: true }], inFields: true },

  { id: "moveUp", group: "row", combos: [{ key: "ArrowUp", alt: true }], inFields: true },
  { id: "moveDown", group: "row", combos: [{ key: "ArrowDown", alt: true }], inFields: true },
  { id: "duplicate", group: "row", combos: [{ key: "ArrowDown", alt: true, shift: true }], inFields: true },
  { id: "superset", group: "row", combos: [{ key: "g", alt: true }], inFields: true },
  { id: "details", group: "row", combos: [{ key: "o", alt: true }], inFields: true },
  { id: "note", group: "row", combos: [{ key: "n", alt: true }], inFields: true },
];

export const SHORTCUT_GROUPS: ShortcutGroup[] = ["general", "write", "move", "row"];

export function isMacPlatform(): boolean {
  if (typeof navigator === "undefined") return false;
  const platform =
    (navigator as Navigator & { userAgentData?: { platform?: string } }).userAgentData?.platform ?? navigator.platform ?? "";
  return /mac|iphone|ipad|ipod/i.test(platform);
}

type KeyEventLike = Pick<KeyboardEvent, "key" | "code" | "ctrlKey" | "metaKey" | "shiftKey" | "altKey">;

function isLetter(key: string) {
  return /^[a-z]$/.test(key);
}

export function comboMatches(event: KeyEventLike, combo: KeyCombo, mac: boolean): boolean {
  const mod = mac ? event.metaKey : event.ctrlKey;
  // The other modifier (Ctrl on a Mac, ⌘/Win elsewhere) belongs to the system.
  const foreign = mac ? event.ctrlKey : event.metaKey;
  if (foreign || mod !== Boolean(combo.mod) || event.altKey !== Boolean(combo.alt)) return false;
  if (isLetter(combo.key)) {
    return event.code === `Key${combo.key.toUpperCase()}` && event.shiftKey === Boolean(combo.shift);
  }
  if (combo.key === "?") return event.key === "?";
  if (combo.key === "/") return event.key === "/" || event.code === "Slash";
  return event.key === combo.key && event.shiftKey === Boolean(combo.shift);
}

/** The shortcut an event means, or null. `inTextField`: the event comes from a field the coach types in. */
export function matchShortcut(event: KeyEventLike, { mac, inTextField }: { mac: boolean; inTextField: boolean }): ShortcutId | null {
  for (const shortcut of SHORTCUTS) {
    if (shortcut.documentOnly) continue;
    if (inTextField && !shortcut.inFields) continue;
    for (const combo of shortcut.combos) {
      if (!comboMatches(event, combo, mac)) continue;
      // «?» is a character: typed in a field it is just text.
      if (combo.key === "?" && inTextField) continue;
      return shortcut.id;
    }
  }
  return null;
}

const NAMED_KEYS: Record<string, { mac: string; other: string }> = {
  Enter: { mac: "↵", other: "Enter" },
  Escape: { mac: "Esc", other: "Esc" },
  Backspace: { mac: "⌫", other: "Backspace" },
  ArrowUp: { mac: "↑", other: "↑" },
  ArrowDown: { mac: "↓", other: "↓" },
  Tab: { mac: "⇥", other: "Tab" },
};

/** The keys of a combination as the coach's keyboard labels them, e.g. ["⌘", "K"] or ["Ctrl", "K"]. */
export function comboKeys(combo: KeyCombo, mac: boolean): string[] {
  const keys: string[] = [];
  if (combo.mod) keys.push(mac ? "⌘" : "Ctrl");
  if (combo.alt) keys.push(mac ? "⌥" : "Alt");
  if (combo.shift && combo.key !== "?") keys.push(mac ? "⇧" : "Shift");
  const named = NAMED_KEYS[combo.key];
  keys.push(named ? (mac ? named.mac : named.other) : combo.key.toUpperCase());
  return keys;
}

export function shortcutById(id: ShortcutId): Shortcut {
  return SHORTCUTS.find((shortcut) => shortcut.id === id)!;
}

/** A shortcut's first combination as one label ("Ctrl+K", "⌘K"), for tooltips. */
export function shortcutLabel(id: ShortcutId, mac: boolean): string {
  return comboKeys(shortcutById(id).combos[0], mac).join(mac ? "" : "+");
}
