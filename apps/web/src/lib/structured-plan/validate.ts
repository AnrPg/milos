/**
 * ADR-270: the rules a saved section must meet. The API
 * (`Palee.Workouts.Domain.StructuredPlan`) enforces the same rules with the
 * same codes and paths, so the editor can show exactly what the server
 * would refuse. `validateSection` accepts any JSON value and never throws:
 * a wrong shape is reported as `bad_shape` and read as empty.
 *
 * Paths are dot-separated keys and indexes from the section root:
 * `params.rest`, `blocks.0.2.cells.1.l`, `blocks.1.0.x.tempo`,
 * `interrupt.0.dose`, `structs.<key>.intra`.
 */
import { FLOWS, MEASURES, MODS, STRUCTS, paramDefs, scoresFor, type ParamDef } from "./catalog";
import {
  clock,
  clockAmbiguity,
  decimalCommaNorm,
  measureCellErrors,
  normText,
  parseClock,
  parseCount,
  parseCountRange,
  parseDose,
  parseLoad,
  parseTimes,
  setLoads,
  tempoParts,
  type Ambiguity,
  type PlanErrorCode,
} from "./parse";
import { usesCells } from "./rounds";
import { PLAN_VERSION, type PlanCell, type PlanFlow, type PlanMeasure, type PlanRow, type PlanSection } from "./types";

export type PlanIssue = { path: string; code: PlanErrorCode };

/** i18n key of an error code's message. */
export const issueKey = (code: string): string => `PlanCore.error.${code}`;

/** Size bounds (the API refuses anything larger). */
export const PLAN_LIMITS = {
  blocks: 12,
  rowsPerBlock: 60,
  cellsPerRow: 30,
  text: 200,
  note: 2000,
} as const;

/** How a parameter reads for its kind; `ambiguous` names the other reading. */
export type ParamReading =
  | { ok: false }
  | { ok: true; kind: "empty" }
  | { ok: true; kind: "secs"; secs: number; ambiguous?: Ambiguity }
  | { ok: true; kind: "secsRange"; min: number; max: number }
  | { ok: true; kind: "windows"; secs: number[]; ambiguous?: Ambiguity }
  | { ok: true; kind: "count"; n: number }
  | { ok: true; kind: "countRange"; min: number; max: number }
  | { ok: true; kind: "text"; text: string };

/**
 * Reads a typed parameter for its kind. Empty is fine (not set). A `time`
 * may be a range of two ascending durations ("90-120″"); a bare number in a
 * smart time field says how it was read. `times` (AMRAP) are windows: two
 * rising values ("12-15") are two windows, flagged as maybe meant as a range.
 */
export function readParam(def: Pick<ParamDef, "kind" | "bare">, value: unknown): ParamReading {
  if (typeof value !== "string") return { ok: false };
  if (!normText(value)) return { ok: true, kind: "empty" };
  switch (def.kind) {
    case "time": {
      const one = parseClock(value, def.bare);
      if (typeof one === "number") {
        if (one <= 0) return { ok: false };
        const amb = def.bare === "smart" ? clockAmbiguity(value, def.bare) : null;
        return amb ? { ok: true, kind: "secs", secs: one, ambiguous: amb } : { ok: true, kind: "secs", secs: one };
      }
      const range = parseTimes(value, def.bare);
      return range && range !== "bad" && range.range ? { ok: true, kind: "secsRange", min: range.secs[0], max: range.secs[1] } : { ok: false };
    }
    case "times": {
      const t = parseTimes(value, def.bare);
      if (!t || t === "bad") return { ok: false };
      if (t.range) {
        const write = clock(t.secs[0]);
        const list = t.secs.map(clock).join(" · ");
        return { ok: true, kind: "windows", secs: t.secs, ambiguous: { alt: "range", write, hint: { key: "PlanCore.ambiguous.windows", values: { count: 2, list, write } } } };
      }
      return { ok: true, kind: "windows", secs: t.secs };
    }
    case "count": {
      const n = parseCount(value);
      return n ? { ok: true, kind: "count", n } : { ok: false };
    }
    case "range": {
      const r = parseCountRange(value);
      return r ? { ok: true, kind: "countRange", ...r } : { ok: false };
    }
    case "text":
      return { ok: true, kind: "text", text: value.trim() };
  }
}

