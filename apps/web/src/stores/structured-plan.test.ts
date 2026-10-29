import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { PlanRow, PlanSection } from "@/lib/structured-plan/types";
import { PLAN_VERSION } from "@/lib/structured-plan/types";
import {
  INTERRUPT_BLOCK,
  TYPING_COALESCE_MS,
  focusKey,
  usePlanEditorStore,
  type PlanEditorSection,
} from "@/stores/structured-plan";

const store = () => usePlanEditorStore.getState();

const row = (id: string, more: Partial<PlanRow> = {}): PlanRow => ({ id, kind: "ex", name: id, dose: "", load: "", cells: [], group: null, ...more });
const plan = (more: Partial<PlanSection> = {}): PlanSection => ({ v: PLAN_VERSION, flow: "sets", params: { sets: "4", rest: "90″" }, blocks: [[row("a"), row("b")]], score: "none", ...more });
const sec = (id: string, more: Partial<PlanSection> = {}, name = ""): PlanEditorSection => ({ id, name, plan: plan(more) });

const section = (id: string) => store().sections.find((s) => s.id === id)!;
const rowOf = (id: string) => store().findRow(id)!.row;

let now = 1_000_000;
beforeEach(() => {
  vi.spyOn(Date, "now").mockImplementation(() => now);
  store().load({ title: "WOD", note: "", sections: [sec("s1"), sec("s2", { flow: "for_time", params: { rounds: "3", cap: "" }, blocks: [[row("c", { dose: "10" })]], score: "time" })] });
});
afterEach(() => vi.restoreAllMocks());
const later = () => { now += TYPING_COALESCE_MS + 1; };

describe("document", () => {
  it("loads, serializes a deep copy and starts a fresh history", () => {
    const doc = store().serialize();
    expect(doc.title).toBe("WOD");
    doc.sections[0].plan.blocks[0][0].name = "changed";
    expect(rowOf("a").name).toBe("a");
    expect(store().canUndo).toBe(false);
  });

  it("sets title and notes, coalescing typing into one undo step", () => {
    store().setTitle("W");
    now += 100;
    store().setTitle("WO");
    later();
    store().setNote({ kind: "wod" }, "warm up well");
    store().setNote({ kind: "section", sectionId: "s1" }, "heavy");
    later();
    store().setNote({ kind: "row", rowId: "a" }, "belt");
    expect(store().note).toBe("warm up well");
    expect(section("s1").plan.note).toBe("heavy");
    expect(rowOf("a").note).toBe("belt");
    store().undo();
    expect(rowOf("a").note).toBeUndefined();
    store().undo();
    expect(store().note).toBe("");
    expect(store().title).toBe("WO");
    store().undo();
    expect(store().title).toBe("WOD");
    expect(store().canUndo).toBe(false);
    store().redo();
    store().redo();
    expect(store().note).toBe("warm up well");
    expect(store().canRedo).toBe(true);
  });

  it("drops redo after a new change", () => {
    store().moveSection("s2", -1);
    store().undo();
    expect(store().canRedo).toBe(true);
    store().deleteSection("s2");
    expect(store().canRedo).toBe(false);
  });

  it("consumes the pending focus once", () => {
    store().setFocus("x");
    expect(store().consumeFocus("y")).toBeNull();
    expect(store().consumeFocus("x")).toBe("x");
    expect(store().consumeFocus()).toBeNull();
  });
});

describe("sections and wizard", () => {
  it("adds a section after another, open on step Ροή, and drops it when closed unwritten", () => {
    const id = store().addSection("s1");
    expect(store().sections.map((s) => s.id)).toEqual(["s1", id, "s2"]);
    expect(store().openId).toBe(id);
    expect(store().step).toBe(0);
    expect(store().pendingFocus).toBe(focusKey.pick(id));
    store().closeSection();
    expect(store().sections.map((s) => s.id)).toEqual(["s1", "s2"]);
    expect(store().pendingFocus).toBe(focusKey.card("s1"));
  });

  it("deletes, moves and renames sections", () => {
    store().moveSection("s1", 1);
    expect(store().sections.map((s) => s.id)).toEqual(["s2", "s1"]);
    store().moveSection("s1", 1);
    expect(store().sections.map((s) => s.id)).toEqual(["s2", "s1"]);
    store().renameSection("s1", "Strength");
    expect(section("s1").name).toBe("Strength");
    store().deleteSection("s2");
    expect(store().sections.map((s) => s.id)).toEqual(["s1"]);
    store().undo();
    expect(store().sections.map((s) => s.id)).toEqual(["s2", "s1"]);
  });

  it("opens on Ασκήσεις when there are exercises and walks the steps", () => {
    store().openSection("s1");
    expect(store().step).toBe(2);
    expect(store().pendingFocus).toBe(focusKey.row("a", "name"));
    store().nextStep();
    expect(store().step).toBe(3);
    store().prevStep();
    store().prevStep();
    expect(store().step).toBe(1);
    expect(store().pendingFocus).toBe(focusKey.param("s1", "sets"));
    store().setStep(0);
    expect(store().pendingFocus).toBe(focusKey.pick("s1"));
    store().nextStep();
    store().nextStep();
    store().nextStep();
    store().nextStep();
    expect(store().openId).toBeNull();
    expect(store().pendingFocus).toBe(focusKey.card("s1"));
  });

  it("skips the exercises step for a rest section", () => {
    store().setFlow("s1", "rest");
    expect(section("s1").plan.blocks).toEqual([]);
    expect(store().step).toBe(1);
    store().nextStep();
    expect(store().step).toBe(3);
    store().setStep(2);
    expect(store().step).toBe(3);
    store().prevStep();
    expect(store().step).toBe(1);
  });
});

