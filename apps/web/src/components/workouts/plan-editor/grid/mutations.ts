/**
 * ADR-270: every change the grid makes to a section, as pure functions
 * (plan in, new plan out). The store applies them with its undo history; the
 * grid never mutates a plan it read from the store.
 */
import type { PlanCell, PlanMeasure, PlanRow, PlanSection, PlanStructureKind } from "@/lib/structured-plan/types";

import { isGroupStructure, occurrences, structOf, structureDefaults, totalRounds, unitKey, unitsOf } from "./lib-shim";

export type ValueKey = keyof PlanCell;

/** Where a row lives: block index, or -1 for the interrupt lane. */
export type RowAt = { b: number; i: number; row: PlanRow; list: PlanRow[] };

export const newId = () =>
  typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `r${Math.random().toString(36).slice(2)}`;

export function newRow(kind: PlanRow["kind"] = "ex", init: Partial<PlanRow> = {}): PlanRow {
  return { id: newId(), kind, name: "", dose: "", load: "", cells: [], group: null, ...init };
}

export const listOf = (plan: PlanSection, b: number): PlanRow[] => (b === -1 ? (plan.interrupt ??= []) : (plan.blocks[b] ??= []));

export function findRow(plan: PlanSection, rowId: string): RowAt | null {
  for (let b = -1; b < plan.blocks.length; b++) {
    const list = b === -1 ? (plan.interrupt ?? []) : plan.blocks[b]!;
    const i = list.findIndex((r) => r.id === rowId);
    if (i >= 0) return { b, i, row: list[i]!, list };
  }
  return null;
}

/** Copies the plan, applies `fn` to the copy and returns it. */
export function edit(plan: PlanSection, fn: (draft: PlanSection) => void): PlanSection {
  const draft = structuredClone(plan);
  fn(draft);
  return draft;
}

const withRow = (plan: PlanSection, rowId: string, fn: (row: PlanRow, at: RowAt, draft: PlanSection) => void) =>
  edit(plan, (draft) => {
    const at = findRow(draft, rowId);
    if (at) fn(at.row, at, draft);
  });

export const setRowFields = (plan: PlanSection, rowId: string, patch: Partial<Pick<PlanRow, "name" | "dose" | "load" | "note" | "exerciseRef">>) =>
  withRow(plan, rowId, (row) => Object.assign(row, patch));

export const setRowMeasure = (plan: PlanSection, rowId: string, key: Exclude<PlanMeasure, "side">, value: string) =>
  withRow(plan, rowId, (row) => {
    row.x = { ...(row.x ?? {}), [key]: value };
  });

/** One value of one set / round column. */
export const setCell = (plan: PlanSection, rowId: string, col: number, key: ValueKey, value: string) =>
  withRow(plan, rowId, (row) => {
    while (row.cells.length <= col) row.cells.push({});
    row.cells[col] = { ...row.cells[col], [key]: value };
  });

/** Adds a row after `afterId` (or at the end of block `b`); it joins the group of the row it follows. */
export function addRow(plan: PlanSection, where: { afterId?: string; b?: number }, kind: PlanRow["kind"] = "ex"): { plan: PlanSection; rowId: string } {
  let rowId = "";
  const next = edit(plan, (draft) => {
    const after = where.afterId ? findRow(draft, where.afterId) : null;
    const b = after?.b ?? where.b ?? 0;
    const list = listOf(draft, b);
    const at = after ? after.i + 1 : list.length;
    const group = after?.row.group ?? null;
    const grid = draft.flow === "sets" && b !== -1;
    const row =
      kind === "rest"
        ? newRow("rest", grid ? { group, cells: [{ d: "30″" }] } : { group, dose: "30″" })
        : newRow("ex", { group });
    rowId = row.id;
    list.splice(at, 0, row);
  });
  return { plan: next, rowId };
}

/** Deletes a row; an emptied extra block goes too, and a group of one is no group. */
export const deleteRow = (plan: PlanSection, rowId: string) =>
  edit(plan, (draft) => {
    const at = findRow(draft, rowId);
    if (!at) return;
    at.list.splice(at.i, 1);
    const g = at.row.group;
    if (g) {
      const left = at.list.filter((r) => r.group === g);
      if (left.length === 1) {
        left[0]!.group = null;
        delete draft.structs?.[g];
      }
    }
    delete draft.structs?.[rowId];
    if (!at.list.length && at.b >= 0 && draft.blocks.length > 1) draft.blocks.splice(at.b, 1);
  });

/** A new kind of round (block); a block needs a round to happen in, so the count grows to fit. */
export function addRound(plan: PlanSection): { plan: PlanSection; rowId: string } {
  const row = newRow();
  const next = edit(plan, (draft) => {
    draft.blocks.push([row]);
    const k = draft.blocks.length;
    if (totalRounds(draft) < k) {
      if (draft.flow === "sets") draft.params.sets = String(k);
      else if (draft.flow === "emom") draft.params.times = String(k);
      else draft.params.rounds = String(k);
    }
  });
  return { plan: next, rowId: row.id };
}