/** A typed parameter reads for its kind (see `readParam`). */
export const paramValid = (def: Pick<ParamDef, "kind" | "bare">, value: string): boolean => readParam(def, value).ok;

/**
 * A measure value: tempo has 4 marks; numeric measures start with a number
 * (a zone may say "z2"; in per-set cells also a `+x`/`-x` change); RPE is at
 * most 10.
 */
export function measureIssue(key: Exclude<PlanMeasure, "side">, value: unknown, inCell: boolean): PlanErrorCode | null {
  if (typeof value !== "string") return value == null ? null : "bad_shape";
  const t = decimalCommaNorm(value).replace(/^z(?:one)?\s*(?=\d)/, "");
  if (!t) return null;
  const M = MEASURES[key];
  if (M.text) return tempoParts(value) ? null : "bad_tempo";
  if (!(inCell ? /^[+-]?\d/ : /^\d/).test(t)) return "bad_measure_value";
  if (M.max != null && !/^[+-]/.test(t)) {
    const nums = (t.match(/\d+(?:\.\d+)?/g) || []).map(Number);
    if (nums.some((n) => n > (M.max as number))) return "rpe_over_max";
  }
  return null;
}

// ── shape helpers: read anything, report what is not the contract ─────────

type Push = (path: string, code: PlanErrorCode) => void;
const isObj = (v: unknown): v is Record<string, unknown> => Boolean(v) && typeof v === "object" && !Array.isArray(v);
const tooLong = (v: string, max: number = PLAN_LIMITS.text) => v.length > max;

/** A string field: missing / null is "", anything else not a string is `bad_shape`. */
function str(v: unknown, path: string, push: Push, max: number = PLAN_LIMITS.text, code: PlanErrorCode = "too_long"): string {
  if (v == null) return "";
  if (typeof v !== "string") {
    push(path, "bad_shape");
    return "";
  }
  if (tooLong(v, max)) push(path, code);
  return v;
}

function arr(v: unknown, path: string, push: Push): unknown[] {
  if (v == null) return [];
  if (!Array.isArray(v)) {
    push(path, "bad_shape");
    return [];
  }
  return v;
}

function obj(v: unknown, path: string, push: Push): Record<string, unknown> {
  if (v == null) return {};
  if (!isObj(v)) {
    push(path, "bad_shape");
    return {};
  }
  return v;
}

const MEASURE_KEYS = new Set(Object.keys(MEASURES));
const CELL_KEYS = new Set(["d", "l", ...Object.keys(MEASURES).filter((k) => k !== "side")]);

