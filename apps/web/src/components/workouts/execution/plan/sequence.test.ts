import { describe, expect, it } from "vitest";

import type { PlanCell, PlanRow, PlanSection } from "@/lib/structured-plan/types";

import { allSteps, AMRAP_ROUNDS, buildSequence, EMOM_OPEN_SLOTS, type RunRest, type RunStep, type RunWork } from "./sequence";

let uid = 0;
const ex = (name: string, more: Partial<PlanRow> = {}): PlanRow => ({
  id: `r${uid++}`,
  kind: "ex",
  name,
  dose: "",
  load: "",
  cells: [],
  ...more,
});
const rest = (dose: string, more: Partial<PlanRow> = {}): PlanRow => ({ ...ex("", more), kind: "rest", dose, ...more });
const cells = (...pairs: Array<[string, string?]>): PlanCell[] => pairs.map(([d, l = ""]) => ({ d, l }));
const section = (flow: PlanSection["flow"], params: PlanSection["params"], blocks: PlanRow[][], more: Partial<PlanSection> = {}): PlanSection => ({
  v: 1,
  flow,
  params,
  blocks,
  score: "",
  ...more,
});

const works = (steps: RunStep[]) => steps.filter((s): s is RunWork => s.kind === "work");
/** "Name dose @ load" per step, rests as "rest <secs>". */
const brief = (steps: RunStep[]) =>
  steps.map((s) =>
    s.kind === "rest"
      ? `rest ${s.untilHr != null ? `hr${s.untilHr}` : s.range ? s.range.join("-") : (s.secs ?? s.text)}`
      : `${s.round}:${s.name} ${s.values.dose}${s.values.load ? ` @ ${s.values.load}` : ""}`,
  );

