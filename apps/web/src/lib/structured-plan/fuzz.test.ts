/**
 * ADR-270: property-based fuzzing of the core with a tiny seeded generator
 * (no dependency). Every run uses the same seeds, so a failure reproduces.
 */
import { describe as group, expect, it } from "vitest";
import { FLOW_KEYS, MEASURE_KEYS, PRESETS, STRUCT_KEYS } from "./catalog";
import { describe, summary, timeline } from "./describe";
import { applyPreset, changeFlow, newRow, newSection, setStructure, togglePerRound } from "./factory";
import { fuzzy, rankItems } from "./fuzzy";
import {
  clock,
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
  repeatText,
  setLoads,
  showDose,
  showDoseAt,
  showEntry,
  showLoadAt,
  tempoParts,
  tempoText,
  type ParsedDose,
} from "./parse";
import { blockLabel, canPerRound, occurrences, totalRounds } from "./rounds";
import type { PlanCell, PlanSection } from "./types";
import { validateSection } from "./validate";
import corpus from "./__fixtures__/corpus.json";

/** mulberry32: a small seeded PRNG. */
function rng(seed: number) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const int = (n: number) => Math.floor(next() * n);
  const pick = <T>(xs: readonly T[]): T => xs[int(xs.length)];
  return { next, int, pick };
}

/** Tokens coaches type, plus noise. */
const TOKENS = [
  "0", "1", "2", "3", "5", "8", "10", "12", "15", "21", "22", "60", "90", "120", "1000", "99999999999", "2.5", "22,5", "7,5", ":", ":00", ":30", ":90",
  "-", "–", "—", "−", ",", ", ", "/", " ", "  ", "\t", "…", "...", "+", "→", "->", "ως", "έως", "to", "~", "x", "×", "χ", "Χ", "X", "*", "ή", "or",
  "s", "sec", "″", "\"", "”", "''", "δ", "δευτ.", "min", "′", "'", "’", "λ", "λεπτά", "m", "μ", "km", "χλμ", "cal", "θερμίδες", "reps", "επαν.",
  "kg", "κιλά", "%", "1RM", "@", "↑", "bw", "ΣΒ", "rpe", "z", "zone", "ζώνη", "/500m", "max", "AMRAP", "μέγιστες", "σε", "in",
  "each side", "/πλευρά", "ανά πόδι", "βαρύ", "με βάρος", "sets", "σετ", "🔥", "💪", "́", "​", "(", ")", "[", "{", "\\", "$", ".", "e5", "NaN", "Infinity",
];
const typed = (r: ReturnType<typeof rng>, max = 6) => Array.from({ length: 1 + r.int(max) }, () => r.pick(TOKENS)).join("");

const SEEDS = Array.from({ length: 8 }, (_, k) => 1000 + k * 7919);
/** Cases per seed; raise with PLAN_FUZZ_N for a longer local run. */
const N = Number(process.env.PLAN_FUZZ_N) || 400;

group("fuzz: parsers never throw (ADR-270)", () => {
  it.each(SEEDS)("seed %i", (seed) => {
    const r = rng(seed);
    for (let k = 0; k < N; k++) {
      const t = typed(r);
      expect(() => {
        normText(t);
        parseClock(t, "smart");
        parseClock(t, "min");
        clockAmbiguity(t, "smart");
        parseTimes(t, "smart");
        parseTimes(t, "min");
        parseNums(t);
        parseCountRange(t);
        const d = parseDose(t);
        doseCaption(d, "set");
        showDoseAt(d, 3);
        const l = parseLoad(t);
        showLoadAt(l, 2);
        tempoParts(t);
        tempoText(t);
        isRelative(t);
        fuzzy(t, "Back Squat · Ξεκούραση");
        const row = { cells: Array.from({ length: 1 + r.int(5) }, () => ({ d: typed(r, 3), l: typed(r, 3), rpe: typed(r, 3), pace: typed(r, 3) }) as PlanCell) };
        setLoads(row, 6);
        progress(row, "rpe", 6);
        progress(row, "pace", 6, true);
        measureCellErrors(row, "rpe", 6);
        repeatText(row, "d", 6);
      }, JSON.stringify(t)).not.toThrow();
    }
  });
});