/** Per-round values exist where a block runs more than once (never in Σετ, which is per set already). */
export function canPerRound(plan: PlanSection, b: number) {
  return plan.flow !== "sets" && plan.flow !== "rest" && b >= 0 && occurrences(plan, b).list.length > 1;
}

/** Alt+V: same values every round ⇄ one value per round; nothing typed is lost. */
export const togglePerRound = (plan: PlanSection, rowId: string) =>
  withRow(plan, rowId, (row) => {
    const keys = (row.extra ?? []).filter((k): k is Exclude<PlanMeasure, "side"> => k !== "side");
    if (row.perRound) {
      const c = row.cells[0] ?? {};
      row.dose = c.d ?? "";
      row.load = c.l ?? "";
      row.x = Object.fromEntries(keys.map((k) => [k, c[k] ?? ""]));
      row.perRound = false;
    } else {
      const first: PlanCell = { d: row.dose, l: row.load, ...(row.x ?? {}) };
      row.cells = [first, ...row.cells.slice(1)];
      row.perRound = true;
    }
  });

/** Alt+G: joins the row above's group (or starts one with it); again leaves it. */
export const toggleSuperset = (plan: PlanSection, rowId: string) =>
  edit(plan, (draft) => {
    const at = findRow(draft, rowId);
    if (!at) return;
    const { row, list, i } = at;
    if (row.group) {
      const g = row.group;
      row.group = null;
      const left = list.filter((r) => r.group === g);
      if (left.length === 1) {
        left[0]!.group = null;
        delete draft.structs?.[g];
      }
      return;
    }
    const prev = list[i - 1];
    if (!prev) return;
    prev.group ??= newId();
    row.group = prev.group;
  });

/**
 * Alt+T: the structure of the unit holding `rowId`. A group structure on a
 * single row takes the next row as partner (or a new empty one); a single
 * structure on a group splits it.
 */
export function setStruct(plan: PlanSection, rowId: string, kind: PlanStructureKind): { plan: PlanSection; focusRowId: string | null } {
  let focusRowId: string | null = null;
  const next = edit(plan, (draft) => {
    const at = findRow(draft, rowId);
    if (!at) return;
    const u = unitsOf(at.list).find((x) => x.rows.some((r) => r.id === rowId));
    if (!u) return;
    draft.structs ??= {};
    const first = u.rows[0]!;
    if (isGroupStructure(kind) && u.rows.length === 1) {
      const i = at.list.indexOf(first);
      const nxt = at.list[i + 1];
      const g = newId();
      first.group = g;
      if (nxt && !nxt.group && nxt.kind === "ex") {
        nxt.group = g;
        if (!nxt.name) focusRowId = nxt.id;
      } else {
        const partner = newRow("ex", { group: g });
        at.list.splice(i + 1, 0, partner);
        focusRowId = partner.id;
      }
      delete draft.structs[first.id];
      draft.structs[g] = structureDefaults(kind);
    } else if (!isGroupStructure(kind) && u.rows.length > 1) {
      u.rows.forEach((r) => {
        r.group = null;
      });
      if (u.group) delete draft.structs[u.group];
      if (kind !== "single") draft.structs[first.id] = structureDefaults(kind);
    } else if (kind === "single" || (kind === "superset" && u.group)) delete draft.structs[unitKey(u)];
    else draft.structs[unitKey(u)] = structureDefaults(kind);
  });
  return { plan: next, focusRowId };
}

/** A structure field (clusters, intra, drops…) typed in the group header. */
export const setStructField = (plan: PlanSection, key: string, field: string, value: string) =>
  edit(plan, (draft) => {
    draft.structs ??= {};
    const current = draft.structs[key];
    if (!current) return;
    draft.structs[key] = { ...current, [field]: value } as typeof current;
  });

export const addMeasure = (plan: PlanSection, rowId: string, measure: PlanMeasure) =>
  withRow(plan, rowId, (row) => {
    const extra = row.extra ?? [];
    if (!extra.includes(measure)) row.extra = [...extra, measure];
  });

export const dropMeasure = (plan: PlanSection, rowId: string, measure: PlanMeasure) =>
  withRow(plan, rowId, (row) => {
    row.extra = (row.extra ?? []).filter((k) => k !== measure);
    if (measure === "side") return;
    if (row.x) delete row.x[measure];
    row.cells = row.cells.map((c) => {
      const rest = { ...c };
      delete rest[measure];
      return rest;
    });
  });

/** The structure shown for a row's unit, for menus. */
export function structureOfRow(plan: PlanSection, rowId: string) {
  const at = findRow(plan, rowId);
  if (!at) return null;
  const u = unitsOf(at.list).find((x) => x.rows.some((r) => r.id === rowId));
  return u ? structOf(plan, u) : null;
}

export const occurrencesCount = (plan: PlanSection, b: number) => occurrences(plan, b).list.length;
