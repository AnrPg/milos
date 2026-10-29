/**
 * ADR-270: the structured WOD editor's state (`components/workouts/plan-editor`).
 *
 * Holds the WOD title and note, its sections (one `PlanSection` each), which
 * section is open and on which wizard step, and the field the editor should
 * focus next. Every mutation the editor's shortcuts need lives here, so the
 * shell (agent 3) and the exercise grid (agent 4) change the plan the same
 * way and undo / redo covers both.
 *
 * Undo / redo: a structural change (add / delete / move, flow, structure…) is
 * one step; typing (`updateRow`, `setCell`, `setParam`, notes, names) within
 * {@link TYPING_COALESCE_MS} of the previous typing is the same step, like the
 * mockup's `typing()`. `load` starts a fresh history.
 *
 * Row ids are unique across the whole WOD, so row mutations take only the row
 * id. A row lives in one block of its section (`block >= 0`) or in the
 * section's interrupt lane (`block === INTERRUPT_BLOCK`).
 *
 * Focus keys (`pendingFocus`), written by mutations, read and cleared by the
 * component that owns the field (`consumeFocus`):
 *   `card:<sectionId>`            closed section card
 *   `pick:<sectionId>`            step Ροή combobox
 *   `p:<sectionId>:<paramKey>`    step Χρόνος field
 *   `score:<sectionId>`           step Σκορ choice
 *   `snote:<sectionId>`           section note
 *   `r:<rowId>:name|dose|load|note|x:<measure>`  row fields (same values every round)
 *   `c:<rowId>:<col>:<cellKey>`   per-set / per-round cell
 * Build them with {@link focusKey}.
 */
import { create } from "zustand";

import type {
  PlanCell,
  PlanFlow,
  PlanMeasure,
  PlanMods,
  PlanParams,
  PlanRow,
  PlanSection,
  PlanStructure,
  PlanStructureKind,
} from "@/lib/structured-plan/types";
import {
  FLOW_RULES,
  MOD_FIELDS,
  PRESETS,
  convertFlow,
  emptySection,
  isGroupStructure,
  newId,
  newRow,
  structureDefaults,
  totalRounds,
} from "@/stores/structured-plan-shim";

/** One section of the WOD as the editor holds it. */
export type PlanEditorSection = { id: string; name: string; plan: PlanSection };

/** Wizard steps of an open section: 0 Ροή · 1 Χρόνος · 2 Ασκήσεις · 3 Σκορ. */
export type PlanWizardStep = 0 | 1 | 2 | 3;

/** What `serialize` returns and `load` takes. */
export type PlanEditorDocument = { title: string; note: string; sections: PlanEditorSection[] };

/** Where a note goes. */
export type PlanNoteTarget =
  | { kind: "wod" }
  | { kind: "section"; sectionId: string }
  | { kind: "row"; rowId: string };

/** A place to add a row when there is no row to add it after. */
export type PlanRowSlot = { sectionId: string; block: number };

/** A row and where it lives. */
export type PlanRowLocation = { sectionId: string; block: number; index: number; row: PlanRow };

/** Block index of the interrupt lane (`plan.interrupt`). */
export const INTERRUPT_BLOCK = -1;
/** Typing within this many ms of the previous typing is one undo step. */
export const TYPING_COALESCE_MS = 800;
const HISTORY_LIMIT = 200;

type Snapshot = Pick<PlanEditorState, "title" | "note" | "sections" | "openId" | "step">;