group("fuzz: canonical forms round-trip", () => {
  const strip = (d: ParsedDose | null | "bad") => {
    if (!d || d === "bad") return d;
    const rest: Partial<ParsedDose> = { ...d };
    delete rest.ambiguous;
    return rest;
  };

  it.each(SEEDS)("parseDose(showDose(d)) reads d again, seed %i", (seed) => {
    const r = rng(seed);
    let checked = 0;
    for (let k = 0; k < N * 2; k++) {
      const d = parseDose(typed(r, 5));
      if (!d || d === "bad") continue;
      checked++;
      expect(strip(parseDose(showDose(d))), showDose(d)).toEqual(strip(d));
    }
    expect(checked).toBeGreaterThan(20);
  });

  it.each(SEEDS)("generated doses round-trip, seed %i", (seed) => {
    const r = rng(seed);
    for (let k = 0; k < N; k++) {
      const n = () => 1 + r.int(30);
      const list = Array.from({ length: 1 + r.int(4) }, () => {
        const a = n();
        return r.next() < 0.3 ? { min: a, max: a + 1 + r.int(5) } : { min: a, max: a };
      });
      const d: ParsedDose = {
        sets: null,
        entries: list,
        unit: r.pick(["reps", "kcal", "m", "secs"] as const),
        perSide: r.next() < 0.3,
        cont: list.length >= 2 && list.every((e) => e.min === e.max) && r.next() < 0.3,
        max: null,
      };
      expect(strip(parseDose(showDose(d))), showDose(d)).toEqual(d);
    }
  });

  it.each(SEEDS)("times and loads round-trip, seed %i", (seed) => {
    const r = rng(seed);
    for (let k = 0; k < N; k++) {
      const secs = 1 + r.int(3600);
      expect(parseClock(clock(secs), "smart")).toBe(secs);
      const windows = Array.from({ length: 1 + r.int(5) }, () => 60 * (1 + r.int(20)));
      expect((parseTimes(windows.map(clock).join("-"), "min") as { secs: number[] }).secs).toEqual(windows);
      const kind = r.pick(["kg", "pct"] as const);
      const a = r.int(400) / 2;
      const e = r.next() < 0.5 ? { min: a, max: a } : { min: a, max: a + 2.5 * (1 + r.int(10)) };
      const parsed = parseLoad(showEntry(e, kind));
      expect(parsed, showEntry(e, kind)).toMatchObject({ kind, entries: [e], up: false });
    }
  });
});

group("fuzz: unit inference is deterministic", () => {
  it.each(SEEDS)("seed %i", (seed) => {
    const r = rng(seed);
    const cellsOf = ["60", "+5", "-2.5", "70%", "60kg", "65-70", "60→80", "", "", "βαρύ", "22,5", "80 κιλά", "60%↑"];
    for (let k = 0; k < N; k++) {
      const cells = Array.from({ length: 1 + r.int(8) }, () => ({ l: r.pick(cellsOf) }));
      const n = cells.length + r.int(3);
      const a = setLoads({ cells }, n);
      expect(setLoads({ cells: structuredClone(cells) }, n)).toEqual(a);
      const stated = cells.map((c) => (/%/.test(c.l) ? "%" : /kg|κιλ/.test(c.l) ? "kg" : null)).find(Boolean) ?? null;
      expect(a.unit).toBe(stated);
      if (a.unit) expect(a.errors).not.toContain("missing_unit");
      else cells.forEach((c, i) => /^[+-]?\d/.test(c.l) && expect(["missing_unit", "no_base"]).toContain(a.errors[i]));
      if (a.unit === "%") a.values.forEach((v, i) => !a.errors[i] && /^\d/.test(v) && expect(v).toMatch(/%$/));
    }
  });
});

