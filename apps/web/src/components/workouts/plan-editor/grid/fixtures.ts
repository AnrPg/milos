/**
 * The approved mockup's sample sections (ADR-270), as plans: used by the
 * grid's tests and visual checks. Ids are fixed so tests can address rows.
 */
import type { PlanCell, PlanRow, PlanSection } from "@/lib/structured-plan/types";

const ex = (id: string, name: string, more: Partial<PlanRow> = {}): PlanRow => ({ id, kind: "ex", name, dose: "", load: "", cells: [], group: null, ...more });
const rest = (id: string, more: Partial<PlanRow> = {}): PlanRow => ({ id, kind: "rest", name: "", dose: "", load: "", cells: [], group: null, ...more });
const cells = (...pairs: [string, string?][]): PlanCell[] => pairs.map(([d, l = ""]) => ({ d, l }));
const section = (flow: PlanSection["flow"], params: PlanSection["params"], blocks: PlanRow[][], more: Partial<PlanSection> = {}): PlanSection => ({
  v: 1,
  flow,
  params,
  blocks,
  score: "",
  structs: {},
  mods: {},
  interrupt: [],
  ...more,
});

export const SAMPLE: Record<string, PlanSection> = {
  sets: section("sets", { sets: "4", rest: "2:00" }, [
    [
      ex("sq", "Back Squat", {
        note: "Έλεγχος στο κατέβασμα, με ζώνη",
        cells: [{ d: "12", l: "60%", tempo: "31X1" }, ...cells(["10", "+5"], ["8"], ["8"])],
        extra: ["tempo"],
      }),
    ],
  ]),
  superset: section("sets", { sets: "3-4", rest: "90″" }, [
    [
      ex("ke", "Knee Extension", { group: "g1", cells: cells(["12-15"]) }),
      ex("cr", "Standing Calf Raise", { group: "g1", cells: cells(["15"]) }),
      ex("cs", "Cyclist Squat", { group: "g1", note: "Φτέρνες ψηλά", cells: cells(["20"]) }),
    ],
  ]),
  restsInGroup: section("sets", { sets: "4", rest: "3:00" }, [
    [
      ex("rd", "Ring Dip", { group: "g2", cells: cells(["7", "με βάρος"]) }),
      rest("r1", { group: "g2", cells: cells(["30″"]) }),
      ex("hs", "Strict HSPU", { group: "g2", cells: cells(["10"]) }),
      rest("r2", { group: "g2", cells: cells(["30″"]) }),
      ex("eb", "Echo Bike", { group: "g2", cells: cells(["60s max cal"]) }),
    ],
  ]),
  cluster: section("sets", { sets: "5", rest: "2:30" }, [[ex("cl", "Back Squat", { note: "Έλεγχος στο κατέβασμα, με ζώνη", cells: cells(["3", "80%"]) })]], {
    structs: { cl: { kind: "cluster", clusters: "3", intra: "15″" } },
  }),
  emomSuperset: section("emom", { every: "2:30", times: "4" }, [
    [
      ex("fs", "Front Squat", { dose: "7", group: "g3", note: "Ίδια κιλά με το top set της δεκάρας" }),
      ex("pp", "Dual DB Push Press", { dose: "8-12", load: "βαρύ", group: "g3" }),
    ],
  ]),
  emomAlternating: section("emom", { every: "1:00", times: "8" }, [[ex("wb", "Wall Ball", { dose: "20" })], [ex("bt", "Burpee to Target", { dose: "12" })]], {
    preset: "even_odd",
  }),
  amrapPerRound: section("amrap", { dur: "7" }, [
    [
      ex("bp", "Butterfly Pull-up", { dose: "15" }),
      ex("ps", "Power Snatch", { perRound: true, cells: cells(["5", "40kg"], ["10", "+5kg"], ["15"]) }),
    ],
  ]),
  forTimeInterrupt: section("for_time", { rounds: "1", cap: "", intEvery: "2:00" }, [[ex("th", "Thruster", { dose: "75" })]], {
    mods: { interrupt: true },
    interrupt: [ex("bb", "Burpee over Bar", { dose: "10" })],
    preset: "interrupt",
  }),
  differentRounds: section("for_time", { rounds: "4", cap: "20" }, [
    [ex("ro", "Row", { dose: "500 m" }), ex("bu", "Burpee", { dose: "15" })],
    [ex("ru", "Run", { dose: "400 m" }), ex("wb2", "Wall Ball", { dose: "20" })],
  ]),
  amrapWindows: section("amrap", { dur: "3-3-3-4", rest: "1:00" }, [
    [ex("ebk", "Echo Bike", { dose: "15 cal" }), ex("wbl", "Wall Ball", { dose: "25" }), ex("cj", "Clean & Jerk", { dose: "max", load: "60kg" })],
  ]),
};
