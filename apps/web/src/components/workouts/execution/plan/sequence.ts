/**
 * ADR-270: the run sequence of a structured plan section — the ordered steps
 * an athlete does, each with the concrete values of its set or round, grouped
 * into the phases the flow's clock runs through. Pure: no React, no
 * translated text (words inside shown values come in through `ShowWords`).
 *
 * Rules (docs/plans/structured-wod-plan.md, product rules):
 *   - supersets and complexes run set-wise: set 1 = every exercise of the
 *     group, then set 2 …;
 *   - blocks are kinds of round that alternate (1, 3, 5 … / 2, 4, 6 …);
 *   - an empty value is "as before", `+x` keeps changing, `a→b` spreads; an
 *     AMRAP has no last round, so after the last written round a number
 *     repeats and `+x` keeps going;
 *   - interruptions pause the main work every X and resume where it was
 *     (the runner fires them from the clock: `interrupt`).
 */
import type { PlanFlow, PlanMeasure, PlanRow, PlanSection, PlanUnit } from "@/lib/structured-plan/types";
import { setsRange, structOf, unitKey, unitsOf, usesCells as rowUsesCells } from "@/lib/structured-plan/rounds";

import {
  parseClock,
  parseDose,
  parseLoad,
  parseTimes,
  progress,
  repeatText,
  setLoads,
  SHOW_WORDS_EN,
  showDoseAt,
  showLoadAt,
  type ShowWords,
} from "@/lib/structured-plan/parse";

/** Rounds generated for one AMRAP window: far more than anyone finishes. */
export const AMRAP_ROUNDS = 40;
/** Slots generated for an EMOM without a number of times ("until failure"). */
export const EMOM_OPEN_SLOTS = 60;

type ValueMeasure = Exclude<PlanMeasure, "side" | "tempo">;

/** The concrete values of one exercise in one set / round. Empty string = not set. */
export type RunValues = {
  /** Reps or quantity as shown: "12", "8–12", "400 m", "max cal in 1:00". */
  dose: string;
  /** Load as shown: "65 kg", "70%", "BW", the coach's words ("βαρύ"). */
  load: string;
  /** Other measures (pace, RPE, RIR, zone, height, distance, hold), as written or computed. */
  measures: Partial<Record<ValueMeasure, string>>;
  /** Tempo marks ("31X1"); repeats only. */
  tempo: string;
  perSide: boolean;
};

export type RunGroup = { kind: "superset" | "complex"; key: string; index: number; size: number };

/** Inner structure of one set: a cluster piece, a drop, a rest-pause mini set. */
export type RunPart =
  | { kind: "cluster"; index: number; count: number }
  | { kind: "drop"; index: number; count: number; by: string }
  | { kind: "restpause"; index: number; count: number };

export type RunWork = {
  kind: "work";
  key: string;
  rowId: string;
  name: string;
  exerciseRef: string | null;
  note: string;
  values: RunValues;
  /** 1-based set / round / slot / interval number. */
  round: number;
  /** Total sets / rounds; null when open-ended (AMRAP, EMOM until failure). */
  rounds: number | null;
  /** A set beyond the lower end of a "3-4" sets range. */
  optional: boolean;
  group: RunGroup | null;
  part: RunPart | null;
  /** Index of the block (kind of round) the row is in; -1 for interrupt rows. */
  block: number;
  /** One of the rows done at an interruption. */
  interrupt: boolean;
};

export type RunRestReason = "row" | "between_sets" | "intra" | "window" | "off";

export type RunRest = {
  kind: "rest";
  key: string;
  reason: RunRestReason;
  /** Length in seconds; null when untimed (heart-rate rest, unreadable text). */
  secs: number | null;
  /** A range ("90-120″"): shown as a range, the athlete decides when to go. */
  range: [number, number] | null;
  /** Heart-rate rest: it ends when the athlete taps "HR reached" at this bpm. */
  untilHr: number | null;
  /** What the coach typed, when it is not a readable time. */
  text: string;
  round: number;
  interrupt: boolean;
};

export type RunStep = RunWork | RunRest;

