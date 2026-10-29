import { describe, expect, it } from "vitest";
import {
  clockAmbiguity,
  doseCaption,
  isRelative,
  measureCellErrors,
  normText,
  parseClock,
  parseCountRange,
  parseDose,
  parseLoad,
  parseNums,
  parseTimes,
  progress,
  setLoads,
  showDose,
  tempoCanonical,
  tempoParts,
  type ParsedDose,
} from "./parse";
import type { PlanCell } from "./types";

const row = (...cells: PlanCell[]) => ({ cells });
const loads = (...ls: string[]) => row(...ls.map((l) => ({ l })));
const dose = (t: string) => parseDose(t) as ParsedDose;

describe("normalisation (ADR-270 notation)", () => {
  it("unifies case, accents, dashes, primes, quotes, ellipsis and arrows", () => {
    expect(normText("  Ανά   ΠΛΕΥΡΆ ")).toBe("ανα πλευρα");
    expect(normText("8–12")).toBe("8-12");
    expect(normText("8—12")).toBe("8-12");
    expect(normText("−5")).toBe("-5");
    expect(normText("3’")).toBe("3′");
    expect(normText("90”")).toBe("90″");
    expect(normText("90''")).toBe("90″");
    expect(normText("5-10-15...")).toBe("5-10-15…");
    expect(normText("60 -> 80")).toBe("60→80");
    expect(normText(undefined)).toBe("");
  });
});

describe("time fields: bugs fixed", () => {
  it("reads iOS smart quotes as minute / second marks", () => {
    expect(parseClock("3’")).toBe(180);
    expect(parseClock("90”")).toBe(90);
    expect(parseTimes("3’-3’-3’-4’")).toEqual({ range: false, secs: [180, 180, 180, 240] });
  });

  it("refuses m:ss with 60 or more seconds", () => {
    expect(parseClock("0:90")).toBe("bad");
    expect(parseClock("1:59")).toBe(119);
  });

  it("reads Greek and English unit words, decimals and min+sec", () => {
    expect(parseClock("90 δευτ.")).toBe(90);
    expect(parseClock("2 λεπτά")).toBe(120);
    expect(parseClock("2 mins")).toBe(120);
    expect(parseClock("1.5 min")).toBe(90);
    expect(parseClock("1,5 λ")).toBe(90);
    expect(parseClock("2′30″")).toBe(150);
    expect(parseClock("2 λ 30")).toBe(150);
  });

  it("gives every bare part of a smart field one unit", () => {
    expect(parseTimes("5-15", "smart")).toEqual({ range: true, secs: [5, 15] });
    expect(parseTimes("2-3", "smart")).toEqual({ range: true, secs: [120, 180] });
    expect(parseTimes("90-120", "smart")).toEqual({ range: true, secs: [90, 120] });
  });

  it("reads windows split by commas or slashes, never as a range", () => {
    expect(parseTimes("3/3/3/4")).toEqual({ range: false, secs: [180, 180, 180, 240] });
    expect(parseTimes("3, 4")).toEqual({ range: false, secs: [180, 240] });
    expect(parseTimes("3-")).toBe("bad");
  });

  it("says how a bare smart time was read", () => {
    expect(clockAmbiguity("10", "smart")).toMatchObject({ alt: "seconds", write: "10″" });
    expect(clockAmbiguity("90", "smart")).toMatchObject({ alt: "minutes", write: "90′" });
    expect(clockAmbiguity("90″", "smart")).toBeNull();
  });

  it("reads sets ranges with an en dash, ή, or", () => {
    expect(parseCountRange("3–4")).toEqual({ min: 3, max: 4 });
    expect(parseCountRange("3 ή 4")).toEqual({ min: 3, max: 4 });
    expect(parseCountRange("3 or 4")).toEqual({ min: 3, max: 4 });
    expect(parseCountRange("4-3")).toBeNull();
    expect(parseCountRange("0")).toBeNull();
  });
});

