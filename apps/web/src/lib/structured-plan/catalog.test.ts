import { describe, expect, it } from "vitest";
import {
  FLOWS,
  FLOW_KEYS,
  MEASURES,
  MEASURE_KEYS,
  MODS,
  PRESETS,
  STRUCTS,
  STRUCT_KEYS,
  hasExercises,
  hasTimeStep,
  measureUnit,
  paramDefs,
  presetByKey,
  scoresFor,
  structDefaults,
} from "./catalog";
import { fuzzy, rankItems } from "./fuzzy";

describe("catalog (ADR-270)", () => {
  it("has the six flows with the agreed defaults", () => {
    expect(FLOW_KEYS).toEqual(["sets", "for_time", "amrap", "emom", "intervals", "rest"]);
    const dflt = (f: keyof typeof FLOWS) => Object.fromEntries(FLOWS[f].params.map((p) => [p.key, p.dflt]));
    expect(dflt("sets")).toEqual({ sets: "4", rest: "90″" });
    expect(dflt("for_time")).toEqual({ rounds: "1", cap: "" });
    expect(dflt("amrap")).toEqual({ dur: "12", rest: "" });
    expect(dflt("emom")).toEqual({ every: "1:00", times: "10" });
    expect(dflt("intervals")).toEqual({ work: "20″", off: "10″", rounds: "8" });
    expect(dflt("rest")).toEqual({ dur: "2:00" });
  });

  it("keeps structures and add-ons where the mockup allows them", () => {
    expect(FLOWS.sets.structs).toEqual(["single", "superset", "complex", "cluster", "drop", "restpause"]);
    expect(FLOWS.emom.structs).toContain("cluster");
    expect(FLOWS.amrap.structs).not.toContain("drop");
    expect(FLOWS.rest.structs).toEqual([]);
    expect(FLOWS.sets.mods).toEqual(["interrupt"]);
    expect(FLOWS.intervals.mods).toEqual(["hr"]);
    expect(FLOWS.emom.mods).toEqual([]);
    expect(STRUCTS.superset.group && STRUCTS.complex.group).toBe(true);
    expect(STRUCT_KEYS.filter((k) => !STRUCTS[k].group)).toEqual(["single", "cluster", "drop", "restpause"]);
    expect(structDefaults("cluster")).toEqual({ clusters: "3", intra: "15″" });
    expect(structDefaults("drop")).toEqual({ drops: "2", dropby: "-20%" });
    expect(structDefaults("restpause")).toEqual({ minis: "3", intra: "15″" });
    expect(MODS.interrupt.params[0]).toMatchObject({ key: "intEvery", dflt: "2:00" });
    expect(MODS.hr.params[0]).toMatchObject({ key: "hrTarget", dflt: "120" });
  });

  it("knows each flow's score options, default first", () => {
    expect(FLOWS.sets.scores[0]).toBe("none");
    expect(FLOWS.for_time.scores[0]).toBe("time");
    expect(FLOWS.amrap.scores[0]).toBe("rounds_reps");
    expect(scoresFor({ flow: "emom", preset: "death_by" })).toContain("rounds_reps");
    expect(scoresFor({ flow: "emom", preset: null })).not.toContain("rounds_reps");
  });

  it("has active parameters per flow and add-on", () => {
    expect(paramDefs("for_time", { interrupt: true }).map((p) => p.key)).toEqual(["rounds", "cap", "intEvery"]);
    expect(paramDefs("emom", { interrupt: true }).map((p) => p.key)).toEqual(["every", "times"]);
    expect(hasTimeStep("rest") && !hasExercises("rest")).toBe(true);
    expect(hasExercises("sets")).toBe(true);
  });

  it("has the measures, units shown only when the value does not say them", () => {
    expect(MEASURE_KEYS).toEqual(["pace", "tempo", "rpe", "rir", "zone", "height", "dist", "hold", "side"]);
    expect(MEASURES.rpe.max).toBe(10);
    expect(MEASURES.tempo.text).toBe(true);
    expect(MEASURES.side.flag).toBe(true);
    expect(MEASURES.pace.clock && MEASURES.hold.clock).toBe(true);
    expect(measureUnit("height", "60")).toBe("cm");
    expect(measureUnit("height", "60cm")).toBeNull();
    expect(measureUnit("pace", "2:00")).toBe("per500m");
    expect(measureUnit("pace", "2:00/km")).toBeNull();
    expect(measureUnit("tempo", "31X1")).toBeNull();
  });

  it("has all 17 presets with stable keys and i18n labels", () => {
    expect(PRESETS.map((p) => p.key)).toEqual([
      "tabata", "billat", "hrr", "death_by", "even_odd", "complex_emom", "edt", "chipper", "21_15_9",
      "ladder", "calorie_target", "to_failure", "superset", "cluster", "drop_set", "rest_pause", "interrupt",
    ]);
    for (const p of PRESETS) {
      expect(p.labelKey).toBe(`PlanCore.preset.${p.key}`);
      expect(FLOWS[p.flow]).toBeDefined();
      if (p.struct) expect(FLOWS[p.flow].structs).toContain(p.struct);
      for (const m of Object.keys(p.mods || {})) expect(FLOWS[p.flow].mods).toContain(m);
    }
    expect(presetByKey("tabata")?.params).toEqual({ work: "20″", off: "10″", rounds: "8" });
    expect(presetByKey("death_by")).toMatchObject({ flow: "emom", reps: "1-2-3…", params: { every: "1:00", times: "" } });
    expect(presetByKey("even_odd")?.slots).toBe(2);
    expect(presetByKey("edt")).toMatchObject({ flow: "amrap", struct: "superset", score: "reps" });
  });

  it("finds flows and presets by alias, in English and Greek", () => {
    const items = [
      ...FLOW_KEYS.map((k) => ({ key: k, alt: FLOWS[k].aliases.join(" ") })),
      ...PRESETS.map((p) => ({ key: p.key, alt: p.aliases.join(" ") })),
    ];
    const top = (q: string) => rankItems(q, items, (it) => ({ label: it.key.replace(/_/g, " "), alt: it.alt }))[0]?.item.key;
    expect(top("tabata")).toBe("tabata");
    expect(top("μονα ζυγα")).toBe("even_odd");
    expect(top("θανατος")).toBe("death_by");
    expect(top("δυναμη")).toBe("sets");
    expect(fuzzy("πυραμιδα", PRESETS.find((p) => p.key === "ladder")!.aliases.join(" "))).not.toBeNull();
  });
});
