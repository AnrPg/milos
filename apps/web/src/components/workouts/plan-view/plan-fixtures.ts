import { PLAN_VERSION, type PlanRow, type PlanSection } from "@/lib/structured-plan/types";

/** Test fixtures: the mockup's sample sections («Από το αρχείο σου») as stored plans. */

let seed = 0;
export function row(name: string, init: Partial<PlanRow> = {}): PlanRow {
  seed += 1;
  return { id: `r${seed}`, kind: "ex", name, dose: "", load: "", cells: [], group: null, ...init };
}

export function restRow(init: Partial<PlanRow> = {}): PlanRow {
  return row("", { kind: "rest", ...init });
}

export function section(flow: PlanSection["flow"], params: PlanSection["params"], blocks: PlanRow[][], init: Partial<PlanSection> = {}): PlanSection {
  return { v: PLAN_VERSION, flow, preset: null, params, mods: {}, blocks, interrupt: [], structs: {}, score: "none", ...init };
}

export const backSquat = () =>
  section("sets", { sets: "4", rest: "2:00" }, [
    [
      row("Back Squat", {
        note: "Έλεγχος στο κατέβασμα, με ζώνη",
        cells: [{ d: "12", l: "60%", tempo: "31X1" }, { d: "10", l: "+5" }, { d: "8" }, { d: "8" }],
        extra: ["tempo"],
      }),
    ],
  ]);

export const spreadLoad = () => section("sets", { sets: "4", rest: "90″" }, [[row("Deadlift", { cells: [{ d: "5", l: "60→80%" }] })]], { score: "best_load" });

export const giantSet = () =>
  section("sets", { sets: "3-4", rest: "90″" }, [
    [
      row("Knee Extension", { group: "g1", cells: [{ d: "12-15" }] }),
      row("Standing Calf Raise", { group: "g1", cells: [{ d: "15" }] }),
      row("Cyclist Squat", { group: "g1", note: "Φτέρνες ψηλά", cells: [{ d: "20" }] }),
    ],
  ]);

export const clusterSquat = () => {
  const squat = row("Back Squat", { cells: [{ d: "3", l: "80%" }] });
  return section("sets", { sets: "5", rest: "2:30" }, [[squat]], { structs: { [squat.id]: { kind: "cluster", clusters: "3", intra: "15″" } } });
};

export const alternatingEmom = () =>
  section("emom", { every: "1:00", times: "8" }, [[row("Wall Ball", { dose: "20" })], [row("Burpee to Target", { dose: "12" })]], { preset: "even_odd" });

export const differentRounds = () =>
  section("for_time", { rounds: "6", cap: "20" }, [
    [row("Row", { dose: "500 m" }), row("Burpee", { dose: "15" })],
    [row("Run", { dose: "400 m" }), row("Wall Ball", { dose: "20" })],
  ], { score: "time" });

export const amrapPerRound = () =>
  section("amrap", { dur: "7" }, [
    [
      row("Butterfly Pull-up", { dose: "15" }),
      row("Power Snatch", { perRound: true, cells: [{ d: "5", l: "40kg" }, { d: "10", l: "+5kg" }, { d: "15" }] }),
    ],
  ], { score: "rounds_reps" });

export const interrupted = () =>
  section("for_time", { rounds: "1", cap: "", intEvery: "2:00" }, [[row("Thruster", { dose: "75", load: "40kg" })]], {
    mods: { interrupt: true },
    interrupt: [row("Burpee over Bar", { dose: "10" })],
    preset: "interrupt",
    score: "time",
  });

export const tabata = () =>
  section("intervals", { work: "20″", off: "10″", rounds: "8" }, [[row("Air Squat", { dose: "max" })]], { preset: "tabata", score: "lowest_round" });

export const hrIntervals = () =>
  section("intervals", { work: "3:00", off: "", rounds: "3", hrTarget: "120" }, [[row("Row", { dose: "max cal" })]], { mods: { hr: true }, preset: "hrr" });

export const windows = () =>
  section("amrap", { dur: "3-3-3-4", rest: "1:00" }, [[row("Echo Bike", { dose: "15 cal" }), row("Clean & Jerk", { dose: "max", load: "60kg" })]]);

export const restSection = () => section("rest", { dur: "2:00" }, []);

export const measured = () =>
  section("sets", { sets: "3", rest: "" }, [
    [
      row("Bulgarian Split Squat", { cells: [{ d: "10", l: "20kg", rpe: "7" }, { rpe: "+1" }], extra: ["side", "rpe"] }),
      restRow({ cells: [{ d: "30″" }] }),
      row("Box Jump", { cells: [{ d: "5", height: "60" }], extra: ["height"] }),
      row("Plank", { cells: [{ d: "1", hold: "45" }], extra: ["hold"] }),
      row("Ring Dip", { cells: [{ d: "7", l: "με βάρος" }] }),
    ],
  ], {
    note: "Ήρεμα, τεχνική πρώτα",
    levelNotes: { rx: "Με γιλέκο 10 kg", scaled: "Χωρίς βάρος" },
  });

export const edtSuperset = () =>
  section("amrap", { dur: "15" }, [[row("Pull-up", { group: "g2", dose: "5" }), row("Push-up", { group: "g2", dose: "10" })]], {
    preset: "edt",
    structs: { g2: { kind: "complex" } },
    score: "reps",
  });

export const dropAndRestPause = () => {
  const curl = row("Biceps Curl", { cells: [{ d: "10", l: "14kg" }] });
  const press = row("Leg Press", { cells: [{ d: "max", l: "100kg" }] });
  return section("sets", { sets: "2" }, [[curl, press]], {
    structs: { [curl.id]: { kind: "drop", drops: "2", dropby: "-20%" }, [press.id]: { kind: "restpause", minis: "3", intra: "15" } },
  });
};