describe("buildSequence: sets", () => {
  it("runs a superset set-wise: 12-10-8-8 with 15 flies, +5 keeps adding, rest after each round of the group", () => {
    const seq = buildSequence(
      section("sets", { sets: "4", rest: "90″" }, [[
        ex("Bench Press", { group: "g", cells: cells(["12", "60kg"], ["10", "+5"], ["8"], ["8"]) }),
        ex("DB Fly", { group: "g", cells: cells(["15", "12kg"]) }),
      ]], { structs: { g: { kind: "superset" } } }),
    );
    expect(seq.clock).toBe("none");
    expect(brief(allSteps(seq))).toEqual([
      "1:Bench Press 12 @ 60 kg", "1:DB Fly 15 @ 12 kg", "rest 90",
      "2:Bench Press 10 @ 65 kg", "2:DB Fly 15 @ 12 kg", "rest 90",
      "3:Bench Press 8 @ 70 kg", "3:DB Fly 15 @ 12 kg", "rest 90",
      "4:Bench Press 8 @ 75 kg", "4:DB Fly 15 @ 12 kg",
    ]);
    const first = works(allSteps(seq))[1];
    expect(first.group).toEqual({ kind: "superset", key: "g", index: 1, size: 2 });
    expect(first.rounds).toBe(4);
  });

  it("does straight sets one exercise after the other, keeps tempo and measures, marks per side", () => {
    const seq = buildSequence(
      section("sets", { sets: "2", rest: "2:00" }, [[
        ex("Back Squat", { cells: [{ d: "5", l: "70%", tempo: "31X1", rpe: "7" }, { d: "", l: "+5", rpe: "+1" }], extra: ["tempo", "rpe"] }),
        ex("Lunge", { cells: cells(["8"]), extra: ["side"] }),
      ]]),
    );
    const steps = allSteps(seq);
    expect(brief(steps)).toEqual([
      "1:Back Squat 5 @ 70%", "rest 120", "2:Back Squat 5 @ 75%", "rest 120",
      "1:Lunge 8", "rest 120", "2:Lunge 8",
    ]);
    const squat2 = works(steps)[1];
    expect(squat2.values.tempo).toBe("31X1");
    expect(squat2.values.measures.rpe).toBe("8");
    expect(works(steps)[2].values.perSide).toBe(true);
  });

  it("shows a rest range as a range and marks sets past the lower end of a range optional", () => {
    const seq = buildSequence(section("sets", { sets: "3-4", rest: "90-120″" }, [[ex("Knee Extension", { cells: cells(["12-15"]) })]]));
    const steps = allSteps(seq);
    expect((steps[1] as RunRest).range).toEqual([90, 120]);
    expect(works(steps).map((w) => [w.round, w.optional, w.values.dose])).toEqual([
      [1, false, "12–15"], [2, false, "12–15"], [3, false, "12–15"], [4, true, "12–15"],
    ]);
  });

  it("keeps rest rows inside a group and a standalone rest row once between exercises", () => {
    const seq = buildSequence(
      section("sets", { sets: "2", rest: "3:00" }, [[
        ex("Ring Dip", { group: "g", cells: cells(["7", "με βάρος"]) }),
        rest("", { group: "g", cells: cells(["30″"]) }),
        ex("Strict HSPU", { group: "g", cells: cells(["10"]) }),
        rest("", { cells: cells(["5:00"]) }),
        ex("Echo Bike", { cells: cells(["60s max cal"]) }),
      ]]),
    );
    expect(brief(allSteps(seq))).toEqual([
      "1:Ring Dip 7 @ με βάρος", "rest 30", "1:Strict HSPU 10", "rest 180",
      "2:Ring Dip 7 @ με βάρος", "rest 30", "2:Strict HSPU 10", "rest 300",
      "1:Echo Bike max cal in 1:00", "rest 180", "2:Echo Bike max cal in 1:00",
    ]);
  });

  it("alternates different sets set by set", () => {
    const seq = buildSequence(section("sets", { sets: "4" }, [[ex("Snatch", { cells: cells(["2", "70kg"], ["", "+5"]) })], [ex("Clean", { cells: cells(["3", "80kg"]) })]]));
    expect(brief(allSteps(seq))).toEqual(["1:Snatch 2 @ 70 kg", "2:Clean 3 @ 80 kg", "3:Snatch 2 @ 75 kg", "4:Clean 3 @ 80 kg"]);
  });

  it("splits cluster, drop and rest-pause sets into their parts", () => {
    const sq = ex("Back Squat", { cells: cells(["3", "80%"]) });
    const cluster = allSteps(buildSequence(section("sets", { sets: "1" }, [[sq]], { structs: { [sq.id]: { kind: "cluster", clusters: "3", intra: "15″" } } })));
    expect(brief(cluster)).toEqual(["1:Back Squat 3 @ 80%", "rest 15", "1:Back Squat 3 @ 80%", "rest 15", "1:Back Squat 3 @ 80%"]);
    expect(works(cluster).map((w) => w.part)).toEqual([0, 1, 2].map((index) => ({ kind: "cluster", index, count: 3 })));

    const curl = ex("Curl", { cells: cells(["10", "20kg"]) });
    const drop = works(allSteps(buildSequence(section("sets", { sets: "1" }, [[curl]], { structs: { [curl.id]: { kind: "drop", drops: "2", dropby: "-20%" } } }))));
    expect(drop.map((w) => w.part)).toEqual([0, 1, 2].map((index) => ({ kind: "drop", index, count: 3, by: "-20%" })));

    const press = ex("Press", { cells: cells(["max"]) });
    const rp = allSteps(buildSequence(section("sets", { sets: "1" }, [[press]], { structs: { [press.id]: { kind: "restpause", minis: "2", intra: "20″" } } })));
    expect(brief(rp)).toEqual(["1:Press max", "rest 20", "1:Press max"]);
  });
});

