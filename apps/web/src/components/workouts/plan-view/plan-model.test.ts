import { createTranslator } from "next-intl";
import { describe, expect, it } from "vitest";

import el from "../../../../messages/el.json";
import en from "../../../../messages/en.json";

import {
  alternatingEmom,
  amrapPerRound,
  backSquat,
  clusterSquat,
  differentRounds,
  dropAndRestPause,
  edtSuperset,
  giantSet,
  hrIntervals,
  interrupted,
  measured,
  restSection,
  spreadLoad,
  tabata,
  windows,
} from "./plan-fixtures";
import { buildPlanView, compactValues, planSectionText, showTime, tempoShort, type Translate } from "./plan-model";

const greek = createTranslator({ locale: "el", messages: el, namespace: "PlanView" }) as unknown as Translate;
const english = createTranslator({ locale: "en", messages: en, namespace: "PlanView" }) as unknown as Translate;

const rows = (view: ReturnType<typeof buildPlanView>, block = 0) => view.blocks[block]!.units.flatMap((unit) => unit.rows);

describe("compact WOD notation", () => {
  it("writes one value once and different values with dashes, the unit once", () => {
    expect(compactValues(["12", "12", "12"])).toBe("12");
    expect(compactValues(["12", "10", "8", "8"])).toBe("12-10-8-8");
    expect(compactValues(["60 kg", "65 kg", "70 kg"])).toBe("60-65-70 kg");
    expect(compactValues(["60%", "70%"])).toBe("60-70%");
    expect(compactValues(["8-12", "6-8"])).toBe("8-12 / 6-8");
    expect(compactValues(["5", "10"], true)).toBe("5-10…");
    expect(compactValues(["", ""])).toBe("");
  });

  it("shows tempo with arrows and times the calm way", () => {
    expect(tempoShort("31X1")).toBe("↓3 ·1 ↑X ·1");
    expect(tempoShort("3-0-x-1")).toBe("↓3 ·0 ↑X ·1");
    expect(showTime("2:00", "smart")).toBe("2′");
    expect(showTime("90″", "smart")).toBe("1:30");
    expect(showTime("90-120″", "smart")).toBe("1:30–2′");
    expect(showTime("20", "min")).toBe("20′");
    expect(showTime("15", "sec")).toBe("15″");
  });
});