/** A row read into the contract's shape (junk dropped, reported). */
function readRow(raw: unknown, path: string, push: Push): PlanRow | null {
  if (!isObj(raw)) {
    push(path, "bad_shape");
    return null;
  }
  const at = (p: string) => `${path}.${p}`;
  const id = typeof raw.id === "string" && raw.id.trim() ? raw.id : "";
  if (!id) push(at("id"), "bad_shape");
  else if (tooLong(id)) push(at("id"), "too_long");
  const kind = raw.kind === "ex" || raw.kind === "rest" ? raw.kind : null;
  if (!kind) push(at("kind"), "bad_row_kind");
  const cellsRaw = arr(raw.cells, at("cells"), push);
  if (cellsRaw.length > PLAN_LIMITS.cellsPerRow) push(at("cells"), "too_many_cells");
  const cells: PlanCell[] = cellsRaw.slice(0, PLAN_LIMITS.cellsPerRow).map((c, j) => {
    if (c == null) return {};
    if (!isObj(c)) {
      push(at(`cells.${j}`), "bad_shape");
      return {};
    }
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(c)) {
      if (!CELL_KEYS.has(k)) {
        push(at(`cells.${j}.${k}`), "bad_shape");
        continue;
      }
      out[k] = str(v, at(`cells.${j}.${k}`), push);
    }
    return out as PlanCell;
  });
  const xRaw = obj(raw.x, at("x"), push);
  const x: Record<string, string> = {};
  for (const [k, v] of Object.entries(xRaw)) {
    if (!CELL_KEYS.has(k) || k === "d" || k === "l") push(at(`x.${k}`), "bad_shape");
    else x[k] = str(v, at(`x.${k}`), push);
  }
  const extra: PlanMeasure[] = [];
  const seen = new Set<string>();
  arr(raw.extra, at("extra"), push).forEach((k, i) => {
    if (typeof k !== "string" || !MEASURE_KEYS.has(k)) push(at(`extra.${i}`), "unknown_measure");
    else if (seen.has(k)) push(at(`extra.${i}`), "duplicate_measure");
    else extra.push(k as PlanMeasure);
    if (typeof k === "string") seen.add(k);
  });
  if (raw.perRound != null && typeof raw.perRound !== "boolean") push(at("perRound"), "bad_shape");
  if (raw.group != null && typeof raw.group !== "string") push(at("group"), "bad_shape");
  return {
    id,
    kind: kind ?? "ex",
    name: str(raw.name, at("name"), push),
    exerciseRef: str(raw.exerciseRef, at("exerciseRef"), push) || null,
    dose: str(raw.dose, at("dose"), push),
    load: str(raw.load, at("load"), push),
    x,
    extra,
    cells,
    perRound: raw.perRound === true,
    group: typeof raw.group === "string" ? raw.group : null,
    note: str(raw.note, at("note"), push, PLAN_LIMITS.note, "note_too_long"),
  };
}

function validateRow(flow: PlanFlow, row: PlanRow, path: string, inInterrupt: boolean, push: Push) {
  const at = (p: string) => `${path}.${p}`;
  const measures = (row.extra || []).filter((k) => !MEASURES[k].flag) as Exclude<PlanMeasure, "side">[];
  const cellMode = !inInterrupt && usesCells({ flow }, row);
  if (cellMode) {
    const n = row.cells.length;
    const loads = row.kind === "ex" ? setLoads(row, n) : null;
    const measureErrors = Object.fromEntries(measures.map((k) => [k, measureCellErrors(row, k, n, Boolean(MEASURES[k].clock))]));
    row.cells.forEach((c, j) => {
      if (c.d && parseDose(c.d) === "bad") push(at(`cells.${j}.d`), "bad_dose");
      const le = loads?.errors[j];
      if (le) push(at(`cells.${j}.l`), le);
      for (const k of measures) {
        const code = measureIssue(k, c[k] || "", true) ?? (MEASURES[k].text ? null : measureErrors[k][j]);
        if (code) push(at(`cells.${j}.${k}`), code);
      }
    });
  } else {
    if (row.dose && parseDose(row.dose) === "bad") push(at("dose"), "bad_dose");
    if (row.kind === "ex") {
      const l = parseLoad(row.load);
      if (l?.kind === "wrong") push(at("load"), "wrong_unit");
      else if (/^\d+(?:\.\d+)?$/.test(decimalCommaNorm(row.load))) push(at("load"), "missing_unit");
    }
    for (const k of measures) {
      const code = measureIssue(k, row.x?.[k] || "", false);
      if (code) push(at(`x.${k}`), code);
    }
  }
}

/**
 * Every problem of a section, as `{ path, code }`. Empty list = valid.
 * Accepts any value (API JSON); never throws.
 */