/** A stretch of the flow's clock: an EMOM slot, an interval, an AMRAP window, a rest between them. */
export type RunPhase = {
  key: string;
  kind: "work" | "rest";
  /** Length in seconds; null = it ends when its steps are done (or the athlete moves on). */
  secs: number | null;
  /** Slot / interval / window number (1-based), null for a whole-section phase. */
  round: number | null;
  steps: RunStep[];
};

export type RunClock = "none" | "up" | "down";

export type RunSequence = {
  flow: PlanFlow;
  /** "up": For Time (with `capSecs`); "down": AMRAP, EMOM, intervals, rest (per phase); "none": sets. */
  clock: RunClock;
  capSecs: number | null;
  phases: RunPhase[];
  /** Every `everySecs` of the clock, stop for `steps`, then resume where you left off. */
  interrupt: { everySecs: number; steps: RunStep[] } | null;
  /** Rounds have no written end (AMRAP; EMOM without a number of times). */
  open: boolean;
};

// ── params ────────────────────────────────────────────────────────────────

const count = (text: string | undefined): number | null => {
  const v = (text ?? "").trim();
  return /^\d+$/.test(v) && +v > 0 ? +v : null;
};

const secsOf = (text: string | undefined, dflt: "min" | "smart"): number | null => {
  const v = parseClock(text ?? "", dflt);
  return typeof v === "number" && v > 0 ? v : null;
};

/** A rest as written: one time, a range ("90-120″") or text it cannot read. */
function restOf(text: string): Pick<RunRest, "secs" | "range" | "text"> {
  const t = parseTimes(text, "smart");
  if (t && t !== "bad") {
    if (t.range) return { secs: null, range: [t.secs[0], t.secs[1]], text };
    if (t.secs.length === 1) return { secs: t.secs[0], range: null, text };
  }
  return { secs: null, range: null, text: text.trim() };
}

// ── values per column ─────────────────────────────────────────────────────

const CLOCK_MEASURES = new Set<PlanMeasure>(["pace", "hold"]);
const VALUE_MEASURES: ValueMeasure[] = ["pace", "rpe", "rir", "zone", "height", "dist", "hold"];

function prettyDose(text: string, words: ShowWords): string {
  const t = text.trim();
  if (!t) return "";
  const d = parseDose(t);
  return d && d !== "bad" ? showDoseAt(d, 0, words) || t : t;
}

/**
 * The values of `row` in column `col` of `n` (the row's own set / round
 * columns). Rows with per-set cells (flow `sets`, or `perRound`) resolve
 * their cells; other rows repeat their one dose / load, where a dose with
 * several values ("21-15-9", "1-2-3…") is per round.
 */
export function rowValues(
  row: PlanRow,
  col: number,
  n: number,
  usesCells: boolean,
  words: ShowWords = SHOW_WORDS_EN,
): RunValues {
  const extra = row.extra ?? [];
  const measures: RunValues["measures"] = {};
  const cells = usesCells && row.cells.length > 0;
  const width = Math.max(n, col + 1);
  let dose: string;
  let load: string;
  let tempo = "";
  if (cells) {
    dose = prettyDose(progress(row, "d", width)[col] ?? "", words);
    load = row.kind === "ex" ? (setLoads(row, width).values[col] ?? "") : "";
    for (const k of extra) {
      if (k === "side") continue;
      if (k === "tempo") tempo = repeatText(row, "tempo", width)[col] ?? "";
      else measures[k] = progress(row, k, width, CLOCK_MEASURES.has(k))[col] ?? "";
    }
  } else {
    const d = parseDose(row.dose);
    dose = d && d !== "bad" ? showDoseAt(d, col, words) : row.dose.trim();
    const l = parseLoad(row.load);
    load = l ? showLoadAt(l, col, words) : "";
    tempo = row.x?.tempo?.trim() ?? "";
    for (const k of VALUE_MEASURES) {
      const v = row.x?.[k]?.trim();
      if (v && extra.includes(k)) measures[k] = v;
    }
  }
  // "per side" is a flag of the row (Alt+P), or written into the dose ("8/side", "ανά πλευρά").
  const doseText = cells ? (row.cells[0]?.d ?? "") : row.dose;
  const parsed = parseDose(doseText);
  const perSide = extra.includes("side") || Boolean(parsed && parsed !== "bad" && parsed.perSide);
  return { dose, load, measures, tempo, perSide };
}