describe("flow, params, add-ons, score", () => {
  it("switches flow keeping exercises and moving values out of the set grid", () => {
    store().setCell("a", 0, "d", "12");
    store().setCell("a", 0, "l", "60kg");
    store().setFlow("s1", "amrap");
    const p = section("s1").plan;
    expect(p.flow).toBe("amrap");
    expect(p.params.dur).toBe("12");
    expect(p.score).toBe("rounds_reps");
    expect(rowOf("a")).toMatchObject({ dose: "12", load: "60kg" });
    expect(store().step).toBe(1);
    store().undo();
    expect(section("s1").plan.flow).toBe("sets");
  });

  it("applies a preset: flow, its values and where it came from", () => {
    store().applyPreset("s2", "tabata");
    expect(section("s2").plan).toMatchObject({ flow: "intervals", preset: "tabata", params: { work: "20″", off: "10″", rounds: "8" } });
    store().applyPreset("s2", "even_odd");
    expect(section("s2").plan.blocks).toHaveLength(2);
    store().applyPreset("s1", "superset");
    const [first, second] = section("s1").plan.blocks[0];
    expect(first.group).toBeTruthy();
    expect(second.group).toBe(first.group);
    expect(section("s1").plan.structs?.[first.group!]).toEqual({ kind: "superset" });
    store().applyPreset("s1", "nope");
    expect(section("s1").plan.preset).toBe("superset");
  });

  it("sets params and toggles add-ons with their fields", () => {
    store().setParam("s1", "sets", "5");
    expect(section("s1").plan.params.sets).toBe("5");
    store().toggleMod("s1", "interrupt");
    expect(section("s1").plan.mods?.interrupt).toBe(true);
    expect(section("s1").plan.params.intEvery).toBe("2:00");
    expect(section("s1").plan.interrupt).toHaveLength(1);
    expect(store().pendingFocus).toBe(focusKey.param("s1", "intEvery"));
    store().toggleMod("s1", "interrupt");
    expect(section("s1").plan.mods?.interrupt).toBeUndefined();
    expect(section("s1").plan.interrupt).toEqual([]);
    store().toggleMod("s1", "hr");
    expect(section("s1").plan.mods?.hr).toBeUndefined();
  });

  it("sets score and level notes", () => {
    store().setScore("s1", "best_load");
    expect(section("s1").plan.score).toBe("best_load");
    store().setLevelNote("s1", "scaled", "lighter bar");
    expect(section("s1").plan.levelNotes).toEqual({ scaled: "lighter bar" });
    store().setLevelNote("s1", "scaled", "");
    expect(section("s1").plan.levelNotes).toEqual({});
  });
});