describe("buildSequence: for time", () => {
  it("counts up with a cap and repeats the rounds, alternating blocks", () => {
    const seq = buildSequence(
      section("for_time", { rounds: "4", cap: "20" }, [[ex("Row", { dose: "500 m" }), ex("Burpee", { dose: "15" })], [ex("Run", { dose: "400 m" }), ex("Wall Ball", { dose: "20" })]]),
    );
    expect(seq.clock).toBe("up");
    expect(seq.capSecs).toBe(1200);
    expect(seq.phases).toHaveLength(1);
    expect(brief(allSteps(seq))).toEqual([
      "1:Row 500 m", "1:Burpee 15", "2:Run 400 m", "2:Wall Ball 20",
      "3:Row 500 m", "3:Burpee 15", "4:Run 400 m", "4:Wall Ball 20",
    ]);
  });

  it("reads 21-15-9 as three rounds", () => {
    const seq = buildSequence(section("for_time", { rounds: "1" }, [[ex("Thruster", { dose: "21-15-9", load: "43kg" }), ex("Pull-up", { dose: "21-15-9" })]]));
    expect(brief(allSteps(seq))).toEqual([
      "1:Thruster 21 @ 43 kg", "1:Pull-up 21", "2:Thruster 15 @ 43 kg", "2:Pull-up 15", "3:Thruster 9 @ 43 kg", "3:Pull-up 9",
    ]);
  });

  it("75 thrusters with 10 burpees every 2 minutes: interrupt rows every 120 s", () => {
    const seq = buildSequence(
      section("for_time", { rounds: "1", cap: "", intEvery: "2:00" }, [[ex("Thruster", { dose: "75" })]], {
        mods: { interrupt: true },
        interrupt: [ex("Burpee over Bar", { dose: "10" })],
      }),
    );
    expect(seq.capSecs).toBeNull();
    expect(brief(allSteps(seq))).toEqual(["1:Thruster 75"]);
    expect(seq.interrupt?.everySecs).toBe(120);
    expect(brief(seq.interrupt!.steps)).toEqual(["1:Burpee over Bar 10"]);
    expect((seq.interrupt!.steps[0] as RunWork).interrupt).toBe(true);
  });

  it("has no interruption without interrupt rows or a time", () => {
    const base = section("for_time", { intEvery: "" }, [[ex("Thruster", { dose: "75" })]], { mods: { interrupt: true }, interrupt: [ex("Burpee", { dose: "10" })] });
    expect(buildSequence(base).interrupt).toBeNull();
  });
});

describe("buildSequence: AMRAP", () => {
  it("3-3-3-4 with 1' rest: four windows with a rest between, each counting down", () => {
    const seq = buildSequence(
      section("amrap", { dur: "3-3-3-4", rest: "1:00" }, [[ex("Echo Bike", { dose: "15 cal" }), ex("Wall Ball", { dose: "25" }), ex("Clean & Jerk", { dose: "max", load: "60kg" })]]),
    );
    expect(seq.clock).toBe("down");
    expect(seq.open).toBe(true);
    expect(seq.phases.map((p) => [p.kind, p.secs, p.round])).toEqual([
      ["work", 180, 1], ["rest", 60, 1], ["work", 180, 2], ["rest", 60, 2], ["work", 180, 3], ["rest", 60, 3], ["work", 240, 4],
    ]);
    expect(brief(seq.phases[0].steps.slice(0, 4))).toEqual(["1:Echo Bike 15 cal", "1:Wall Ball 25", "1:Clean & Jerk max @ 60 kg", "2:Echo Bike 15 cal"]);
    expect((seq.phases[1].steps[0] as RunRest).reason).toBe("window");
    expect(works(seq.phases[0].steps)).toHaveLength(3 * AMRAP_ROUNDS);
  });

  it("open-ended rounds: after the last written round a number repeats and +x keeps changing", () => {
    const seq = buildSequence(
      section("amrap", { dur: "7" }, [[
        ex("Butterfly Pull-up", { dose: "15" }),
        ex("Power Snatch", { perRound: true, cells: cells(["5", "40kg"], ["10", "+5kg"], ["15"]) }),
        ex("Box Jump", { perRound: true, cells: cells(["5"], ["+2"]) }),
      ]]),
    );
    const snatch = works(seq.phases[0].steps).filter((w) => w.name === "Power Snatch").slice(0, 5);
    expect(snatch.map((w) => `${w.values.dose} @ ${w.values.load}`)).toEqual(["5 @ 40 kg", "10 @ 45 kg", "15 @ 50 kg", "15 @ 55 kg", "15 @ 60 kg"]);
    const box = works(seq.phases[0].steps).filter((w) => w.name === "Box Jump").slice(0, 4);
    expect(box.map((w) => w.values.dose)).toEqual(["5", "7", "9", "11"]);
    expect(snatch.every((w) => w.rounds === null)).toBe(true);
  });
});