/** The number of rounds a dose with several values implies ("21-15-9" → 3), 1 otherwise. */
function rowsRoundHint(rows: PlanRow[]): number {
  let most = 1;
  for (const row of rows) {
    if (row.perRound) continue;
    const d = parseDose(row.dose);
    if (d && d !== "bad" && d.entries && !d.cont && !d.sets) most = Math.max(most, d.entries.length);
  }
  return most;
}

// ── builder ───────────────────────────────────────────────────────────────

type Ctx = {
  section: PlanSection;
  words: ShowWords;
  next: (prefix?: string) => string;
};

function makeCtx(section: PlanSection, words: ShowWords): Ctx {
  let i = 0;
  return { section, words, next: (prefix = "s") => `${prefix}${i++}` };
}

type Column = { round: number; rounds: number | null; col: number; n: number; block: number; optional?: boolean; interrupt?: boolean };

function restRowStep(ctx: Ctx, row: PlanRow, c: Column, usesCells: boolean): RunRest {
  const text = rowValues(row, c.col, c.n, usesCells, ctx.words).dose || row.dose;
  return {
    kind: "rest",
    key: ctx.next(c.interrupt ? "i" : "s"),
    reason: "row",
    ...restOf(text),
    untilHr: null,
    round: c.round,
    interrupt: Boolean(c.interrupt),
  };
}

function workStep(
  ctx: Ctx,
  row: PlanRow,
  c: Column,
  usesCells: boolean,
  group: RunGroup | null,
  part: RunPart | null,
): RunWork {
  return {
    kind: "work",
    key: ctx.next(c.interrupt ? "i" : "s"),
    rowId: row.id,
    name: row.name,
    exerciseRef: row.exerciseRef ?? null,
    note: row.note ?? "",
    values: rowValues(row, c.col, c.n, usesCells, ctx.words),
    round: c.round,
    rounds: c.rounds,
    block: c.block,
    optional: Boolean(c.optional),
    group,
    part,
    interrupt: Boolean(c.interrupt),
  };
}

const intraRest = (ctx: Ctx, text: string, c: Column): RunRest => ({
  kind: "rest",
  key: ctx.next(c.interrupt ? "i" : "s"),
  reason: "intra",
  ...restOf(text),
  untilHr: null,
  round: c.round,
  interrupt: Boolean(c.interrupt),
});

/** One unit (an exercise or a group) in one set / round, with its inner structure. */
function unitSteps(ctx: Ctx, u: PlanUnit, c: Column): RunStep[] {
  const usesCells = (row: PlanRow) => rowUsesCells(ctx.section, row);
  const st = structOf(ctx.section, u);
  if (u.rows.length > 1) {
    const kind = st.kind === "complex" ? "complex" : "superset";
    const key = unitKey(u);
    const size = u.rows.filter((r) => r.kind === "ex").length;
    let index = 0;
    return u.rows.map((row) =>
      row.kind === "rest"
        ? restRowStep(ctx, row, c, usesCells(row))
        : workStep(ctx, row, c, usesCells(row), { kind, key, index: index++, size }, null),
    );
  }
  const row = u.rows[0];
  if (row.kind === "rest") return [restRowStep(ctx, row, c, usesCells(row))];
  const cells = usesCells(row);
  const steps: RunStep[] = [];
  if (st.kind === "cluster" || st.kind === "restpause") {
    const parts = count(st.kind === "cluster" ? st.clusters : st.minis) ?? 1;
    for (let i = 0; i < parts; i++) {
      if (i > 0 && st.intra.trim()) steps.push(intraRest(ctx, st.intra, c));
      steps.push(workStep(ctx, row, c, cells, null, { kind: st.kind, index: i, count: parts }));
    }
    return steps;
  }
  if (st.kind === "drop") {
    const parts = (count(st.drops) ?? 1) + 1;
    for (let i = 0; i < parts; i++) {
      steps.push(workStep(ctx, row, c, cells, null, { kind: "drop", index: i, count: parts, by: st.dropby.trim() }));
    }
    return steps;
  }
  return [workStep(ctx, row, c, cells, null, null)];
}

