import { describe, expect, it } from "vitest";
import {
  clock,
  doseCaption,
  entryAt,
  human,
  isRelative,
  loadCaption,
  mmss,
  parseClock,
  parseDose,
  parseLoad,
  parseNums,
  parseTimes,
  progress,
  repeatDose,
  repeatText,
  setCountOf,
  setLoads,
  showDoseAt,
  showLoadAt,
  showTimes,
  tempoParts,
  tempoShort,
  tempoText,
  type ParsedDose,
} from "./parse";
import type { PlanCell } from "./types";

const row = (...cells: PlanCell[]) => ({ cells });
const loads = (...ls: string[]) => row(...ls.map((l) => ({ l })));
const dose = (t: string) => parseDose(t) as ParsedDose;

describe("clock formatting", () => {
  it("shows seconds below a minute and m:ss above", () => {
    expect(clock(45)).toBe("45″");
    expect(clock(90)).toBe("1:30");
    expect(clock(150)).toBe("2:30");
    expect(mmss(45)).toBe("0:45");
    expect(mmss(600)).toBe("10:00");
  });

  it("gives minutes and seconds for a human sentence", () => {
    expect(human(150)).toEqual({ key: "PlanCore.human.minSec", values: { min: 2, sec: 30 } });
    expect(human(120)).toEqual({ key: "PlanCore.human.min", values: { min: 2 } });
    expect(human(45)).toEqual({ key: "PlanCore.human.sec", values: { sec: 45 } });
  });
});

describe("parseClock", () => {
  it("reads m:ss, seconds and minutes", () => {
    expect(parseClock("2:30")).toBe(150);
    expect(parseClock("90s")).toBe(90);
    expect(parseClock("90″")).toBe(90);
    expect(parseClock("60δ")).toBe(60);
    expect(parseClock("3'")).toBe(180);
    expect(parseClock("2min")).toBe(120);
    expect(parseClock("2λ")).toBe(120);
  });

  it("reads a bare number as minutes, or smartly (≤ 10 = minutes, else seconds)", () => {
    expect(parseClock("20")).toBe(1200);
    expect(parseClock("2", "smart")).toBe(120);
    expect(parseClock("90", "smart")).toBe(90);
  });

  it("returns null for empty and bad for anything else", () => {
    expect(parseClock("  ")).toBeNull();
    expect(parseClock("soon")).toBe("bad");
    expect(parseClock("90-120″")).toBe("bad");
  });
});

describe("parseTimes", () => {
  it("reads AMRAP windows 3'-3'-3'-4' and 3-3-3-4", () => {
    expect(parseTimes("3'-3'-3'-4'")).toEqual({ range: false, secs: [180, 180, 180, 240] });
    expect(parseTimes("3-3-3-4")).toEqual({ range: false, secs: [180, 180, 180, 240] });
    expect(showTimes(parseTimes("3-3-3-4"))).toBe("3:00 · 3:00 · 3:00 · 4:00");
  });

  it("reads 90-120″ as a range of rest", () => {
    expect(parseTimes("90-120″", "smart")).toEqual({ range: true, secs: [90, 120] });
    expect(showTimes(parseTimes("90-120″", "smart"))).toBe("1:30–2:00");
  });

  it("refuses zero and words", () => {
    expect(parseTimes("0-3")).toBe("bad");
    expect(parseTimes("3-x")).toBe("bad");
    expect(parseTimes("")).toBeNull();
  });
});

