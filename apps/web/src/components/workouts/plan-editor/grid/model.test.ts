import { describe, expect, it } from "vitest";

import type { PlanRow } from "@/lib/structured-plan/types";

import { SAMPLE } from "./fixtures";
import { occurrences } from "./lib";
import { blockTitle, cellTestId, compactField, hintFor, parseFieldKey, perSummary, rowCells, tableColumns } from "./model";
import { addRound, deleteRow, dropMeasure, setStruct, toggleSuperset, togglePerRound } from "./mutations";

const row = (cells: PlanRow["cells"], more: Partial<PlanRow> = {}): PlanRow => ({ id: "r", kind: "ex", name: "", dose: "", load: "", cells, group: null, ...more });

describe("rowCells", () => {
  it("computes inherited, relative and spread loads, with the badge of the rule typed", () => {
    const { views, loadUnit } = rowCells(row([{ l: "60→80%" }, {}, {}, { l: "+2.5" }]), 5);
    expect(loadUnit).toBe("%");
    expect(views.l!.map((v) => v.placeholder)).toEqual(["60", "65", "70", "72.5", "75"]);
    expect(views.l![0]).toMatchObject({ display: "60", badge: "60→80" });
    expect(views.l![3]).toMatchObject({ display: "72.5", badge: "+2.5" });
  });

  it("keeps words as words and reports missing or mixed units", () => {
    expect(rowCells(row([{ l: "βαρύ" }]), 2).views.l![1]!.placeholder).toBe("βαρύ");
    expect(rowCells(row([{ l: "60" }, { l: "+5" }]), 2).views.l![0]!.error).toEqual({ key: "error.loadMissingUnit" });
    expect(rowCells(row([{ l: "60kg" }, { l: "70%" }]), 2).views.l![1]!.error).toEqual({ key: "error.loadMixedUnits", values: { unit: "kg" } });
  });

  it("repeats tempo but progresses numeric measures, capped at their maximum", () => {
    const r = row([{ tempo: "31X1", rpe: "8" }, { rpe: "+1" }, {}, {}], { extra: ["tempo", "rpe"] });
    const { views } = rowCells(r, 4);
    expect(views.tempo!.map((v) => v.placeholder)).toEqual(["31X1", "31X1", "31X1", "31X1"]);
    expect(views.rpe!.map((v) => v.placeholder)).toEqual(["8", "9", "10", "10"]);
    expect(rowCells(row([{ tempo: "fast" }], { extra: ["tempo"] }), 1).views.tempo![0]!.error).toEqual({ key: "error.tempo" });
  });

  it("flags doses it cannot read", () => {
    expect(rowCells(row([{ d: "12-10-8" }, { d: "8 ??" }]), 2).views.d![1]!.error).toEqual({ key: "error.dose" });
    expect(compactField(row([], { dose: "60s max cal" }), "d").error).toBeNull();
  });
});

describe("summaries and labels", () => {
  it("summarises per-round values first → last", () => {
    const ps = SAMPLE.amrapPerRound!.blocks[0]![1]!;
    expect(perSummary(ps, "d", 4)).toBe("5 → 15");
    expect(perSummary(ps, "l", 4)).toBe("40 kg → 55 kg");
  });

  it("names blocks by the rounds they run in", () => {
    const p = SAMPLE.differentRounds!;
    const o = occurrences(p, 1);
    expect(blockTitle(p, 1, o.list, o.open, 4)).toEqual({ key: "round.round", values: { list: "2, 4" } });
    const e = SAMPLE.emomAlternating!;
    const oe = occurrences(e, 0);
    expect(blockTitle(e, 0, oe.list, oe.open, 8)).toEqual({ key: "round.minute", values: { list: "1, 3, 5, …" } });
    expect(blockTitle(SAMPLE.amrapPerRound!, 0, [1, 2], true, Infinity)).toEqual({ key: "head.amrap" });
  });

  it("gives every table the measure columns any of its rows added", () => {
    expect(tableColumns([row([], { extra: ["rpe", "side"] }), row([], { extra: ["height"] })])).toEqual(["d", "l", "rpe", "height"]);
  });

  it("round-trips field keys and their test ids", () => {
    expect(parseFieldKey("c:abc:2:l")).toEqual({ kind: "cell", rowId: "abc", col: 2, k: "l" });
    expect(cellTestId(parseFieldKey("r:abc:dose")!)).toBe("plan-cell-abc-same-d");
    expect(cellTestId(parseFieldKey("r:abc:x:rpe")!)).toBe("plan-cell-abc-same-rpe");
  });

  it("adds the AMRAP after-the-last-round tip to per-round fields", () => {
    const h = hintFor(SAMPLE.amrapPerRound!, parseFieldKey("c:ps:3:d"), "γύρο");
    expect(h.tips.map((t) => t[1])).toContain("tip.afterLast");
  });
});

describe("mutations", () => {
  it("adds a kind of round and makes room for it", () => {
    const p = { ...SAMPLE.forTimeInterrupt!, params: { rounds: "1" } };
    const out = addRound(p);
    expect(out.plan.blocks).toHaveLength(2);
    expect(out.plan.params.rounds).toBe("2");
    expect(out.plan.blocks[1]![0]!.id).toBe(out.rowId);
  });

  it("dissolves a group of one when a row leaves or is deleted", () => {
    const p = SAMPLE.emomSuperset!;
    expect(toggleSuperset(p, "pp").blocks[0]!.every((r) => !r.group)).toBe(true);
    expect(deleteRow(p, "fs").blocks[0]![0]!.group).toBeNull();
  });

  it("joins the next row as partner for a group structure, or adds one", () => {
    const p = SAMPLE.amrapWindows!;
    const out = setStruct(p, "ebk", "complex");
    const [a, b] = out.plan.blocks[0]!;
    expect(a!.group).toBe(b!.group);
    expect(out.plan.structs?.[a!.group!]).toEqual({ kind: "complex" });
    const alone = setStruct(SAMPLE.forTimeInterrupt!, "th", "superset");
    expect(alone.plan.blocks[0]).toHaveLength(2);
    expect(alone.focusRowId).toBe(alone.plan.blocks[0]![1]!.id);
  });

  it("moves values between same-every-round and per-round without losing them", () => {
    const p = SAMPLE.emomSuperset!;
    const on = togglePerRound(p, "pp");
    expect(on.blocks[0]![1]!.cells[0]).toMatchObject({ d: "8-12", l: "βαρύ" });
    const off = togglePerRound(on, "pp");
    expect(off.blocks[0]![1]).toMatchObject({ dose: "8-12", load: "βαρύ", perRound: false });
  });

  it("drops a measure from every cell", () => {
    const out = dropMeasure(SAMPLE.sets!, "sq", "tempo");
    expect(out.blocks[0]![0]!.extra).toEqual([]);
    expect(out.blocks[0]![0]!.cells[0]).toEqual({ d: "12", l: "60%" });
  });
});