export type PlanEditorState = {
  title: string;
  note: string;
  sections: PlanEditorSection[];
  /** The one open section, or null when every section is a closed card. */
  openId: string | null;
  step: PlanWizardStep;
  /** Field to focus after the next render; see the module doc. */
  pendingFocus: string | null;
  canUndo: boolean;
  canRedo: boolean;

  // ── document ────────────────────────────────────────────────────────────
  /** Replaces everything and starts a fresh history. Opens nothing. */
  load: (doc: Partial<PlanEditorDocument>) => void;
  /** The WOD as plain data (sections deep-copied). */
  serialize: () => PlanEditorDocument;
  setTitle: (title: string) => void;
  /** WOD, section or exercise note (typing). */
  setNote: (target: PlanNoteTarget, text: string) => void;
  undo: () => void;
  redo: () => void;
  /** Returns and clears `pendingFocus` if it equals `key` (or any key when omitted). */
  consumeFocus: (key?: string) => string | null;
  setFocus: (key: string | null) => void;

  // ── sections ────────────────────────────────────────────────────────────
  /**
   * Adds an empty section (flow `sets`, no exercises yet) after `afterId`
   * (null / omitted: at the end), opens it on step Ροή and returns its id.
   */
  addSection: (afterId?: string | null) => string;
  deleteSection: (sectionId: string) => void;
  /** Moves a section one place up (-1) or down (+1). */
  moveSection: (sectionId: string, delta: -1 | 1) => void;
  renameSection: (sectionId: string, name: string) => void;
  /**
   * Opens a section (closing the open one). Without `step` it opens on
   * Ασκήσεις when it has exercises, else on its first step with content.
   */
  openSection: (sectionId: string, step?: PlanWizardStep) => void;
  /**
   * Closes the open section. A section closed on step Ροή before a flow was
   * ever chosen and with no exercise is dropped (the mockup's `close()`).
   */
  closeSection: () => void;
  /** Goes to a step of the open section; steps without content are refused. */
  setStep: (step: PlanWizardStep) => void;
  /** Next step with content; past Σκορ it closes the section. */
  nextStep: () => void;
  prevStep: () => void;

  // ── step Ροή / Χρόνος / Σκορ ────────────────────────────────────────────
  /** Switches the section's flow, keeping its exercises and values; moves to the next step. */
  setFlow: (sectionId: string, flow: PlanFlow) => void;
  /** Applies a preset (`PRESETS[].key`): its flow plus the values it fills; moves to the next step. */
  applyPreset: (sectionId: string, presetKey: string) => void;
  /** Sets one flow / add-on parameter as typed (typing). */
  setParam: (sectionId: string, key: keyof PlanParams, value: string) => void;
  /** Switches an add-on on or off (interrupt adds an empty interrupt row; off clears them). */
  toggleMod: (sectionId: string, mod: keyof PlanMods) => void;
  setScore: (sectionId: string, score: string) => void;
  /** Per scale level note (typing); empty text removes it. */
  setLevelNote: (sectionId: string, level: string, text: string) => void;

  /**
   * Replaces a section's plan with `recipe(plan)` (the recipe gets a deep
   * copy it may mutate or replace). `typing: true` coalesces it with other
   * typing into one undo step; otherwise it is its own step. `focus` sets
   * `pendingFocus`. For callers with their own pure plan mutations.
   */
  updatePlan: (sectionId: string, recipe: (plan: PlanSection) => PlanSection | void, opts?: { typing?: boolean; focus?: string | null }) => void;

  // ── rows (grid) ─────────────────────────────────────────────────────────
  /** Finds a row anywhere in the WOD. */
  findRow: (rowId: string) => PlanRowLocation | null;
  /**
   * Adds a row after the row `after` (same block, same group), or at the end
   * of a slot. A rest row starts at 30″. Focuses its name (or its rest value)
   * and returns its id.
   */
  addRow: (after: string | PlanRowSlot, kind?: PlanRow["kind"]) => string;
  /** Deletes a row; an emptied extra block goes too; a group of one is ungrouped. Focuses the row above. */
  deleteRow: (rowId: string) => void;
  /** Patches row fields (name, dose, load, x, note, exerciseRef…) (typing). */
  updateRow: (rowId: string, patch: Partial<Omit<PlanRow, "id">>) => void;
  /** Sets one value of a per-set / per-round cell (typing); missing cells before it are filled empty. */
  setCell: (rowId: string, col: number, key: keyof PlanCell, value: string) => void;
  /** Alt+G: joins the row to the group of the row above, or takes it out of its group. */
  toggleSuperset: (rowId: string) => void;
  /**
   * Alt+T: sets the structure of the row's unit. A group kind on a single row
   * pulls in the next ungrouped row (or a new empty one); a single kind on a
   * group ungroups it.
   */
  setStructure: (rowId: string, kind: PlanStructureKind) => void;
  /** Changes a structure's own fields (clusters, intra…) (typing). */
  updateStructure: (unitKey: string, patch: Partial<Record<string, string>>) => void;
  /** Alt+P: adds a measure to a row (no-op when it is already there). */
  addMeasure: (rowId: string, measure: PlanMeasure) => void;
  /** Removes a measure and its values. */
  removeMeasure: (rowId: string, measure: PlanMeasure) => void;
  /**
   * Alt+V: values per round on / off (flows other than `sets`). Returns false
   * (and changes nothing) when the row's block happens only once.
   */
  togglePerRound: (rowId: string) => boolean;
  /**
   * Alt+S: adds a block (a kind of round that alternates) with one empty
   * exercise, raising the rounds / sets / slots when there are fewer than
   * blocks. Returns the new row id, or null for flows without exercises.
   */
  addBlock: (sectionId: string) => string | null;
};

