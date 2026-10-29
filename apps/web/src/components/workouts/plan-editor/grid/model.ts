/**
 * ADR-270: what the grid shows for each value, worked out from the plan
 * alone (no DOM): inherited placeholders, computed values with their badge
 * (`65` + `+5`), errors, column labels and units, per-round summaries, and
 * what the hint line says for the focused field. Messages are returned as
 * `PlanGrid` i18n keys with values, so this stays pure and testable.
 */
import type { PlanCell, PlanMeasure, PlanRow, PlanSection } from "@/lib/structured-plan/types";

import { MEASURES, measureUnit as libMeasureUnit, parseClock, parseDose, parseTempo, progress, repeatDose, repeatText, setLoads, type Dose } from "./lib";

export type Msg = { key: string; values?: Record<string, string | number> };
export type MeasureKey = Exclude<PlanMeasure, "side">;
/** A value column: reps / quantity, load, or a measure. */
export type ColKey = "d" | "l" | MeasureKey;

export type FieldView = {
  /** Shown greyed when the field is empty: the inherited value. */
  placeholder: string;
  /** Computed value drawn inside the field while it is not focused. */
  display: string;
  /** Tiny badge next to the display (the rule the coach typed: `+5`, `60→80`). */
  badge: string;
  error: Msg | null;
  /** Unit right next to the typed value; empty when the value or the label says it. */
  suffix: string;
};

const EMPTY = "—";

export const isFlag = (k: PlanMeasure) => Boolean(MEASURES[k].flag);
export const valueMeasures = (row: PlanRow): MeasureKey[] => (row.extra ?? []).filter((k): k is MeasureKey => !isFlag(k));
export const flagMeasures = (row: PlanRow): PlanMeasure[] => (row.extra ?? []).filter(isFlag);

/** The lines of one row's set / round cell, in label order. */
export const lineKeys = (row: PlanRow): ColKey[] => (row.kind === "rest" ? ["d"] : ["d", "l", ...valueMeasures(row)]);

/** The columns of a non-Σετ table: reps, load, then every measure any row added. */
export const tableColumns = (rows: PlanRow[]): ColKey[] => ["d", "l", ...new Set(rows.flatMap(valueMeasures))];

const isRelative = (t: string) => /^[+-]|→|->|ως|έως/.test(t.trim());
const bare = (x: string | undefined) => (x ?? "").replace(/\s*(kg|%)$/i, "");
const arrow = (t: string) => t.replace("->", "→");

/** Unit token of a measure's header or suffix ("/10", "cm", "sec"…); `sec` is translated by the UI. */
export function measureUnit(k: MeasureKey, value?: string): string {
  return libMeasureUnit(k, value ?? "");
}