describe("dose: bugs fixed and ambiguity", () => {
  it("reads a unit written after every value", () => {
    expect(dose("30s-45s")).toMatchObject({ unit: "secs", entries: [{ min: 30, max: 45 }] });
    expect(dose("400m-800m")).toMatchObject({ unit: "m", entries: [{ min: 400, max: 800 }] });
    expect(parseDose("1min-30s")).toBe("bad");
  });

  it("reads Greek and English unit words", () => {
    expect(dose("10 rep").unit).toBe("reps");
    expect(dose("10 επαναλήψεις").entries).toEqual([{ min: 10, max: 10 }]);
    expect(dose("500 μέτρα")).toMatchObject({ unit: "m", entries: [{ min: 500, max: 500 }] });
    expect(dose("2 χλμ")).toMatchObject({ unit: "m", entries: [{ min: 2000, max: 2000 }] });
    expect(dose("15 θερμίδες").unit).toBe("kcal");
    expect(dose("2 λεπτά")).toMatchObject({ unit: "secs", entries: [{ min: 120, max: 120 }] });
    expect(dose("8—12").entries).toEqual([{ min: 8, max: 12 }]);
  });

  it("reads per side in more ways", () => {
    expect(dose("8 per side").perSide).toBe(true);
    expect(dose("8/leg").perSide).toBe(true);
    expect(dose("8 ΑΝΆ ΠΌΔΙ").perSide).toBe(true);
  });

  it("reads max within a time in either order", () => {
    expect(dose("max cal σε 1:00")).toMatchObject({ unit: "kcal", max: { within: 60 } });
    expect(dose("max reps in 60″")).toMatchObject({ unit: "reps", max: { within: 60 } });
    expect(dose("AMRAP").max).toEqual({ within: null });
    expect(parseDose("60s max cal in 1:00")).toBe("bad");
  });

  it("flags 10-12 as a range that could be two sets", () => {
    const d = dose("10-12");
    expect(d.entries).toEqual([{ min: 10, max: 12 }]);
    expect(d.ambiguous).toMatchObject({ alt: "list", write: "10, 12" });
    expect(dose(d.ambiguous!.write).entries).toEqual([
      { min: 10, max: 10 },
      { min: 12, max: 12 },
    ]);
    expect(doseCaption(d, "set").at(-1)).toEqual({ key: "PlanCore.ambiguous.rangeOrList", values: { range: "10–12", count: 2, write: "10, 12" } });
    expect(dose("4x10-12").ambiguous).toBeUndefined();
  });

  it("flags a rising list that could be meant to keep climbing", () => {
    const d = dose("5-10-15");
    expect(d.cont).toBe(false);
    expect(d.ambiguous).toMatchObject({ alt: "ladder", write: "5-10-15…" });
    expect(dose("5-10-15…").ambiguous).toBeUndefined();
    expect(dose("21-15-9").ambiguous).toBeUndefined();
    expect(dose("12-10-8-8").ambiguous).toBeUndefined();
    expect(dose("8-8").ambiguous).toBeUndefined();
  });

  it("never reads zero, negatives or junk", () => {
    for (const t of ["0", "-5", "0-5", "💪", "x", "10-", "--", "…", "4x0", "0x10"]) expect(parseDose(t)).toBe("bad");
    expect(parseDose("   ")).toBeNull();
  });

  it("round-trips canonical text", () => {
    for (const t of ["10", "10, 12", "8-12", "12-10-8-8", "5-10-15…", "4x8-10 each side", "30s", "400 m", "15 cal", "60s max cal", "max", "3-4x12"]) {
      const d = dose(t);
      expect(parseDose(showDose(d))).toEqual(d);
    }
  });
});

describe("load: bugs fixed", () => {
  it("reads a comma as decimal only before a single digit", () => {
    expect(parseLoad("22,5kg")).toMatchObject({ kind: "kg", entries: [{ min: 22.5, max: 22.5 }] });
    expect(parseLoad("60,70%")).toMatchObject({ kind: "pct", entries: [{ min: 60, max: 60 }, { min: 70, max: 70 }] });
  });

  it("reads a unit on both ends of a range, 1RM and @", () => {
    expect(parseLoad("60%-70%")).toMatchObject({ kind: "pct", entries: [{ min: 60, max: 70 }] });
    expect(parseLoad("60kg-70kg")).toMatchObject({ kind: "kg", entries: [{ min: 60, max: 70 }] });
    expect(parseLoad("70% 1RM")).toMatchObject({ kind: "pct" });
    expect(parseLoad("70% του 1RM")).toMatchObject({ kind: "pct" });
    expect(parseLoad("@70%")).toMatchObject({ kind: "pct" });
    expect(parseLoad("@8")).toEqual({ kind: "rpe", min: 8, max: 8 });
    expect(parseLoad("60 ΚΙΛΆ")).toMatchObject({ kind: "kg" });
  });

  it("flags 60-70% as a range that could be two sets", () => {
    const l = parseLoad("60-70%");
    expect(l).toMatchObject({ kind: "pct", ambiguous: { alt: "list", write: "60%, 70%" } });
  });

  it("calls a non-load unit wrong instead of words", () => {
    expect(parseLoad("60 km")).toEqual({ kind: "wrong", text: "60 km" });
    expect(parseLoad("20 reps")).toMatchObject({ kind: "wrong" });
    expect(parseLoad("βαρύ")).toEqual({ kind: "text", text: "βαρύ" });
    expect(parseLoad("-10kg")).toEqual({ kind: "text", text: "-10kg" });
  });
});