// ── helpers ──────────────────────────────────────────────────────────────

/** Builds the focus keys documented on this module. */
export const focusKey = {
  card: (sectionId: string) => `card:${sectionId}`,
  pick: (sectionId: string) => `pick:${sectionId}`,
  param: (sectionId: string, key: string) => `p:${sectionId}:${key}`,
  score: (sectionId: string) => `score:${sectionId}`,
  sectionNote: (sectionId: string) => `snote:${sectionId}`,
  row: (rowId: string, field: "name" | "dose" | "load" | "note" | `x:${string}`) => `r:${rowId}:${field}`,
  cell: (rowId: string, col: number, key: string) => `c:${rowId}:${col}:${key}`,
};

/** True when a flow has a Χρόνος step (it has parameters). */
export const hasTimeStep = (flow: PlanFlow) => FLOW_RULES[flow].fields.length > 0;
/** True when a flow has exercises (every flow but rest). */
export const hasExercises = (flow: PlanFlow) => FLOW_RULES[flow].layout !== "none";
/** Whether a wizard step has content for a flow (Ροή and Σκορ always do). */
export const stepAvailable = (flow: PlanFlow, step: PlanWizardStep) =>
  step === 1 ? hasTimeStep(flow) : step === 2 ? hasExercises(flow) : true;

function nextAvailable(flow: PlanFlow, step: PlanWizardStep, delta: 1 | -1): PlanWizardStep | null {
  for (let k = step + delta; k >= 0 && k <= 3; k += delta) if (stepAvailable(flow, k as PlanWizardStep)) return k as PlanWizardStep;
  return null;
}

/** The field a step starts on. */
export function firstFocusOf(section: PlanEditorSection, step: PlanWizardStep): string {
  const { plan } = section;
  if (step === 0) return focusKey.pick(section.id);
  if (step === 1) return focusKey.param(section.id, FLOW_RULES[plan.flow].fields[0]?.key ?? "");
  if (step === 3) return focusKey.score(section.id);
  const row = plan.blocks.flat()[0];
  return row ? focusKey.row(row.id, "name") : focusKey.param(section.id, FLOW_RULES[plan.flow].fields[0]?.key ?? "");
}

const listOf = (plan: PlanSection, block: number): PlanRow[] =>
  block === INTERRUPT_BLOCK ? (plan.interrupt ??= []) : (plan.blocks[block] ??= []);

function locate(sections: PlanEditorSection[], rowId: string): PlanRowLocation | null {
  for (const section of sections) {
    const { plan } = section;
    for (let block = INTERRUPT_BLOCK; block < plan.blocks.length; block++) {
      const list = block === INTERRUPT_BLOCK ? plan.interrupt ?? [] : plan.blocks[block];
      const index = list.findIndex((row) => row.id === rowId);
      if (index >= 0) return { sectionId: section.id, block, index, row: list[index] };
    }
  }
  return null;
}