/** Column of round `round` (1-based) in block `b` of `k`, and how many columns that block has. */
function columnOf(round: number, k: number, total: number): { block: number; col: number; n: number } {
  const block = (round - 1) % k;
  const col = Math.floor((round - 1) / k);
  const n = total <= block ? 1 : Math.floor((total - 1 - block) / k) + 1;
  return { block, col, n };
}

/** Every unit of round `round`, in order. */
function roundSteps(ctx: Ctx, round: number, total: number, rounds: number | null, extra: Partial<Column> = {}): RunStep[] {
  const blocks = ctx.section.blocks.length ? ctx.section.blocks : [[]];
  const { block, col, n } = columnOf(round, blocks.length, total);
  const c: Column = { round, rounds, col, n, block, ...extra };
  return unitsOf(blocks[block] ?? []).flatMap((u) => unitSteps(ctx, u, c));
}

function betweenSets(ctx: Ctx, round: number): RunRest | null {
  const text = ctx.section.params.rest?.trim();
  if (!text) return null;
  return { kind: "rest", key: ctx.next(), reason: "between_sets", ...restOf(text), untilHr: null, round, interrupt: false };
}

function setsPhases(ctx: Ctx): RunPhase[] {
  const { section } = ctx;
  const { min, max } = setsRange(section);
  const steps: RunStep[] = [];
  const push = (s: RunStep | null) => {
    if (s) steps.push(s);
  };
  if (section.blocks.length <= 1) {
    // Straight sets: each unit (an exercise, or a superset done set-wise) does all its sets, then the next.
    const dropTrailingRest = () => {
      const last = steps[steps.length - 1];
      if (last?.kind === "rest" && last.reason === "between_sets") steps.pop();
    };
    for (const u of unitsOf(section.blocks[0] ?? [])) {
      if (u.rows.every((r) => r.kind === "rest")) {
        // A rest row between exercises happens once, in place of the rest between sets.
        dropTrailingRest();
        steps.push(...unitSteps(ctx, u, { round: 1, rounds: max, col: 0, n: 1, block: 0 }));
        continue;
      }
      for (let set = 1; set <= max; set++) {
        steps.push(...unitSteps(ctx, u, { round: set, rounds: max, col: set - 1, n: max, block: 0, optional: set > min }));
        push(betweenSets(ctx, set));
      }
    }
    dropTrailingRest();
  } else {
    // Different sets alternate: set 1 = block 1, set 2 = block 2, …
    for (let set = 1; set <= max; set++) {
      steps.push(...roundSteps(ctx, set, max, max, { optional: set > min }));
      if (set < max) push(betweenSets(ctx, set));
    }
  }
  return [{ key: "p0", kind: "work", secs: null, round: null, steps }];
}

function forTimePhases(ctx: Ctx, capSecs: number | null): RunPhase[] {
  const rounds = Math.max(count(ctx.section.params.rounds) ?? 1, rowsRoundHint(ctx.section.blocks.flat()));
  const steps: RunStep[] = [];
  for (let r = 1; r <= rounds; r++) steps.push(...roundSteps(ctx, r, rounds, rounds));
  return [{ key: "p0", kind: "work", secs: capSecs, round: null, steps }];
}

function amrapPhases(ctx: Ctx): RunPhase[] {
  const windows = parseTimes(ctx.section.params.dur ?? "", "min");
  const secs: (number | null)[] = windows && windows !== "bad" && !windows.range ? windows.secs : [null];
  const rest = secsOf(ctx.section.params.rest, "smart");
  const phases: RunPhase[] = [];
  secs.forEach((len, w) => {
    if (w > 0 && rest) {
      phases.push({
        key: `p${phases.length}`,
        kind: "rest",
        secs: rest,
        round: w,
        steps: [{ kind: "rest", key: ctx.next(), reason: "window", secs: rest, range: null, untilHr: null, text: "", round: w, interrupt: false }],
      });
    }
    const steps: RunStep[] = [];
    for (let r = 1; r <= AMRAP_ROUNDS; r++) steps.push(...roundSteps(ctx, r, AMRAP_ROUNDS, null));
    phases.push({ key: `p${phases.length}`, kind: "work", secs: len, round: secs.length > 1 ? w + 1 : null, steps });
  });
  return phases;
}