describe("buildSequence: EMOM", () => {
  it("alternates odd and even minutes", () => {
    const seq = buildSequence(section("emom", { every: "1:00", times: "8" }, [[ex("Wall Ball", { dose: "20" })], [ex("Burpee to Target", { dose: "12" })]]));
    expect(seq.phases).toHaveLength(8);
    expect(seq.phases.every((p) => p.secs === 60)).toBe(true);
    expect(seq.phases.map((p) => brief(p.steps)[0])).toEqual([
      "1:Wall Ball 20", "2:Burpee to Target 12", "3:Wall Ball 20", "4:Burpee to Target 12",
      "5:Wall Ball 20", "6:Burpee to Target 12", "7:Wall Ball 20", "8:Burpee to Target 12",
    ]);
  });

  it("every 2:30 × 4 with a superset in each slot", () => {
    const seq = buildSequence(
      section("emom", { every: "2:30", times: "4" }, [[ex("Front Squat", { dose: "7", group: "g" }), ex("Dual DB Push Press", { dose: "8-12", load: "βαρύ", group: "g" })]]),
    );
    expect(seq.phases.map((p) => [p.secs, p.round])).toEqual([[150, 1], [150, 2], [150, 3], [150, 4]]);
    expect(brief(seq.phases[3].steps)).toEqual(["4:Front Squat 7", "4:Dual DB Push Press 8–12 @ βαρύ"]);
    expect((seq.phases[3].steps[1] as RunWork).group?.index).toBe(1);
  });

  it("Death by: 1-2-3… keeps adding; no number of times = until failure", () => {
    const seq = buildSequence(section("emom", { every: "1:00", times: "" }, [[ex("Burpee", { dose: "1-2-3…" })]]));
    expect(seq.open).toBe(true);
    expect(seq.phases).toHaveLength(EMOM_OPEN_SLOTS);
    expect(seq.phases.slice(0, 5).map((p) => (p.steps[0] as RunWork).values.dose)).toEqual(["1", "2", "3", "4", "5"]);
    expect((seq.phases[0].steps[0] as RunWork).rounds).toBeNull();
  });
});

describe("buildSequence: EMOM params", () => {
  it("does not invent a slot length when every is unreadable", () => {
    const seq = buildSequence(section("emom", { every: "", times: "3" }, [[ex("Burpee", { dose: "10" })]]));
    expect(seq.phases.map((p) => p.secs)).toEqual([null, null, null]);
  });
});

describe("buildSequence: intervals", () => {
  it("work / off / rounds, no rest after the last round", () => {
    const seq = buildSequence(section("intervals", { work: "20″", off: "10″", rounds: "3" }, [[ex("Air Squat", { dose: "max" })]]));
    expect(seq.phases.map((p) => [p.kind, p.secs, p.round])).toEqual([
      ["work", 20, 1], ["rest", 10, 1], ["work", 20, 2], ["rest", 10, 2], ["work", 20, 3],
    ]);
  });

  it("heart-rate rest ends on the athlete's tap", () => {
    const seq = buildSequence(
      section("intervals", { work: "3:00", off: "", rounds: "2", hrTarget: "120" }, [[ex("Row", { dose: "max m" })]], { mods: { hr: true } }),
    );
    expect(seq.phases.map((p) => [p.kind, p.secs])).toEqual([["work", 180], ["rest", null], ["work", 180]]);
    expect(brief(seq.phases[1].steps)).toEqual(["rest hr120"]);
  });
});

describe("buildSequence: rest", () => {
  it("is one countdown", () => {
    const seq = buildSequence(section("rest", { dur: "2:00" }, []));
    expect(seq.phases).toEqual([expect.objectContaining({ kind: "rest", secs: 120 })]);
  });
});