/** Consecutive rows with the same group form one unit; its key is the group id or the row id. */
function unitOf(list: PlanRow[], index: number): { key: string; rows: PlanRow[]; start: number } {
  const row = list[index];
  if (!row.group) return { key: row.id, rows: [row], start: index };
  let start = index;
  while (start > 0 && list[start - 1].group === row.group) start--;
  let end = index;
  while (end + 1 < list.length && list[end + 1].group === row.group) end++;
  return { key: row.group, rows: list.slice(start, end + 1), start };
}

/** After grouping changes: a group left with one row is ungrouped, and its structure forgotten. */
function tidyGroups(plan: PlanSection, list: PlanRow[]) {
  const counts = new Map<string, number>();
  for (const row of list) if (row.group) counts.set(row.group, (counts.get(row.group) ?? 0) + 1);
  for (const row of list) {
    if (row.group && (counts.get(row.group) ?? 0) < 2) {
      if (plan.structs) delete plan.structs[row.group];
      row.group = null;
    }
  }
}

// ── history ──────────────────────────────────────────────────────────────

const history = { past: [] as Snapshot[], future: [] as Snapshot[], lastTyping: 0 };

const snapshotOf = (s: Snapshot): Snapshot => ({ title: s.title, note: s.note, sections: s.sections, openId: s.openId, step: s.step });

function pushPast(snapshot: Snapshot) {
  history.past.push(snapshot);
  if (history.past.length > HISTORY_LIMIT) history.past.shift();
  history.future = [];
}

/** Clears undo / redo (used by `load` and tests). */
export function resetPlanHistory() {
  history.past = [];
  history.future = [];
  history.lastTyping = 0;
  usePlanEditorStore.setState({ canUndo: false, canRedo: false });
}

const EMPTY: Snapshot & { pendingFocus: string | null } = { title: "", note: "", sections: [], openId: null, step: 0, pendingFocus: null };