export function validateSection(input: PlanSection | unknown): PlanIssue[] {
  const out: PlanIssue[] = [];
  const push: Push = (path, code) => out.push({ path, code });
  if (!isObj(input)) return [{ path: "", code: "bad_shape" }];
  const section = input;
  if (section.v !== PLAN_VERSION) push("v", "bad_version");
  const flow = typeof section.flow === "string" && section.flow in FLOWS ? (section.flow as PlanFlow) : null;
  if (!flow) {
    push("flow", "unknown_flow");
    return out;
  }
  const F = FLOWS[flow];
  // add-ons
  const mods: Record<string, unknown> = obj(section.mods, "mods", push);
  for (const [m, on] of Object.entries(mods)) {
    if (on != null && typeof on !== "boolean") push(`mods.${m}`, "bad_shape");
    else if (on && !F.mods.includes(m as keyof typeof MODS)) push(`mods.${m}`, "mod_not_allowed");
  }
  // parameters: the flow's and its add-ons' (an add-on switched off may leave its value behind)
  const active = paramDefs(flow, mods as PlanSection["mods"]);
  const allowed = new Set([...F.params, ...F.mods.flatMap((m) => MODS[m].params)].map((d) => d.key as string));
  for (const [key, raw] of Object.entries(obj(section.params, "params", push))) {
    const path = `params.${key}`;
    const value = str(raw, path, push);
    if (!allowed.has(key)) {
      if (value.trim()) push(path, "unknown_param");
      continue;
    }
    const def = active.find((d) => d.key === key);
    if (def && typeof raw === "string" && !readParam(def, value).ok) push(path, "bad_param");
  }
  // score
  const score = str(section.score, "score", push);
  const preset = str(section.preset, "preset", push);
  if (!(scoresFor({ flow, preset: preset || null }) as string[]).includes(score)) push("score", "unknown_score");
  // notes
  str(section.note, "note", push, PLAN_LIMITS.note, "note_too_long");
  for (const [level, note] of Object.entries(obj(section.levelNotes, "levelNotes", push))) {
    if (tooLong(level)) push(`levelNotes.${level}`, "too_long");
    str(note, `levelNotes.${level}`, push, PLAN_LIMITS.note, "note_too_long");
  }
  // rows
  const blocks = arr(section.blocks, "blocks", push);
  if (F.layout === "none" && blocks.some((b) => Array.isArray(b) && b.length)) push("blocks", "blocks_not_allowed");
  if (blocks.length > PLAN_LIMITS.blocks) push("blocks", "too_many_blocks");
  const ids = new Set<string>();
  const take = (list: unknown[], base: string, inInterrupt: boolean) => {
    if (list.length > PLAN_LIMITS.rowsPerBlock) push(base, "too_many_rows");
    list.forEach((raw, i) => {
      const path = `${base}.${i}`;
      const row = readRow(raw, path, push);
      if (!row) return;
      if (row.id && ids.has(row.id)) push(`${path}.id`, "duplicate_id");
      ids.add(row.id);
      validateRow(flow, row, path, inInterrupt, push);
    });
  };
  blocks.forEach((b, i) => take(arr(b, `blocks.${i}`, push), `blocks.${i}`, false));
  take(arr(section.interrupt, "interrupt", push), "interrupt", true);
  // structures
  for (const [key, st] of Object.entries(obj(section.structs, "structs", push))) {
    const kind = isObj(st) && typeof st.kind === "string" ? st.kind : "";
    const def = (STRUCTS as Record<string, (typeof STRUCTS)[keyof typeof STRUCTS]>)[kind];
    if (!isObj(st) || !def) {
      push(`structs.${key}`, "unknown_struct");
      continue;
    }
    if (def.key !== "single" && !F.structs.includes(def.key)) push(`structs.${key}`, "struct_not_allowed");
    for (const f of def.params) {
      const path = `structs.${key}.${f.key}`;
      const v = str(st[f.key], path, push);
      if (!v.trim()) continue;
      const ok = f.kind === "count" ? parseCount(v) != null : f.kind === "time" ? (parseClock(v, "smart") as number) > 0 : true;
      if (!ok) push(path, "bad_struct_param");
    }
  }
  return out;
}