/** Random JSON-ish junk. */
function junk(r: ReturnType<typeof rng>, depth = 0): unknown {
  const k = r.int(depth > 3 ? 6 : 9);
  switch (k) {
    case 0:
      return null;
    case 1:
      return r.int(1000) - 500;
    case 2:
      return r.next() < 0.5;
    case 3:
    case 4:
      return typed(r);
    case 5:
      return undefined;
    case 6:
      return Array.from({ length: r.int(4) }, () => junk(r, depth + 1));
    default:
      return Object.fromEntries(Array.from({ length: r.int(5) }, () => [r.pick(["id", "kind", "name", "cells", "d", "l", "flow", "blocks", "params", "rpe", "x", "extra", typed(r, 2)]), junk(r, depth + 1)]));
  }
}

/** Replaces one random node of a value with junk. */
function mutate(r: ReturnType<typeof rng>, v: unknown, depth = 0): unknown {
  if (depth > 0 && r.next() < 0.25) return junk(r);
  if (Array.isArray(v)) return v.length ? v.map((x, i) => (i === r.int(v.length) ? mutate(r, x, depth + 1) : x)) : [junk(r)];
  if (v && typeof v === "object") {
    const keys = Object.keys(v);
    const key = r.pick(keys.length ? keys : ["x"]);
    return { ...(v as object), [key]: mutate(r, (v as Record<string, unknown>)[key], depth + 1) };
  }
  return junk(r);
}

group("fuzz: validation never throws", () => {
  const sections = (corpus.sections as { section: unknown }[]).map((e) => e.section);

  it.each(SEEDS)("on junk and on mutated corpus sections, seed %i", (seed) => {
    const r = rng(seed);
    for (let k = 0; k < N; k++) {
      const j = junk(r);
      expect(() => validateSection(j)).not.toThrow();
      const m = mutate(r, r.pick(sections));
      let out: unknown;
      expect(() => {
        out = validateSection(m);
      }, JSON.stringify(m).slice(0, 300)).not.toThrow();
      expect(validateSection(structuredClone(m))).toEqual(out);
    }
  });
});

group("fuzz: well-shaped random sections go through every reader", () => {
  it.each(SEEDS)("seed %i", (seed) => {
    const r = rng(seed);
    for (let k = 0; k < N / 4; k++) {
      let s: PlanSection = r.next() < 0.5 ? newSection(r.pick(FLOW_KEYS)) : applyPreset(newSection("sets"), r.pick(PRESETS).key);
      if (r.next() < 0.5) s = changeFlow(s, r.pick(FLOW_KEYS));
      for (const key of Object.keys(s.params) as (keyof PlanSection["params"])[]) if (r.next() < 0.5) s.params[key] = typed(r, 3);
      s.blocks = Array.from({ length: s.flow === "rest" ? 0 : 1 + r.int(4) }, () =>
        Array.from({ length: 1 + r.int(4) }, () =>
          newRow(r.next() < 0.2 ? "rest" : "ex", {
            name: typed(r, 2),
            dose: typed(r, 3),
            load: typed(r, 3),
            extra: MEASURE_KEYS.filter(() => r.next() < 0.3),
            perRound: r.next() < 0.4,
            group: r.next() < 0.3 ? "g" : null,
            cells: Array.from({ length: r.int(6) }, () => ({ d: typed(r, 2), l: typed(r, 2), rpe: typed(r, 2), tempo: typed(r, 2) })),
          }),
        ),
      );
      const row = s.blocks[0]?.[0];
      if (row && r.next() < 0.5) s = setStructure(s, 0, row.id, r.pick(STRUCT_KEYS));
      if (row && r.next() < 0.3) s = togglePerRound(s, row.id);
      expect(() => {
        validateSection(s);
        describe(s);
        timeline(s);
        summary(s);
        totalRounds(s);
        s.blocks.forEach((_, b) => {
          occurrences(s, b);
          blockLabel(s, b);
          canPerRound(s, b);
        });
        rankItems(typed(r, 2), PRESETS, (p) => ({ label: p.key, alt: p.aliases.join(" ") }));
      }, JSON.stringify(s).slice(0, 300)).not.toThrow();
      const t = timeline(s);
      expect(t.segments.every((x) => x.secs > 0 && Number.isFinite(x.secs))).toBe(true);
      expect(t.open ? t.total === null : Number.isFinite(t.total)).toBe(true);
    }
  });
});