describe("parseNums", () => {
  it("reads per-set lists, ranges and keep-going lists", () => {
    expect(parseNums("12-10-8-8")).toEqual({ entries: [12, 10, 8, 8].map((n) => ({ min: n, max: n })), cont: false });
    expect(parseNums("8-12")).toEqual({ entries: [{ min: 8, max: 12 }], cont: false });
    expect(parseNums("8 έως 12")).toEqual({ entries: [{ min: 8, max: 12 }], cont: false });
    expect(parseNums("8-10, 6-8")).toEqual({ entries: [{ min: 8, max: 10 }, { min: 6, max: 8 }], cont: false });
    expect(parseNums("5-10-15…")).toEqual({ entries: [5, 10, 15].map((n) => ({ min: n, max: n })), cont: true });
    expect(parseNums("12-8")).toEqual({ entries: [{ min: 12, max: 12 }, { min: 8, max: 8 }], cont: false });
  });

  it("refuses words and a lone keep-going value", () => {
    expect(parseNums("heavy")).toBe("bad");
    expect(parseNums("5…")).toBe("bad");
    expect(parseNums("10-8, 6")).toBe("bad");
  });
});

describe("parseDose", () => {
  it("reads 12-10-8-8 as four sets", () => {
    const d = dose("12-10-8-8");
    expect(setCountOf(d)).toBe(4);
    expect([0, 1, 2, 3].map((i) => showDoseAt(d, i))).toEqual(["12", "10", "8", "8"]);
  });

  it("reads 4 x 8-10 each side: sets, a range and per side", () => {
    const d = dose("4 x 8-10 each side");
    expect(d.sets).toEqual({ min: 4, max: 4 });
    expect(d.entries).toEqual([{ min: 8, max: 10 }]);
    expect(d.perSide).toBe(true);
    expect(showDoseAt(d, 0)).toBe("8–10/side");
    expect(showDoseAt(d, 0, { perSide: "/πλευρά", within: "σε", from: "από", zone: "ζώνη" })).toBe("8–10/πλευρά");
    expect(dose("8 ανά πλευρά").perSide).toBe(true);
  });

  it("reads 3-4 sets as a range of sets", () => {
    expect(dose("3-4x12-15").sets).toEqual({ min: 3, max: 4 });
    expect(dose("3-4 σετ x 12").sets).toEqual({ min: 3, max: 4 });
  });

  it("reads 60″ max cal as max within a time", () => {
    const d = dose("60″ max cal");
    expect(d.max).toEqual({ within: 60 });
    expect(d.unit).toBe("kcal");
    expect(showDoseAt(d, 0)).toBe("max cal in 1:00");
    expect(dose("60s max cal").max).toEqual({ within: 60 });
    expect(dose("max").max).toEqual({ within: null });
  });

  it("reads the AMRAP 5-10-15 ladder as keep going", () => {
    const d = dose("5-10-15…");
    expect(d.cont).toBe(true);
    expect([0, 1, 2, 3, 4].map((i) => entryAt(d, i)?.min)).toEqual([5, 10, 15, 20, 25]);
  });

  it("reads distance, calories and time units", () => {
    expect(dose("500 m").unit).toBe("m");
    expect(showDoseAt(dose("2km"), 0)).toBe("2 km");
    expect(dose("15 cal").unit).toBe("kcal");
    expect(showDoseAt(dose("100 cal"), 0)).toBe("100 cal");
    expect(showDoseAt(dose("30s"), 0)).toBe("30″");
    expect(showDoseAt(dose("1:00"), 0)).toBe("1:00");
    expect(showDoseAt(dose("30″"), 0)).toBe("30″");
  });

  it("refuses what does not read", () => {
    expect(parseDose("lots")).toBe("bad");
    expect(parseDose("0")).toBe("bad");
    expect(parseDose("4x 10-8")).toBe("bad");
    expect(parseDose("")).toBeNull();
  });
});