/** Bare reps in a rest row: up to 10 reads as minutes, above as seconds. */
export function restSuffix(v: string): "" | "min" | "sec" {
  const t = v.trim();
  if (!t || /[:s″"′'λδ]|min/.test(t)) return "";
  return Number(t) <= 10 ? "min" : "sec";
}

function doseSuffix(v: string): string {
  const d = parseDose(v);
  if (!d || d === "bad" || d.unit === "reps") return "";
  const says = (re: RegExp) => re.test(v.toLowerCase());
  if (d.unit === "kcal") return says(/cal|θερμ/) ? "" : "cal";
  if (d.unit === "m") return says(/m/) ? "" : "m";
  return "";
}

const doseError = (v: string): Msg | null => (v.trim() && parseDose(v) === "bad" ? { key: "error.dose" } : null);

function measureError(k: MeasureKey, t: string, inCell: boolean): Msg | null {
  if (!t) return null;
  const M = MEASURES[k];
  if (M.text) return parseTempo(t) ? null : { key: "error.tempo" };
  if (!(inCell ? /^[+-]?\d/ : /^\d/).test(t)) return { key: inCell ? "error.number" : "error.numberExample", values: { example: M.ph } };
  if (M.max && /^\d+(\.\d+)?$/.test(t) && Number(t) > M.max) return { key: "error.max", values: { max: M.max } };
  return null;
}

// ── same-for-every-round values (flows other than Σετ) ──────────────────────

/** One field of a row that has the same value every round. */
export function compactField(row: PlanRow, k: ColKey): FieldView {
  const view: FieldView = { placeholder: EMPTY, display: "", badge: "", error: null, suffix: "" };
  if (k === "d") {
    view.error = row.kind === "rest" ? null : doseError(row.dose);
    view.suffix = row.kind === "rest" ? restSuffix(row.dose) : doseSuffix(row.dose);
    if (row.kind === "rest") view.placeholder = "0:30";
    return view;
  }
  if (k === "l") {
    const t = row.load.trim();
    if (/^\d+(?:[.,]\d+)?$/.test(t)) view.error = { key: "error.loadUnitCompact" };
    return view;
  }
  const t = (row.x?.[k] ?? "").trim();
  view.error = measureError(k, t, false);
  view.suffix = t && !view.error ? measureUnit(k, t) : "";
  return view;
}

// ── per set / per round values ─────────────────────────────────────────────

export type RowCells = {
  /** views[k][column] */
  views: Partial<Record<ColKey, FieldView[]>>;
  /** Unit the row's loads are in, from whichever column states it. */
  loadUnit: "kg" | "%" | null;
};

/** Every field of a row's `n` set / round columns. */
export function rowCells(row: PlanRow, n: number): RowCells {
  const cells = row.cells;
  const views: RowCells["views"] = {};
  const doses = repeatDose(cells, n);
  views.d = Array.from({ length: n }, (_, j) => {
    const v = cells[j]?.d ?? "";
    return {
      placeholder: (!v && j ? doses[j - 1] : "") || EMPTY,
      display: "",
      badge: "",
      error: row.kind === "rest" ? null : doseError(v),
      suffix: row.kind === "rest" ? restSuffix(v) : "",
    };
  });
  if (row.kind !== "ex") return { views, loadUnit: null };
  const loads = setLoads(cells, n);
  views.l = Array.from({ length: n }, (_, j) => {
    const t = (cells[j]?.l ?? "").trim();
    const err = loads.errors[j];
    const shown = bare(loads.values[j]);
    return {
      placeholder: shown || EMPTY,
      display: t && !err && shown && shown !== t ? shown : "",
      badge: t && !err && isRelative(t) ? bare(arrow(t)) : "",
      error: err === "missing_unit" ? { key: "error.loadMissingUnit" } : err === "mixed_unit" ? { key: "error.loadMixedUnits", values: { unit: loads.unit ?? "" } } : null,
      suffix: "",
    };
  });
  for (const k of valueMeasures(row)) {
    const M = MEASURES[k];
    const vals = (M.text ? repeatText(cells, k, n) : progress(cells, k, n, M.clock)).map((x) => (M.max && Number(x) > M.max ? String(M.max) : x));
    views[k] = Array.from({ length: n }, (_, j) => {
      const t = (cells[j]?.[k] ?? "").trim();
      const error = measureError(k, t, true);
      return {
        placeholder: vals[j] || EMPTY,
        display: t && !error && !M.text && vals[j] && vals[j] !== t ? vals[j]! : "",
        badge: t && !error && !M.text && isRelative(t) ? arrow(t) : "",
        error,
        suffix: "",
      };
    });
  }
  return { views, loadUnit: loads.unit };
}

/** "5 → 15", "40 kg → 60 kg": what a per-round row shows in its own columns. */
export function perSummary(row: PlanRow, k: ColKey, n: number): string {
  const cells = row.cells;
  const vals =
    k === "d"
      ? repeatDose(cells, n)
      : k === "l"
        ? setLoads(cells, n).values
        : MEASURES[k].text
          ? repeatText(cells, k, n)
          : progress(cells, k, n, MEASURES[k].clock);
  const xs = vals.filter(Boolean);
  if (!xs.length) return "";
  return xs.every((x) => x === xs[0]) ? xs[0]! : `${xs[0]} → ${xs.at(-1)}`;
}

// ── block labels ───────────────────────────────────────────────────────────

/** The word for one column: Σετ, Γύρος or Διάστημα (`PlanGrid.round.*`). */
export const roundWordKey = (plan: PlanSection) =>
  plan.flow === "sets" ? "set" : plan.flow === "emom" || plan.flow === "intervals" ? "slot" : "round";

/**
 * A block's title: which rounds it runs in ("Γύρος 1, 3, …"), or, with a
 * single block, how the flow repeats it.
 */
export function blockTitle(plan: PlanSection, b: number, list: number[], open: boolean, total: number): Msg {
  const k = plan.blocks.length;
  const word = roundWordKey(plan);
  if (k <= 1) {
    if (plan.flow === "sets") return { key: "head.exercise" };
    if (plan.flow === "amrap") return { key: "head.amrap" };
    if (plan.flow === "emom") {
      const e = parseClock(plan.params.every ?? "", "smart");
      return typeof e === "number" && e > 0 ? { key: "head.emomEvery", values: { every: clock(e) } } : { key: "head.emom" };
    }
    if (plan.flow === "intervals") return { key: "head.intervals", values: { work: plan.params.work ?? "" } };
    return total > 1 ? { key: "head.rounds", values: { rounds: plan.params.rounds ?? String(total) } } : { key: "head.once" };
  }
  if (k >= total && list.length === 1) return { key: `round.${word}`, values: { list: String(list[0]) } };
  const more = open || list.length > 3;
  if (plan.flow === "emom") {
    const e = parseClock(plan.params.every ?? "", "smart");
    if (e === 60) return { key: "round.minute", values: { list: list.slice(0, 3).join(", ") + (more ? ", …" : "") } };
    if (typeof e === "number" && e > 0)
      return {
        key: "round.slotAt",
        values: { list: list.slice(0, 2).join(", ") + ", …", at: list.slice(0, 2).map((x) => mmss(e * (x - 1))).join(", ") + ", …" },
      };
  }
  return { key: `round.${word}`, values: { list: list.slice(0, 3).join(", ") + (more ? ", …" : "") } };
}

export const clock = (s: number) => (s >= 60 ? mmss(s) : `${s}″`);
const mmss = (s: number) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;

// ── hint line ──────────────────────────────────────────────────────────────

/** A field the grid knows: `r:<row>:name|dose|load|note|x:<k>` or `c:<row>:<col>:<k>`. */
export type FieldKey =
  | { kind: "row"; rowId: string; field: "name" | "dose" | "load" | "note" }
  | { kind: "x"; rowId: string; k: MeasureKey }
  | { kind: "cell"; rowId: string; col: number; k: ColKey };

export function parseFieldKey(key: string | undefined | null): FieldKey | null {
  if (!key) return null;
  let m = /^r:([^:]+):(name|dose|load|note)$/.exec(key);
  if (m) return { kind: "row", rowId: m[1]!, field: m[2] as "name" };
  m = /^r:([^:]+):x:(\w+)$/.exec(key);
  if (m) return { kind: "x", rowId: m[1]!, k: m[2] as MeasureKey };
  m = /^c:([^:]+):(\d+):(\w+)$/.exec(key);
  if (m) return { kind: "cell", rowId: m[1]!, col: Number(m[2]), k: m[3] as ColKey };
  return null;
}

export const fieldKey = {
  name: (rowId: string) => `r:${rowId}:name`,
  dose: (rowId: string) => `r:${rowId}:dose`,
  load: (rowId: string) => `r:${rowId}:load`,
  note: (rowId: string) => `r:${rowId}:note`,
  x: (rowId: string, k: MeasureKey) => `r:${rowId}:x:${k}`,
  cell: (rowId: string, col: number, k: ColKey) => `c:${rowId}:${col}:${k}`,
  /** A structure field (clusters, intra…) of a unit. */
  struct: (unitKey: string, field: string) => `s:${unitKey}:${field}`,
};

/** The test id of a value field: column `same` for same-every-round values, else the 0-based set / round. */
export function cellTestId(key: FieldKey): string | undefined {
  if (key.kind === "cell") return `plan-cell-${key.rowId}-${key.col}-${key.k}`;
  if (key.kind === "x") return `plan-cell-${key.rowId}-same-${key.k}`;
  if (key.field === "dose") return `plan-cell-${key.rowId}-same-d`;
  if (key.field === "load") return `plan-cell-${key.rowId}-same-l`;
  return undefined;
}

export type Tip = [code: string, meaningKey: string];
export type Hint = { meaning: Msg | null; error: boolean; tips: Tip[] };

const TIPS: Record<string, Tip[]> = {
  d: [["8-12", "tip.range"], ["5-10-15…", "tip.ladder"], ["max", "tip.max"]],
  dc: [["tip.emptyCode", "tip.asBefore"], ["8-12", "tip.range"], ["max", "tip.max"]],
  l: [["60kg", "tip.kg"], ["70%", "tip.pct"], ["tip.heavyCode", "tip.words"]],
  lc: [["tip.emptyCode", "tip.asBefore"], ["+5", "tip.plusEach"], ["60→80", "tip.spread"], ["tip.unitCode", "tip.unitOnce"]],
  x: [["tip.emptyCode", "tip.asBefore"], ["+1", "tip.changeEach"], ["7→9", "tip.spread"]],
  clock: [["tip.emptyCode", "tip.asBefore"], ["-0:05", "tip.changeEach"], ["2:00→1:50", "tip.spread"]],
  tempo: [["31X1", "tip.tempo"]],
  rest: [["30″", "tip.seconds"], ["1:30", "tip.minSec"], ["2", "tip.minutes"]],
};
const AMRAP_TIP: Tip = ["tip.afterLastCode", "tip.afterLast"];

function doseMeaning(d: Dose, roundWord: string): Msg | null {
  if (d.max) return { key: d.unit === "kcal" ? "mean.maxCal" : d.unit === "m" ? "mean.maxM" : "mean.max" };
  if (!d.entries) return d.sets ? { key: "mean.sets", values: { sets: d.sets.min === d.sets.max ? String(d.sets.min) : `${d.sets.min}–${d.sets.max}` } } : null;
  const show = (e: { min: number; max: number }) => (e.min === e.max ? showOne(e.min, d.unit) : `${showOne(e.min, d.unit)}–${showOne(e.max, d.unit)}`);
  if (d.entries.length > 1) {
    const list = d.entries.map(show).join(" · ");
    if (d.cont) {
      const es = d.entries;
      const step = es.at(-1)!.min - es.at(-2)!.min;
      return { key: "mean.ladder", values: { list, step: `${step > 0 ? "+" : ""}${step}`, word: roundWord } };
    }
    return { key: "mean.perRound", values: { list, word: roundWord } };
  }
  const e = d.entries[0]!;
  const side = d.perSide ? "Side" : "";
  if (e.min !== e.max) return { key: `mean.range${side}`, values: { range: show(e) } };
  return { key: d.unit === "reps" ? `mean.reps${side}` : `mean.amount${side}`, values: { value: show(e) } };
}

function showOne(n: number, unit: Dose["unit"]) {
  const num = String(Math.round(n * 100) / 100);
  if (unit === "secs") return clock(n);
  if (unit === "kcal") return `${num} cal`;
  if (unit === "m") return n >= 1000 && n % 100 === 0 ? `${n / 1000} km` : `${num} m`;
  return num;
}

function loadMeaning(v: string): Msg | null {
  const t = v.trim().toLowerCase();
  if (!t) return null;
  if (["bw", "σβ", "bodyweight"].includes(t)) return { key: "mean.bw" };
  const m = /^(\d+(?:[.,]\d+)?)\s*(kg|κιλά|κιλα|%)$/.exec(t);
  if (m) return { key: m[2] === "%" ? "mean.pct" : "mean.kg", values: { value: m[1]!.replace(",", ".") } };
  if (/^\d+(?:[.,]\d+)?$/.test(t)) return null;
  return { key: "mean.words" };
}

/** What the hint line says while `key` is focused. */
export function hintFor(plan: PlanSection, key: FieldKey | null, roundWord: string): Hint {
  const none: Hint = { meaning: null, error: false, tips: [] };
  if (!key || (key.kind === "row" && (key.field === "name" || key.field === "note"))) return none;
  const at = findAnyRow(plan, key.rowId);
  if (!at) return none;
  const row = at.row;
  if (key.kind === "cell") {
    const n = Math.max(key.col + 1, row.cells.length);
    const view = rowCells(row, n).views[key.k]?.[key.col];
    const value = (row.cells[key.col]?.[key.k] ?? "").trim();
    let meaning: Msg | null = view?.error ?? null;
    if (!meaning && value) {
      if (key.k === "d") {
        const d = parseDose(value);
        meaning = d && d !== "bad" && row.kind === "ex" ? doseMeaning(d, roundWord) : null;
      } else if (key.k === "l") {
        meaning = view?.display ? { key: "mean.equals", values: { value: `${view.display}${loadUnitText(row, n)}` } } : null;
      } else if (MEASURES[key.k].text) meaning = tempoMeaning(value);
      else if (view?.display) {
        const unit = measureUnit(key.k, view.display);
        meaning = unit ? { key: "mean.equalsUnit", values: { value: view.display, unit } } : { key: "mean.equals", values: { value: view.display } };
      }
    }
    let tips =
      row.kind === "rest"
        ? TIPS.rest!
        : key.k === "d"
          ? TIPS.dc!
          : key.k === "l"
            ? TIPS.lc!
            : MEASURES[key.k].text
              ? TIPS.tempo!
              : MEASURES[key.k].clock
                ? TIPS.clock!
                : TIPS.x!;
    if (plan.flow === "amrap" && row.kind === "ex" && !MEASURES[key.k as MeasureKey]?.text) tips = [...tips.slice(0, 3), AMRAP_TIP];
    return { meaning, error: Boolean(view?.error), tips };
  }
  if (key.kind === "x") {
    const value = (row.x?.[key.k] ?? "").trim();
    const error = compactField(row, key.k).error;
    const meaning = error ?? (MEASURES[key.k].text && value ? tempoMeaning(value) : null);
    return { meaning, error: Boolean(error), tips: MEASURES[key.k].text ? TIPS.tempo! : [] };
  }
  if (key.field === "dose") {
    const view = compactField(row, "d");
    if (row.kind === "rest") return { meaning: null, error: false, tips: TIPS.rest! };
    const d = parseDose(row.dose);
    return { meaning: view.error ?? (d && d !== "bad" ? doseMeaning(d, roundWord) : null), error: Boolean(view.error), tips: TIPS.d! };
  }
  const view = compactField(row, "l");
  return { meaning: view.error ?? loadMeaning(row.load), error: Boolean(view.error), tips: TIPS.l! };
}

function loadUnitText(row: PlanRow, n: number) {
  const u = setLoads(row.cells, n).unit;
  return u === "%" ? "%" : u === "kg" ? " kg" : "";
}

function tempoMeaning(v: string): Msg | null {
  const t = parseTempo(v);
  if (!t) return null;
  return { key: "mean.tempo", values: { down: t[0], bottom: t[1], up: t[2], top: t[3] } };
}

function findAnyRow(plan: PlanSection, rowId: string) {
  for (const list of [...plan.blocks, plan.interrupt ?? []]) {
    const row = list.find((r) => r.id === rowId);
    if (row) return { row };
  }
  return null;
}

/** The value a field holds in the plan. */
export function fieldValue(row: PlanRow, key: FieldKey): string {
  if (key.kind === "cell") return (row.cells[key.col] as PlanCell | undefined)?.[key.k] ?? "";
  if (key.kind === "x") return row.x?.[key.k] ?? "";
  return (row[key.field] as string | undefined) ?? "";
}

/** A value for a quoted CSS attribute selector (jsdom has no CSS.escape). */
export const attr = (value: string) => value.replace(/["\\]/g, "\\$&");