function emomPhases(ctx: Ctx): RunPhase[] {
  const every = secsOf(ctx.section.params.every, "smart") ?? 60;
  const times = count(ctx.section.params.times);
  const total = times ?? EMOM_OPEN_SLOTS;
  const phases: RunPhase[] = [];
  for (let r = 1; r <= total; r++) {
    phases.push({ key: `p${r - 1}`, kind: "work", secs: every, round: r, steps: roundSteps(ctx, r, total, times) });
  }
  return phases;
}

function intervalPhases(ctx: Ctx): RunPhase[] {
  const { params, mods } = ctx.section;
  const work = secsOf(params.work, "smart");
  const off = secsOf(params.off, "smart");
  const hr = mods?.hr ? count(params.hrTarget) : null;
  const rounds = count(params.rounds) ?? 1;
  const phases: RunPhase[] = [];
  for (let r = 1; r <= rounds; r++) {
    phases.push({ key: `p${phases.length}`, kind: "work", secs: work, round: r, steps: roundSteps(ctx, r, rounds, rounds) });
    if (r === rounds) break;
    if (mods?.hr) {
      phases.push({
        key: `p${phases.length}`,
        kind: "rest",
        secs: null,
        round: r,
        steps: [{ kind: "rest", key: ctx.next(), reason: "off", secs: null, range: null, untilHr: hr, text: "", round: r, interrupt: false }],
      });
    } else if (off) {
      phases.push({
        key: `p${phases.length}`,
        kind: "rest",
        secs: off,
        round: r,
        steps: [{ kind: "rest", key: ctx.next(), reason: "off", secs: off, range: null, untilHr: null, text: "", round: r, interrupt: false }],
      });
    }
  }
  return phases;
}

function interruptOf(ctx: Ctx): RunSequence["interrupt"] {
  const { section } = ctx;
  if (!section.mods?.interrupt) return null;
  const everySecs = secsOf(section.params.intEvery, "smart");
  const rows = section.interrupt ?? [];
  if (!everySecs || !rows.some((r) => r.kind === "ex" && r.name.trim())) return null;
  const c: Column = { round: 1, rounds: null, col: 0, n: 1, block: -1, interrupt: true };
  return { everySecs, steps: unitsOf(rows).flatMap((u) => unitSteps(ctx, u, c)) };
}

/** Builds the run sequence of one plan section. */
export function buildSequence(section: PlanSection, words: ShowWords = SHOW_WORDS_EN): RunSequence {
  const ctx = makeCtx(section, words);
  const interrupt = interruptOf(ctx);
  switch (section.flow) {
    case "sets":
      return { flow: "sets", clock: "none", capSecs: null, phases: setsPhases(ctx), interrupt, open: false };
    case "for_time": {
      const capSecs = secsOf(section.params.cap, "min");
      return { flow: "for_time", clock: "up", capSecs, phases: forTimePhases(ctx, capSecs), interrupt, open: false };
    }
    case "amrap":
      return { flow: "amrap", clock: "down", capSecs: null, phases: amrapPhases(ctx), interrupt, open: true };
    case "emom":
      return { flow: "emom", clock: "down", capSecs: null, phases: emomPhases(ctx), interrupt: null, open: !count(section.params.times) };
    case "intervals":
      return { flow: "intervals", clock: "down", capSecs: null, phases: intervalPhases(ctx), interrupt: null, open: false };
    case "rest": {
      const secs = secsOf(section.params.dur, "smart");
      const step: RunRest = { kind: "rest", key: ctx.next(), reason: "row", secs, range: null, untilHr: null, text: section.params.dur ?? "", round: 1, interrupt: false };
      return { flow: "rest", clock: "down", capSecs: null, phases: [{ key: "p0", kind: "rest", secs, round: null, steps: [step] }], interrupt: null, open: false };
    }
  }
}

/** Every step of a sequence in order (interrupt rows excluded). */
export const allSteps = (seq: RunSequence): RunStep[] => seq.phases.flatMap((p) => p.steps);