describe("rows", () => {
  it("adds rows after a row (keeping its group) or in a slot, and deletes them", () => {
    const id = store().addRow("a");
    expect(section("s1").plan.blocks[0].map((r) => r.id)).toEqual(["a", id, "b"]);
    expect(store().pendingFocus).toBe(focusKey.row(id, "name"));
    const rest = store().addRow("b", "rest");
    expect(rowOf(rest)).toMatchObject({ kind: "rest", cells: [{ d: "30″" }] });
    expect(store().pendingFocus).toBe(focusKey.cell(rest, 0, "d"));
    const loopRest = store().addRow("c", "rest");
    expect(rowOf(loopRest).dose).toBe("30″");
    const end = store().addRow({ sectionId: "s2", block: 0 });
    expect(section("s2").plan.blocks[0].at(-1)!.id).toBe(end);
    store().deleteRow(id);
    expect(store().findRow(id)).toBeNull();
    expect(store().pendingFocus).toBe(focusKey.row("a", "name"));
  });

  it("adds a row into the interrupt lane", () => {
    store().toggleMod("s1", "interrupt");
    const id = store().addRow({ sectionId: "s1", block: INTERRUPT_BLOCK });
    expect(store().findRow(id)!.block).toBe(INTERRUPT_BLOCK);
    expect(section("s1").plan.interrupt).toHaveLength(2);
  });

  it("updates rows and cells as typing", () => {
    store().updateRow("a", { name: "Back Squat" });
    now += 10;
    store().setCell("a", 2, "l", "+5");
    expect(rowOf("a").name).toBe("Back Squat");
    expect(rowOf("a").cells).toEqual([{}, {}, { l: "+5" }]);
    store().undo();
    expect(rowOf("a").name).toBe("a");
    expect(rowOf("a").cells).toEqual([]);
  });

  it("toggles a superset with the row above and back", () => {
    store().toggleSuperset("a");
    expect(rowOf("a").group).toBeNull();
    store().toggleSuperset("b");
    expect(rowOf("b").group).toBeTruthy();
    expect(rowOf("a").group).toBe(rowOf("b").group);
    store().toggleSuperset("b");
    expect(rowOf("a").group).toBeNull();
    expect(rowOf("b").group).toBeNull();
  });

  it("sets structures on a row or a group", () => {
    store().setStructure("a", "cluster");
    expect(section("s1").plan.structs?.a).toEqual({ kind: "cluster", clusters: "3", intra: "15″" });
    store().updateStructure("a", { clusters: "4" });
    expect(section("s1").plan.structs?.a).toMatchObject({ clusters: "4" });
    store().setStructure("a", "complex");
    const group = rowOf("a").group!;
    expect(rowOf("b").group).toBe(group);
    expect(section("s1").plan.structs?.[group]).toEqual({ kind: "complex" });
    expect(section("s1").plan.structs?.a).toBeUndefined();
    store().setStructure("b", "drop");
    expect(rowOf("a").group).toBeNull();
    expect(section("s1").plan.structs?.a).toMatchObject({ kind: "drop" });
    store().setStructure("a", "single");
    expect(section("s1").plan.structs?.a).toBeUndefined();
    store().setStructure("c", "superset");
    const [, partner] = section("s2").plan.blocks[0];
    expect(partner.name).toBe("");
    expect(store().pendingFocus).toBe(focusKey.row(partner.id, "name"));
  });

  it("adds and removes measures with their values", () => {
    store().addMeasure("a", "tempo");
    store().addMeasure("a", "tempo");
    expect(rowOf("a").extra).toEqual(["tempo"]);
    expect(store().pendingFocus).toBe(focusKey.cell("a", 0, "tempo"));
    store().setCell("a", 0, "tempo", "31X1");
    store().addMeasure("c", "rpe");
    expect(store().pendingFocus).toBe(focusKey.row("c", "x:rpe"));
    store().removeMeasure("a", "tempo");
    expect(rowOf("a").extra).toEqual([]);
    expect(rowOf("a").cells).toEqual([{}]);
  });

  it("toggles per-round values where a block repeats", () => {
    expect(store().togglePerRound("a")).toBe(false);
    store().updateRow("c", { load: "40kg" });
    expect(store().togglePerRound("c")).toBe(true);
    expect(rowOf("c")).toMatchObject({ perRound: true, cells: [{ d: "10", l: "40kg" }] });
    expect(store().pendingFocus).toBe(focusKey.cell("c", 1, "l"));
    store().setCell("c", 0, "d", "12");
    expect(store().togglePerRound("c")).toBe(true);
    expect(rowOf("c")).toMatchObject({ perRound: false, dose: "12", load: "40kg" });
    store().setParam("s2", "rounds", "1");
    expect(store().togglePerRound("c")).toBe(false);
  });

  it("replaces a plan through a recipe, as typing or as its own step", () => {
    store().updatePlan("s1", (p) => { p.note = "a"; }, { typing: true });
    now += 10;
    store().updatePlan("s1", (p) => ({ ...p, note: "ab" }), { typing: true, focus: "x" });
    expect(section("s1").plan.note).toBe("ab");
    expect(store().pendingFocus).toBe("x");
    store().updatePlan("s1", (p) => { p.score = "reps"; });
    store().undo();
    expect(section("s1").plan.score).toBe("none");
    store().undo();
    expect(section("s1").plan.note).toBeUndefined();
  });

  it("adds blocks and raises the rounds when needed", () => {
    store().setParam("s2", "rounds", "1");
    const id = store().addBlock("s2");
    expect(section("s2").plan.blocks).toHaveLength(2);
    expect(section("s2").plan.params.rounds).toBe("2");
    expect(store().pendingFocus).toBe(focusKey.row(id!, "name"));
    store().deleteRow(id!);
    expect(section("s2").plan.blocks).toHaveLength(1);
    store().setFlow("s1", "rest");
    expect(store().addBlock("s1")).toBeNull();
  });
});
