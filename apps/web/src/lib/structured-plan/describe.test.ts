import { describe as group, expect, it } from "vitest";
import { describe, summary, timeline } from "./describe";
import { newRow, newSection } from "./factory";
import type { PlanFlow, PlanMods, PlanParams, PlanRow, PlanSection } from "./types";

const section = (flow: PlanFlow, params: PlanParams, more: Partial<PlanSection> = {}): PlanSection => ({
  ...newSection(flow),
  params,
  ...more,
});
const withMods = (flow: PlanFlow, params: PlanParams, mods: PlanMods, blocks?: PlanRow[][]) =>
  section(flow, params, { mods, ...(blocks ? { blocks } : {}) });

group("describe", () => {
  it("words EMOM every 2:30 x 4 with its total", () => {
    expect(describe(section("emom", { every: "2:30", times: "4" }))).toEqual([
      { key: "PlanCore.describe.emom", values: { every: "2:30", times: 4, total: "10:00" } },
    ]);
    expect(describe(section("emom", { every: "1:00", times: "" }))).toEqual([{ key: "PlanCore.describe.emomOpen", values: { every: "1:00" } }]);
  });

  it("words AMRAP windows 3'-3'-3'-4' with 1' rest, and a single AMRAP", () => {
    expect(describe(section("amrap", { dur: "3'-3'-3'-4'", rest: "1:00" }))).toEqual([
      { key: "PlanCore.describe.amrapWindowsRest", values: { count: 4, list: "3:00, 3:00, 3:00, 4:00", rest: "1:00" } },
    ]);
    expect(describe(section("amrap", { dur: "12" }))).toEqual([{ key: "PlanCore.describe.amrap", values: { dur: "12:00" } }]);
  });

  it("words sets with 90-120″ rest, for time, intervals with HR rest and interruptions", () => {
    expect(describe(section("sets", { sets: "3-4", rest: "90-120″" }))).toEqual([
      { key: "PlanCore.describe.setsRest", values: { sets: "3-4", rest: "90-120″" } },
    ]);
    expect(describe(section("for_time", { rounds: "4", cap: "20" }))).toEqual([{ key: "PlanCore.describe.forTimeCap", values: { rounds: 4, cap: "20" } }]);
    expect(describe(withMods("intervals", { work: "3:00", off: "", rounds: "3", hrTarget: "120" }, { hr: true }))).toEqual([
      { key: "PlanCore.describe.intervalsHr", values: { rounds: "3", work: "3:00", hr: "120" } },
    ]);
    expect(describe(withMods("for_time", { rounds: "1", intEvery: "2:00" }, { interrupt: true }))).toEqual([
      { key: "PlanCore.describe.forTime", values: { rounds: 1 } },
      { key: "PlanCore.describe.interrupt", values: { every: "2:00" } },
    ]);
  });
});

group("timeline", () => {
  it("alternates EMOM slots by block", () => {
    const s = section("emom", { every: "1:00", times: "4" }, { blocks: [[newRow()], [newRow()]] });
    expect(timeline(s)).toEqual({
      segments: [0, 1, 0, 1].map((slot) => ({ secs: 60, kind: "slot", slot })),
      interrupts: [],
      total: 240,
    });
  });

  it("puts rest between AMRAP windows", () => {
    const t = timeline(section("amrap", { dur: "3-3-3-4", rest: "1:00" }));
    expect(t.segments.map((x) => `${x.kind}:${x.secs}`)).toEqual(["work:180", "rest:60", "work:180", "rest:60", "work:180", "rest:60", "work:240"]);
    expect(t.total).toBe(960);
  });

  it("draws intervals work / rest (Tabata) and HR rest as 60 s", () => {
    const tabata = timeline(section("intervals", { work: "20″", off: "10″", rounds: "8" }));
    expect(tabata.segments).toHaveLength(16);
    expect(tabata.total).toBe(240);
    const hrr = timeline(withMods("intervals", { work: "3:00", off: "", rounds: "3" }, { hr: true }));
    expect(hrr.segments.filter((x) => x.kind === "rest").map((x) => x.secs)).toEqual([60, 60, 60]);
  });

  it("marks interruptions every intEvery over For Time's cap (or 12′ uncapped)", () => {
    const t = timeline(withMods("for_time", { rounds: "1", cap: "", intEvery: "2:00" }, { interrupt: true }));
    expect(t.total).toBe(720);
    expect(t.interrupts).toEqual([120, 240, 360, 480, 600]);
    expect(timeline(section("sets", { sets: "4" })).segments).toEqual([]);
  });
});

group("summary", () => {
  it("summarises params and names per block with the per side flag", () => {
    const a = newRow("ex", { name: "Bulgarian Split Squat", extra: ["side"] });
    const b = newRow("ex", { name: "Row" });
    const c = newRow("ex", { name: "" });
    const s = section("for_time", { rounds: "4", cap: "20" }, { blocks: [[a, c], [b, newRow("rest")]] });
    expect(summary(s)).toEqual({
      params: [{ key: "PlanCore.summary.rounds", values: { rounds: 4 } }],
      names: [[{ name: "Bulgarian Split Squat", perSide: true }], [{ name: "Row", perSide: false }]],
    });
  });

  it("summarises each flow", () => {
    expect(summary(section("emom", { every: "2:30", times: "4" })).params).toEqual([{ key: "PlanCore.summary.emom", values: { every: "2:30", times: "4" } }]);
    expect(summary(section("sets", { sets: "3-4" })).params).toEqual([{ key: "PlanCore.summary.sets", values: { sets: "3-4" } }]);
    expect(summary(section("amrap", { dur: "3-3-3-4" })).params).toEqual([{ key: "PlanCore.summary.windows", values: { count: 4 } }]);
    expect(summary(section("amrap", { dur: "7" })).params).toEqual([{ key: "PlanCore.summary.dur", values: { dur: "7:00" } }]);
    expect(summary(section("for_time", { rounds: "1" })).params).toEqual([]);
    expect(summary(section("rest", { dur: "2:00" })).params).toEqual([{ key: "PlanCore.summary.dur", values: { dur: "2:00" } }]);
    expect(summary(withMods("for_time", { rounds: "1", intEvery: "2:00" }, { interrupt: true })).params).toEqual([
      { key: "PlanCore.summary.interrupt", values: { every: "2:00" } },
    ]);
  });
});