describe("buildPlanView", () => {
  it("sets: per-set values, progressive load and tempo", () => {
    const view = buildPlanView(backSquat(), greek);
    expect(view.flow).toBe("Σετ");
    expect(view.params).toBe("4 σετ · 2′ ξεκούραση");
    const [squat] = rows(view);
    expect(squat).toMatchObject({ name: "Back Squat", dose: "12-10-8-8", load: "60-65-70-75%", note: "Έλεγχος στο κατέβασμα, με ζώνη" });
    expect(squat!.measures).toEqual(["Tempo ↓3 ·1 ↑X ·1"]);
  });

  it("keeps a spread load as the coach wrote it", () => {
    const view = buildPlanView(spreadLoad(), greek);
    expect(rows(view)[0]).toMatchObject({ dose: "5", load: "60→80%" });
    expect(view.score).toBe("Σκορ: Φορτίο (καλύτερο σετ)");
  });

  it("groups a giant set under one structure header", () => {
    const view = buildPlanView(giantSet(), greek);
    expect(view.params).toBe("3-4 σετ · 1:30 ξεκούραση");
    expect(view.blocks[0]!.units).toHaveLength(1);
    expect(view.blocks[0]!.units[0]!.structure).toBe("Superset");
    expect(rows(view).map((row) => [row.name, row.dose])).toEqual([
      ["Knee Extension", "12-15"],
      ["Standing Calf Raise", "15"],
      ["Cyclist Squat", "20"],
    ]);
  });

  it("names cluster, complex, drop set and rest-pause structures", () => {
    expect(buildPlanView(clusterSquat(), greek).blocks[0]!.units[0]!.structure).toBe("Cluster · 3 κομμάτια · 15″ παύση");
    expect(buildPlanView(edtSuperset(), greek).blocks[0]!.units[0]!.structure).toBe("Complex");
    const units = buildPlanView(dropAndRestPause(), greek).blocks[0]!.units;
    expect(units.map((unit) => unit.structure)).toEqual(["Drop set · 2 μειώσεις, -20% κάθε φορά", "Rest-pause · 3 μίνι σετ · 15″ παύση"]);
  });

  it("labels different rounds by the rounds they run in", () => {
    const view = buildPlanView(differentRounds(), greek);
    expect(view.params).toBe("6 γύροι · όριο 20′");
    expect(view.blocks.map((block) => block.label)).toEqual(["Γύρος 1, 3, 5", "Γύρος 2, 4, 6"]);
    expect(rows(view, 1).map((row) => `${row.name} ${row.dose}`)).toEqual(["Run 400 m", "Wall Ball 20"]);
  });

  it("labels alternating EMOM minutes, and never puts the instance in the flow name", () => {
    const view = buildPlanView(alternatingEmom(), greek);
    expect(view.flow).toBe("EMOM");
    expect(view.preset).toBe("Εναλλάξ (μονά / ζυγά)");
    expect(view.params).toBe("κάθε 1′ · × 8");
    expect(view.blocks.map((block) => block.label)).toEqual(["Λεπτό 1, 3, 5, …", "Λεπτό 2, 4, 6, …"]);
  });

  it("AMRAP per round: the written rounds, «…» while a value keeps changing", () => {
    const view = buildPlanView(amrapPerRound(), greek);
    expect(view.params).toBe("7′");
    expect(rows(view).map((row) => [row.name, row.dose, row.load])).toEqual([
      ["Butterfly Pull-up", "15", ""],
      ["Power Snatch", "5-10-15", "40-45-50 kg…"],
    ]);
  });

  it("AMRAP windows and their rest", () => {
    expect(buildPlanView(windows(), greek).params).toBe("4 παράθυρα: 3′ · 3′ · 3′ · 4′ · 1′ ξεκούραση ανάμεσα");
  });

  it("shows interruptions apart from the main work", () => {
    const view = buildPlanView(interrupted(), greek);
    expect(view.params).toBe("");
    expect(rows(view)[0]).toMatchObject({ name: "Thruster", dose: "75", load: "40 kg" });
    expect(view.interrupt?.label).toBe("Κάθε 2′ σταματάς για");
    expect(view.interrupt?.units[0]!.rows[0]).toMatchObject({ name: "Burpee over Bar", dose: "10" });
    expect(view.preset).toBe("Με διακοπή");
  });

  it("intervals, with a fixed rest or until heart rate falls", () => {
    expect(buildPlanView(tabata(), greek).params).toBe("8 × 20″ άσκηση / 10″ ξεκούραση");
    expect(buildPlanView(hrIntervals(), greek).params).toBe("3 × 3′ άσκηση, ξεκούραση μέχρι οι παλμοί να πέσουν στους 120");
    expect(buildPlanView(tabata(), english).params).toBe("8 × 20″ work / 10″ rest");
  });

  it("a rest section has only its duration", () => {
    const view = buildPlanView(restSection(), greek);
    expect(view).toMatchObject({ flow: "Ξεκούραση", params: "2′", blocks: [] });
  });

  it("per side, measures with units, rest rows, words for load, notes and per-level notes", () => {
    const view = buildPlanView(measured(), greek, { rx: "RX" });
    const [split, rest, box, plank, dip] = rows(view);
    expect(split).toMatchObject({ perSide: true, dose: "10", load: "20 kg", measures: ["RPE 7-8-9"] });
    expect(rest).toMatchObject({ kind: "rest", name: "Ξεκούραση", dose: "30″" });
    expect(box!.measures).toEqual(["Ύψος 60 cm"]);
    expect(plank!.measures).toEqual(["Κράτημα 45″"]);
    expect(dip!.load).toBe("με βάρος");
    expect(view.note).toBe("Ήρεμα, τεχνική πρώτα");
    expect(view.levelNotes).toEqual([
      { level: "rx", label: "RX", note: "Με γιλέκο 10 kg" },
      { level: "scaled", label: "Scaled", note: "Χωρίς βάρος" },
    ]);
  });
});

describe("planSectionText", () => {
  it("writes a plan as text a coach can keep editing", () => {
    expect(planSectionText("Δευτέρα A", backSquat(), greek)).toBe(
      ["Δευτέρα A · Σετ", "4 σετ · 2′ ξεκούραση", "Back Squat 12-10-8-8 @ 60-65-70-75% · Tempo ↓3 ·1 ↑X ·1", "  Έλεγχος στο κατέβασμα, με ζώνη"].join("\n"),
    );
    expect(planSectionText("", differentRounds(), greek)).toBe(
      ["For Time", "6 γύροι · όριο 20′", "Γύρος 1, 3, 5:", "  Row 500 m", "  Burpee 15", "Γύρος 2, 4, 6:", "  Run 400 m", "  Wall Ball 20", "Σκορ: Χρόνος"].join("\n"),
    );
    expect(planSectionText("B", measured(), greek)).toContain("Bulgarian Split Squat (ανά πλευρά) 10 @ 20 kg · RPE 7-8-9");
  });
});