describe("parseLoad", () => {
  it("reads kg (with decimals) and %", () => {
    expect(parseLoad("22.5kg")).toEqual({ kind: "kg", entries: [{ min: 22.5, max: 22.5 }], up: false });
    expect(parseLoad("22,5 κιλά")).toEqual({ kind: "kg", entries: [{ min: 22.5, max: 22.5 }], up: false });
    expect(showLoadAt(parseLoad("22.5kg"), 0)).toBe("22.5 kg");
    expect(parseLoad("70%")).toMatchObject({ kind: "pct" });
  });

  it("reads 'start 60% and build up'", () => {
    const l = parseLoad("60%↑");
    expect(l).toEqual({ kind: "pct", entries: [{ min: 60, max: 60 }], up: true });
    expect(showLoadAt(l, 0)).toBe("60%");
    expect(showLoadAt(l, 2)).toBe("↑ from 60%");
    expect(parseLoad("60%+")).toMatchObject({ up: true });
    expect(loadCaption(l)).toEqual({ key: "PlanCore.loadCaption.buildUp", values: { kind: "pct", value: "60%" } });
  });

  it("keeps words like βαρύ as the coach's text", () => {
    expect(parseLoad("βαρύ")).toEqual({ kind: "text", text: "βαρύ" });
    expect(showLoadAt(parseLoad("με βάρος"), 0)).toBe("με βάρος");
    expect(loadCaption(parseLoad("βαρύ"))).toEqual({ key: "PlanCore.loadCaption.text" });
  });

  it("reads body weight, RPE, zones and pace", () => {
    expect(parseLoad("bw")).toEqual({ kind: "bw" });
    expect(parseLoad("rpe 8")).toEqual({ kind: "rpe", min: 8, max: 8 });
    expect(parseLoad("z2")).toEqual({ kind: "zone", zone: 2 });
    expect(showLoadAt(parseLoad("2:00/500"), 0)).toBe("2:00/500m");
    expect(parseLoad("")).toBeNull();
  });
});

describe("captions", () => {
  it("words a list of sets, a range, a keep-going list, max and per side", () => {
    expect(doseCaption(dose("12-10-8-8"), "set")).toEqual([{ key: "PlanCore.caption.setList", values: { count: 4, list: "12 · 10 · 8 · 8" } }]);
    expect(doseCaption(dose("5-10-15…"), "round")).toEqual([
      { key: "PlanCore.caption.perList", values: { word: "round", list: "5 · 10 · 15" } },
      { key: "PlanCore.caption.cont", values: { step: "+5", word: "round" } },
    ]);
    expect(doseCaption(dose("4x8-10/side"), "set")).toEqual([
      { key: "PlanCore.caption.sets", values: { count: 4 } },
      { key: "PlanCore.caption.range", values: { range: "8–10" } },
      { key: "PlanCore.caption.perSide" },
    ]);
    expect(doseCaption(dose("60s max cal"), "set")).toEqual([{ key: "PlanCore.caption.maxWithin", values: { unit: "kcal", within: "1:00" } }]);
    expect(doseCaption(dose("10"), "set")).toEqual([{ key: "PlanCore.caption.reps", values: { count: 10 } }]);
    expect(doseCaption(dose("400 m"), "set")).toEqual([{ key: "PlanCore.caption.value", values: { value: "400 m" } }]);
    expect(doseCaption("bad", "set")).toEqual([{ key: "PlanCore.caption.badDose" }]);
    expect(doseCaption(null, "set")).toEqual([]);
  });

  it("words loads per set and ranges", () => {
    expect(loadCaption(parseLoad("60-70%"))).toEqual({ key: "PlanCore.loadCaption.range", values: { kind: "pct", value: "60–70%" } });
    expect(loadCaption(parseLoad("60kg"))).toEqual({ key: "PlanCore.loadCaption.value", values: { kind: "kg", value: "60 kg" } });
    expect(loadCaption(parseLoad("bw"))).toEqual({ key: "PlanCore.loadCaption.bw" });
  });
});