describe("setLoads: bugs fixed", () => {
  it("reads a range per column and lets it inherit the unit", () => {
    expect(setLoads(loads("60%", "65-70"), 2)).toEqual({ values: ["60%", "65–70%"], errors: [null, null], unit: "%" });
  });

  it("reads 'start 60% and build up' in a column", () => {
    expect(setLoads(loads("60%↑", "", ""), 3)).toEqual({ values: ["60%", "↑ 60%", "↑ 60%"], errors: [null, null, null], unit: "%" });
    expect(setLoads(loads("60%+", "+5"), 2).values).toEqual(["60%", "65%"]);
  });

  it("refuses a change with nothing before it (no_base)", () => {
    expect(setLoads(loads("+5kg", ""), 2).errors).toEqual(["no_base", null]);
    expect(setLoads(loads("βαρύ", "+5kg"), 2).errors).toEqual([null, "no_base"]);
    expect(setLoads(loads("60kg", "-10"), 2).values).toEqual(["60 kg", "50 kg"]);
  });

  it("refuses a non-load unit and decimal commas stay decimals", () => {
    expect(setLoads(loads("60 km"), 1).errors).toEqual(["wrong_unit"]);
    expect(setLoads(loads("22,5kg", "+2,5"), 3).values).toEqual(["22.5 kg", "25 kg", "27.5 kg"]);
    expect(setLoads(loads("60kg", "−5"), 2).values).toEqual(["60 kg", "55 kg"]);
  });

  it("spreads with ως / έως / -> and refuses a kg→% spread", () => {
    expect(setLoads(loads("60 ως 80%"), 3).values).toEqual(["60%", "70%", "80%"]);
    expect(setLoads(loads("60 έως 80%"), 3).values).toEqual(["60%", "70%", "80%"]);
    expect(setLoads(loads("60kg→80%"), 2).errors[0]).toBe("wrong_unit");
  });

  it("never throws on junk cells", () => {
    expect(setLoads({ cells: [null as unknown as PlanCell, { l: 5 as unknown as string }] }, 2).values).toEqual(["", ""]);
    expect(setLoads({ cells: undefined as unknown as PlanCell[] }, 2).values).toEqual(["", ""]);
  });
});

describe("measures: bugs fixed", () => {
  it("keeps a range as typed and does not add to it", () => {
    expect(progress(row({ rpe: "7-8" }, {}, { rpe: "+1" }), "rpe", 3)).toEqual(["7-8", "7-8", "+1"]);
    expect(measureCellErrors(row({ rpe: "7-8" }, {}, { rpe: "+1" }), "rpe", 3)).toEqual([null, null, "no_base"]);
    expect(measureCellErrors(row({ rpe: "7" }, { rpe: "+1" }), "rpe", 2)).toEqual([null, null]);
  });

  it("reads tempo with Greek Χ, dots and slashes", () => {
    expect(tempoParts("31Χ1")).toEqual({ down: 3, bottom: 1, up: "X", top: 1 });
    expect(tempoParts("3.1.x.1")).toEqual({ down: 3, bottom: 1, up: "X", top: 1 });
    expect(tempoCanonical("3/1/χ/1")).toBe("31X1");
  });

  it("knows ως / έως spreads as relative, not words that contain them", () => {
    expect(isRelative("60 ως 80")).toBe(true);
    expect(isRelative("πως")).toBe(false);
    expect(parseNums("8 ως 12")).toEqual({ entries: [{ min: 8, max: 12 }], cont: false });
  });
});

describe("bounds: bugs found by fuzzing", () => {
  it("refuses numbers past a billion instead of reading 1e+22", () => {
    expect(parseDose("1000000000")).not.toBe("bad");
    expect(parseDose("10000000000000000000000")).toBe("bad");
    expect(parseClock("99999999999", "smart")).toBe("bad");
    expect(parseLoad("1e22kg")).toMatchObject({ kind: "text" });
    expect(setLoads(loads("60kg", "99999999999999"), 2)).toEqual({ values: ["60 kg", "99999999999999"], errors: [null, null], unit: "kg" });
  });

  it("caps counts at 999 so clocks and tables stay finite", () => {
    expect(parseCountRange("999")).toEqual({ min: 999, max: 999 });
    expect(parseCountRange("3-1000")).toBeNull();
    expect(parseDose("1000x10")).toBe("bad");
  });

  it("writes canonical doses with full precision", () => {
    expect(showDose(dose("2.522"))).toBe("2.522");
  });
});
