"use client";

import type { PlanMeasure, PlanRow, PlanStructureKind } from "@/lib/structured-plan/types";

import { useGrid, type PickerState } from "./context";
import { MEASURES } from "./lib";
import { attr, fieldKey, type MeasureKey } from "./model";
import * as M from "./mutations";

/**
 * Row actions shared by the ⋯ menu, its shortcuts (Alt+…) and the add
 * buttons. Each one writes a new plan and says which field gets the caret.
 */
export function useGridActions() {
  const { plan, write, focusKey, openNote, openPicker } = useGrid();

  return {
    addRow(where: { afterId?: string; b?: number }, kind: PlanRow["kind"] = "ex") {
      let id = "";
      write((p) => {
        const out = M.addRow(p, where, kind);
        id = out.rowId;
        return out.plan;
      });
      if (!id) return;
      const at = where.afterId ? M.findRow(plan, where.afterId) : null;
      const b = at?.b ?? where.b ?? 0;
      focusKey(kind === "rest" ? (plan.flow === "sets" && b !== -1 ? fieldKey.cell(id, 0, "d") : fieldKey.dose(id)) : fieldKey.name(id));
    },
    deleteRow(rowId: string) {
      const at = M.findRow(plan, rowId);
      write((p) => M.deleteRow(p, rowId));
      const prev = at ? (at.list[at.i - 1] ?? at.list[at.i + 1]) : null;
      if (prev) focusKey(fieldKey.name(prev.id));
    },
    addRound() {
      let id = "";
      write((p) => {
        const out = M.addRound(p);
        id = out.rowId;
        return out.plan;
      });
      if (id) focusKey(fieldKey.name(id));
    },
    togglePerRound(rowId: string) {
      const at = M.findRow(plan, rowId);
      if (!at || at.row.kind !== "ex" || !M.canPerRound(plan, at.b)) return false;
      const turningOn = !at.row.perRound;
      write((p) => M.togglePerRound(p, rowId));
      focusKey(turningOn ? fieldKey.cell(rowId, Math.min(1, M.occurrencesCount(plan, at.b) - 1), at.row.load ? "l" : "d") : fieldKey.dose(rowId));
      return true;
    },
    toggleSuperset(rowId: string) {
      write((p) => M.toggleSuperset(p, rowId));
      focusKey(fieldKey.name(rowId));
    },
    note(rowId: string) {
      openNote(rowId);
      focusKey(fieldKey.note(rowId));
    },
    setStruct(rowId: string, kind: PlanStructureKind) {
      let focusRow: string | null = null;
      let unitKey: string | null = null;
      write((p) => {
        const out = M.setStruct(p, rowId, kind);
        focusRow = out.focusRowId;
        const at = M.findRow(out.plan, rowId);
        unitKey = at?.row.group ?? rowId;
        return out.plan;
      });
      const fields = kind === "cluster" ? "clusters" : kind === "drop" ? "drops" : kind === "restpause" ? "minis" : null;
      if (focusRow) focusKey(fieldKey.name(focusRow));
      else if (fields && unitKey) focusKey(fieldKey.struct(unitKey, fields));
      else focusKey(fieldKey.name(rowId));
    },
    addMeasure(rowId: string, k: PlanMeasure) {
      const at = M.findRow(plan, rowId);
      write((p) => M.addMeasure(p, rowId, k));
      if (!at) return;
      if (MEASURES[k].flag) focusKey(fieldKey.name(rowId));
      else focusKey((plan.flow === "sets" && at.b !== -1) || at.row.perRound ? fieldKey.cell(rowId, 0, k as MeasureKey) : fieldKey.x(rowId, k as MeasureKey));
    },
    dropMeasure(rowId: string, k: PlanMeasure) {
      write((p) => M.dropMeasure(p, rowId, k));
      focusKey(fieldKey.name(rowId));
    },
    open(rowId: string, mode: PickerState["mode"], anchor: HTMLElement | null, returnKey: string | null) {
      const target = anchor ?? document.querySelector<HTMLElement>(`[data-more="${attr(rowId)}"]`);
      if (target) openPicker({ rowId, mode, anchor: target, returnKey });
    },
  };
}

export type GridActions = ReturnType<typeof useGridActions>;