describe("setLoads: the unit is written once per row", () => {
  it("lets bare numbers inherit the unit stated in any column", () => {
    expect(setLoads(loads("60%", "+5", "", "75"), 4)).toEqual({ values: ["60%", "65%", "70%", "75%"], errors: [null, null, null, null], unit: "%" });
    expect(setLoads(loads("60", "70kg"), 2).values).toEqual(["60 kg", "70 kg"]);
  });

  it("marks a row of numbers with no unit anywhere as missing_unit", () => {
    const r = setLoads(loads("60", "70"), 2);
    expect(r.unit).toBeNull();
    expect(r.errors).toEqual(["missing_unit", "missing_unit"]);
  });

  it("marks a kg / % mix as mixed_unit", () => {
    const r = setLoads(loads("60kg", "70%"), 2);
    expect(r.unit).toBe("kg");
    expect(r.errors).toEqual([null, "mixed_unit"]);
  });

  it("keeps adding +x in the empty columns after it", () => {
    expect(setLoads(loads("60kg", "+2.5"), 4).values).toEqual(["60 kg", "62.5 kg", "65 kg", "67.5 kg"]);
  });

  it("spreads a→b and a->b to the last column", () => {
    expect(setLoads(loads("60→80%"), 5).values).toEqual(["60%", "65%", "70%", "75%", "80%"]);
    expect(setLoads(loads("60->80kg"), 3).values).toEqual(["60 kg", "70 kg", "80 kg"]);
  });

  it("repeats an empty column and reads decimals like 22.5", () => {
    expect(setLoads(loads("22.5kg"), 3).values).toEqual(["22.5 kg", "22.5 kg", "22.5 kg"]);
    expect(setLoads(loads("22,5 κιλά"), 1).values).toEqual(["22.5 kg"]);
  });

  it("passes words through (βαρύ, με βάρος) without asking for a unit", () => {
    const r = setLoads(loads("βαρύ", ""), 2);
    expect(r.values).toEqual(["βαρύ", "βαρύ"]);
    expect(r.errors).toEqual([null, null]);
    expect(r.unit).toBeNull();
  });

  it("follows the reference program: 12-10-8-8 with 60% and +5", () => {
    const r = row({ d: "12", l: "60%" }, { d: "10", l: "+5" }, { d: "8" }, { d: "8" });
    expect(repeatDose(r, 4)).toEqual(["12", "10", "8", "8"]);
    expect(setLoads(r, 4).values).toEqual(["60%", "65%", "70%", "75%"]);
  });
});

describe("progress, repeatText, isRelative", () => {
  it("progresses numeric measures like load", () => {
    expect(progress(row({ rpe: "7" }, { rpe: "+1" }), "rpe", 3)).toEqual(["7", "8", "9"]);
    expect(progress(row({ rpe: "7→9" }), "rpe", 3)).toEqual(["7", "8", "9"]);
    expect(progress(row({ pace: "2:00" }, { pace: "-0:05" }), "pace", 3, true)).toEqual(["2:00", "1:55", "1:50"]);
    expect(progress(row({ rir: "2" }), "rir", 3)).toEqual(["2", "2", "2"]);
  });

  it("only repeats text measures (tempo never progresses)", () => {
    expect(repeatText(row({ tempo: "31X1" }, {}, { tempo: "2010" }), "tempo", 4)).toEqual(["31X1", "31X1", "2010", "2010"]);
  });

  it("knows relative values", () => {
    expect(isRelative("+5")).toBe(true);
    expect(isRelative("-0:05")).toBe(true);
    expect(isRelative("60→80")).toBe(true);
    expect(isRelative("60->80")).toBe(true);
    expect(isRelative("60")).toBe(false);
  });
});

describe("tempo", () => {
  it("reads four marks with X = explosive", () => {
    expect(tempoParts("31X1")).toEqual({ down: 3, bottom: 1, up: "X", top: 1 });
    expect(tempoParts("3-1-x-1")).toEqual({ down: 3, bottom: 1, up: "X", top: 1 });
    expect(tempoShort("31x1")).toBe("↓3 ·1 ↑X ·1");
    expect(tempoText("31X1")?.[2]).toEqual({ key: "PlanCore.tempo.upExplosive" });
    expect(tempoText("31X1")?.[0]).toEqual({ key: "PlanCore.tempo.down", values: { secs: 3 } });
  });

  it("refuses anything but four marks", () => {
    expect(tempoParts("31X")).toBeNull();
    expect(tempoParts("31X12")).toBeNull();
    expect(tempoShort("slow")).toBeNull();
  });
});