/** The editor store. */
export const usePlanEditorStore = create<PlanEditorState>((set, get) => {
  /** A structural change: one undo step. */
  const commit = (fn: (draft: Snapshot) => void, focus?: string | null) => {
    const prev = get();
    pushPast(snapshotOf(prev));
    history.lastTyping = 0;
    const draft = { ...snapshotOf(prev), sections: prev.sections.map((s) => ({ ...s, plan: structuredClone(s.plan) })) };
    fn(draft);
    set({ ...draft, canUndo: true, canRedo: false, ...(focus !== undefined ? { pendingFocus: focus } : {}) });
  };
  /** Typing: coalesced into one undo step within TYPING_COALESCE_MS. */
  const typing = (fn: (draft: Snapshot) => void) => {
    const prev = get();
    const now = Date.now();
    if (now - history.lastTyping > TYPING_COALESCE_MS) pushPast(snapshotOf(prev));
    else history.future = [];
    history.lastTyping = now;
    const draft = { ...snapshotOf(prev), sections: prev.sections.map((s) => ({ ...s, plan: structuredClone(s.plan) })) };
    fn(draft);
    set({ ...draft, canUndo: history.past.length > 0, canRedo: false });
  };
  const section = (draft: Snapshot, id: string) => draft.sections.find((s) => s.id === id);
  const stepHistory = (direction: -1 | 1) => {
    const from = direction < 0 ? history.past : history.future;
    const to = direction < 0 ? history.future : history.past;
    const snapshot = from.pop();
    if (!snapshot) return;
    to.push(snapshotOf(get()));
    history.lastTyping = 0;
    set({ ...snapshot, pendingFocus: null, canUndo: history.past.length > 0, canRedo: history.future.length > 0 });
  };
  /** Row mutation helper: finds the row in a draft, or does nothing. */
  const onRow = (draft: Snapshot, rowId: string, fn: (plan: PlanSection, list: PlanRow[], index: number, sec: PlanEditorSection) => void) => {
    const at = locate(draft.sections, rowId);
    if (!at) return;
    const sec = section(draft, at.sectionId);
    if (!sec) return;
    fn(sec.plan, listOf(sec.plan, at.block), at.index, sec);
  };
  const chooseFlow = (sectionId: string, flow: PlanFlow, presetKey: string | null) => {
    const preset = presetKey ? PRESETS.find((p) => p.key === presetKey) ?? null : null;
    if (presetKey && !preset) return;
    let focus: string | null = null;
    commit((draft) => {
      const sec = section(draft, sectionId);
      if (!sec) return;
      sec.plan = convertFlow(sec.plan, flow, preset);
      draft.openId = sectionId;
      draft.step = nextAvailable(flow, 0, 1) ?? 3;
      focus = firstFocusOf(sec, draft.step);
    });
    set({ pendingFocus: focus });
  };

  return {
    ...EMPTY,
    canUndo: false,
    canRedo: false,

    load: (doc) => {
      set({ title: doc.title ?? "", note: doc.note ?? "", sections: structuredClone(doc.sections ?? []), openId: null, step: 0, pendingFocus: null });
      resetPlanHistory();
    },
    serialize: () => {
      const { title, note, sections } = get();
      return { title, note, sections: structuredClone(sections) };
    },
    setTitle: (title) => typing((draft) => { draft.title = title; }),
    setNote: (target, text) => typing((draft) => {
      if (target.kind === "wod") draft.note = text;
      else if (target.kind === "section") { const sec = section(draft, target.sectionId); if (sec) sec.plan.note = text; }
      else onRow(draft, target.rowId, (_plan, list, index) => { list[index].note = text; });
    }),
    undo: () => stepHistory(-1),
    redo: () => stepHistory(1),
    consumeFocus: (key) => {
      const current = get().pendingFocus;
      if (current === null || (key !== undefined && key !== current)) return null;
      set({ pendingFocus: null });
      return current;
    },
    setFocus: (key) => set({ pendingFocus: key }),

    addSection: (afterId = null) => {
      const id = newId();
      // A new section has no exercises until a flow is chosen; `sets` is a placeholder flow.
      const plan: PlanSection = { ...emptySection("sets"), blocks: [] };
      commit((draft) => {
        const at = afterId ? draft.sections.findIndex((s) => s.id === afterId) + 1 : draft.sections.length;
        draft.sections.splice(at > 0 ? at : draft.sections.length, 0, { id, name: "", plan });
        draft.openId = id;
        draft.step = 0;
      }, focusKey.pick(id));
      return id;
    },
    deleteSection: (sectionId) => {
      const index = get().sections.findIndex((s) => s.id === sectionId);
      if (index < 0) return;
      commit((draft) => {
        draft.sections.splice(index, 1);
        if (draft.openId === sectionId) draft.openId = null;
      });
      const next = get().sections[index - 1] ?? get().sections[0];
      set({ pendingFocus: next ? focusKey.card(next.id) : null });
    },
    moveSection: (sectionId, delta) => {
      const index = get().sections.findIndex((s) => s.id === sectionId);
      const to = index + delta;
      if (index < 0 || to < 0 || to >= get().sections.length) return;
      commit((draft) => {
        const [moved] = draft.sections.splice(index, 1);
        draft.sections.splice(to, 0, moved);
      });
    },
    renameSection: (sectionId, name) => typing((draft) => { const sec = section(draft, sectionId); if (sec) sec.name = name; }),
    openSection: (sectionId, step) => {
      const sec = get().sections.find((s) => s.id === sectionId);
      if (!sec) return;
      const { flow } = sec.plan;
      let target: PlanWizardStep = step ?? (sec.plan.blocks.flat().length ? 2 : hasTimeStep(flow) ? 1 : hasExercises(flow) ? 2 : 3);
      if (!stepAvailable(flow, target)) target = nextAvailable(flow, target, 1) ?? 3;
      set({ openId: sectionId, step: target, pendingFocus: firstFocusOf(sec, target) });
    },
    closeSection: () => {
      const { openId, step, sections } = get();
      if (!openId) return;
      const index = sections.findIndex((s) => s.id === openId);
      const sec = sections[index];
      if (sec && step === 0 && !sec.plan.blocks.flat().length && sec.plan.flow === "sets") {
        // Closed before a flow was picked: it was never written, drop it (one undo step).
        commit((draft) => { draft.sections.splice(index, 1); draft.openId = null; draft.step = 0; });
        const next = get().sections[index - 1] ?? get().sections[0];
        set({ pendingFocus: next ? focusKey.card(next.id) : null });
        return;
      }
      set({ openId: null, step: 0, pendingFocus: focusKey.card(openId) });
    },
    setStep: (step) => {
      const sec = get().sections.find((s) => s.id === get().openId);
      if (!sec || !stepAvailable(sec.plan.flow, step)) return;
      set({ step, pendingFocus: firstFocusOf(sec, step) });
    },
    nextStep: () => {
      const { step, openId, sections } = get();
      const sec = sections.find((s) => s.id === openId);
      if (!sec) return;
      const next = nextAvailable(sec.plan.flow, step, 1);
      if (next === null) get().closeSection();
      else get().setStep(next);
    },
    prevStep: () => {
      const { step, openId, sections } = get();
      const sec = sections.find((s) => s.id === openId);
      if (!sec) return;
      const prev = nextAvailable(sec.plan.flow, step, -1);
      if (prev !== null) get().setStep(prev);
    },

    setFlow: (sectionId, flow) => chooseFlow(sectionId, flow, null),
    applyPreset: (sectionId, presetKey) => {
      const preset = PRESETS.find((p) => p.key === presetKey);
      if (preset) chooseFlow(sectionId, preset.flow, presetKey);
    },
    setParam: (sectionId, key, value) => typing((draft) => { const sec = section(draft, sectionId); if (sec) sec.plan.params[key] = value; }),
    toggleMod: (sectionId, mod) => {
      const sec = get().sections.find((s) => s.id === sectionId);
      if (!sec || !FLOW_RULES[sec.plan.flow].mods.includes(mod)) return;
      const on = !sec.plan.mods?.[mod];
      const field = MOD_FIELDS[mod];
      commit((draft) => {
        const plan = section(draft, sectionId)!.plan;
        const mods = { ...(plan.mods ?? {}) };
        if (on) {
          mods[mod] = true;
          plan.params[field.key] ??= field.dflt;
          if (mod === "interrupt" && !plan.interrupt?.length) plan.interrupt = [newRow()];
        } else {
          delete mods[mod];
          delete plan.params[field.key];
          if (mod === "interrupt") plan.interrupt = [];
        }
        plan.mods = mods;
      }, on ? focusKey.param(sectionId, field.key) : undefined);
    },
    setScore: (sectionId, score) => commit((draft) => { const sec = section(draft, sectionId); if (sec) sec.plan.score = score; }),
    setLevelNote: (sectionId, level, text) => typing((draft) => {
      const sec = section(draft, sectionId);
      if (!sec) return;
      const notes = { ...(sec.plan.levelNotes ?? {}) };
      if (text) notes[level] = text;
      else delete notes[level];
      sec.plan.levelNotes = notes;
    }),

    updatePlan: (sectionId, recipe, opts = {}) => {
      if (!get().sections.some((s) => s.id === sectionId)) return;
      const apply = (draft: Snapshot) => {
        const sec = section(draft, sectionId)!;
        sec.plan = recipe(sec.plan) ?? sec.plan;
      };
      if (opts.typing) typing(apply);
      else commit(apply);
      if (opts.focus !== undefined) set({ pendingFocus: opts.focus });
    },
    findRow: (rowId) => locate(get().sections, rowId),
    addRow: (after, kind = "ex") => {
      const slot: PlanRowSlot | null = typeof after === "string"
        ? (() => { const at = locate(get().sections, after); return at ? { sectionId: at.sectionId, block: at.block } : null; })()
        : after;
      if (!slot) return "";
      const sec = get().sections.find((s) => s.id === slot.sectionId);
      if (!sec) return "";
      const afterRow = typeof after === "string" ? locate(get().sections, after)?.row ?? null : null;
      const grid = FLOW_RULES[sec.plan.flow].layout === "grid" && slot.block !== INTERRUPT_BLOCK;
      const row = kind === "rest"
        ? newRow("rest", { group: afterRow?.group ?? null, ...(grid ? { cells: [{ d: "30″" }] } : { dose: "30″" }) })
        : newRow("ex", { group: afterRow?.group ?? null });
      const focus = kind === "rest" ? (grid ? focusKey.cell(row.id, 0, "d") : focusKey.row(row.id, "dose")) : focusKey.row(row.id, "name");
      commit((draft) => {
        const plan = section(draft, slot.sectionId)!.plan;
        const list = listOf(plan, slot.block);
        const index = afterRow ? list.findIndex((r) => r.id === afterRow.id) + 1 : list.length;
        list.splice(index > 0 ? index : list.length, 0, row);
      }, focus);
      return row.id;
    },
    deleteRow: (rowId) => {
      const at = locate(get().sections, rowId);
      if (!at) return;
      let focus: string | null = null;
      commit((draft) => onRow(draft, rowId, (plan, list, index) => {
        list.splice(index, 1);
        if (plan.structs) delete plan.structs[rowId];
        tidyGroups(plan, list);
        if (!list.length && at.block >= 0 && plan.blocks.length > 1) plan.blocks.splice(at.block, 1);
        const prev = list[index - 1] ?? list[0];
        focus = prev ? focusKey.row(prev.id, "name") : null;
      }));
      set({ pendingFocus: focus });
    },
    updateRow: (rowId, patch) => typing((draft) => onRow(draft, rowId, (_plan, list, index) => { list[index] = { ...list[index], ...patch }; })),
    setCell: (rowId, col, key, value) => typing((draft) => onRow(draft, rowId, (_plan, list, index) => {
      const row = list[index];
      const cells = [...row.cells];
      while (cells.length <= col) cells.push({});
      cells[col] = { ...cells[col], [key]: value };
      list[index] = { ...row, cells };
    })),
    toggleSuperset: (rowId) => commit((draft) => onRow(draft, rowId, (plan, list, index) => {
      const row = list[index];
      if (row.group) {
        row.group = null;
      } else {
        const prev = list[index - 1];
        if (!prev) return;
        prev.group ??= newId();
        row.group = prev.group;
        // A single-row structure on the row above does not survive joining a group.
        if (plan.structs) { delete plan.structs[prev.id]; delete plan.structs[row.id]; }
      }
      tidyGroups(plan, list);
    })),
    setStructure: (rowId, kind) => {
      let focus: string = focusKey.row(rowId, "name");
      commit((draft) => onRow(draft, rowId, (plan, list, index) => {
        const unit = unitOf(list, index);
        const structs = (plan.structs ??= {});
        const first = unit.rows[0];
        if (isGroupStructure(kind) && unit.rows.length === 1) {
          // A group needs a partner: the next ungrouped row joins, or a new empty one.
          const group = newId();
          first.group = group;
          delete structs[first.id];
          const next = list[unit.start + 1];
          if (next && !next.group && next.kind === "ex") {
            next.group = group;
            if (!next.name) focus = focusKey.row(next.id, "name");
          } else {
            const partner = newRow("ex", { group });
            list.splice(unit.start + 1, 0, partner);
            focus = focusKey.row(partner.id, "name");
          }
          structs[group] = structureDefaults(kind);
        } else if (!isGroupStructure(kind) && unit.rows.length > 1) {
          for (const row of unit.rows) row.group = null;
          delete structs[unit.key];
          if (kind !== "single") structs[first.id] = structureDefaults(kind);
        } else if (kind === "single") {
          delete structs[unit.key];
        } else {
          structs[unit.key] = structureDefaults(kind);
        }
      }));
      set({ pendingFocus: focus });
    },
    updateStructure: (unitKey, patch) => typing((draft) => {
      for (const sec of draft.sections) {
        const current = sec.plan.structs?.[unitKey];
        if (current) { sec.plan.structs![unitKey] = { ...current, ...patch } as PlanStructure; return; }
      }
    }),
    addMeasure: (rowId, measure) => {
      const at = locate(get().sections, rowId);
      if (!at || at.row.extra?.includes(measure)) return;
      const sec = get().sections.find((s) => s.id === at.sectionId)!;
      const perCell = (FLOW_RULES[sec.plan.flow].layout === "grid" && at.block !== INTERRUPT_BLOCK) || at.row.perRound;
      const focus = measure === "side" ? focusKey.row(rowId, "name") : perCell ? focusKey.cell(rowId, 0, measure) : focusKey.row(rowId, `x:${measure}`);
      commit((draft) => onRow(draft, rowId, (_plan, list, index) => { list[index] = { ...list[index], extra: [...(list[index].extra ?? []), measure] }; }), focus);
    },
    removeMeasure: (rowId, measure) => commit((draft) => onRow(draft, rowId, (_plan, list, index) => {
      const row = list[index];
      const extra = (row.extra ?? []).filter((m) => m !== measure);
      const next: PlanRow = { ...row, extra };
      if (measure !== "side") {
        const key = measure as Exclude<PlanMeasure, "side">;
        if (row.x) { const x = { ...row.x }; delete x[key]; next.x = x; }
        next.cells = row.cells.map((cell) => { const c = { ...cell }; delete c[key]; return c; });
      }
      list[index] = next;
    })),
    togglePerRound: (rowId) => {
      const at = locate(get().sections, rowId);
      if (!at || at.row.kind !== "ex") return false;
      const sec = get().sections.find((s) => s.id === at.sectionId)!;
      const { plan } = sec;
      if (FLOW_RULES[plan.flow].layout === "grid" || at.block === INTERRUPT_BLOCK) return false;
      const blocks = Math.max(1, plan.blocks.length);
      if (totalRounds(plan) <= blocks && totalRounds(plan) !== Infinity) {
        // The block occurs once: nothing to vary.
        const occurs = Math.ceil((totalRounds(plan) - at.block) / blocks);
        if (occurs < 2) return false;
      }
      const on = !at.row.perRound;
      commit((draft) => onRow(draft, rowId, (_p, list, index) => {
        const row = list[index];
        if (on) list[index] = { ...row, perRound: true, cells: [{ d: row.dose, l: row.load, ...(row.x ?? {}) }] };
        else {
          const first = row.cells[0] ?? {};
          const x = Object.fromEntries((row.extra ?? []).filter((m) => m !== "side").map((m) => [m, first[m as keyof PlanCell] ?? ""]));
          list[index] = { ...row, perRound: false, dose: first.d ?? "", load: first.l ?? "", x };
        }
      }), on ? focusKey.cell(rowId, 1, at.row.load ? "l" : "d") : focusKey.row(rowId, "dose"));
      return true;
    },
    addBlock: (sectionId) => {
      const sec = get().sections.find((s) => s.id === sectionId);
      if (!sec || !hasExercises(sec.plan.flow)) return null;
      const row = newRow();
      commit((draft) => {
        const plan = section(draft, sectionId)!.plan;
        plan.blocks.push([row]);
        const k = plan.blocks.length;
        if (totalRounds(plan) < k) {
          if (plan.flow === "sets") plan.params.sets = String(k);
          else if (plan.flow === "emom") plan.params.times = String(k);
          else plan.params.rounds = String(k);
        }
      }, focusKey.row(row.id, "name"));
      return row.id;
    },
  };
});
