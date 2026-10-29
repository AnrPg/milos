/**
 * ADR-270: the rules a saved section must meet. The API
 * (`Palee.Workouts.Domain.StructuredPlan`) enforces the same rules with the
 * same codes and paths, so the editor can show exactly what the server
 * would refuse.
 *
 * Paths are dot-separated keys and indexes from the section root:
 * `params.rest`, `blocks.0.2.cells.1.l`, `blocks.1.0.x.tempo`,
 * `interrupt.0.dose`, `structs.<key>.intra`.
 */
import { FLOWS, MEASURES, MODS, STRUCTS, paramDefs, scoresFor, type ParamDef } from "./catalog";
import { parseClock, parseDose, parseTimes, setLoads, tempoParts, type PlanErrorCode } from "./parse";
import { usesCells } from "./rounds";
import { PLAN_VERSION, type PlanCell, type PlanMeasure, type PlanRow, type PlanSection } from "./types";

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

/**
 * A typed parameter reads for its kind. Empty is fine (not set). A `time`
 * may be a range of two ascending durations ("90-120″").
 */
export function paramValid(def: Pick<ParamDef, "kind" | "bare">, value: string): boolean {
  const v = value.trim();
  if (!v) return true;
  switch (def.kind) {
    case "time": {
      const one = parseClock(v, def.bare);
      if (typeof one === "number") return one > 0;
      const range = parseTimes(v, def.bare);
      return Boolean(range && range !== "bad" && range.range);
    }
    case "times": {
      const t = parseTimes(v, def.bare);
      return Boolean(t && t !== "bad");
    }
    case "count":
      return /^\d+$/.test(v) && +v > 0;
    case "range": {
      const m = /^(\d+)(?:\s*-\s*(\d+))?$/.exec(v);
      return Boolean(m && +m[1] > 0 && +(m[2] || m[1]) >= +m[1]);
    }
    case "text":
      return true;
  }
}

/**
 * A measure value: tempo has 4 marks; numeric measures start with a number
 * (or, in per-set cells, a `+x`/`-x` change); RPE is at most 10.
 */
export function measureIssue(key: Exclude<PlanMeasure, "side">, value: string, inCell: boolean): PlanErrorCode | null {
  const t = value.trim();
  if (!t) return null;
  const M = MEASURES[key];
  if (M.text) return tempoParts(t) ? null : "bad_tempo";
  if (!(inCell ? /^[+-]?\d/ : /^\d/).test(t)) return "bad_measure_value";
  if (M.max != null && !/^[+-]/.test(t)) {
    const nums = (t.replace(",", ".").match(/\d+(?:\.\d+)?/g) || []).map(Number);
    if (nums.some((n) => n > (M.max as number))) return "rpe_over_max";
  }
  return null;
}

const tooLong = (v: string | null | undefined, max: number = PLAN_LIMITS.text) => (v ?? "").length > max;

function validateRow(section: PlanSection, row: PlanRow, path: string, inInterrupt: boolean, out: PlanIssue[]) {
  const push = (p: string, code: PlanErrorCode) => out.push({ path: `${path}${p ? "." + p : ""}`, code });
  if (row.kind !== "ex" && row.kind !== "rest") push("kind", "bad_row_kind");
  if (tooLong(row.name)) push("name", "too_long");
  if (tooLong(row.exerciseRef)) push("exerciseRef", "too_long");
  if (tooLong(row.note, PLAN_LIMITS.note)) push("note", "note_too_long");
  const seen = new Set<string>();
  (row.extra || []).forEach((k, i) => {
    if (!MEASURES[k]) push(`extra.${i}`, "unknown_measure");
    else if (seen.has(k)) push(`extra.${i}`, "duplicate_measure");
    seen.add(k);
  });
  const measures = (row.extra || []).filter((k) => MEASURES[k] && !MEASURES[k].flag) as Exclude<PlanMeasure, "side">[];
  if (row.cells.length > PLAN_LIMITS.cellsPerRow) push("cells", "too_many_cells");
  const cellMode = !inInterrupt && usesCells(section, row);
  if (cellMode) {
    const loads = row.kind === "ex" ? setLoads(row, row.cells.length) : null;
    row.cells.forEach((c: PlanCell, j) => {
      for (const [k, v] of Object.entries(c)) if (typeof v === "string" && tooLong(v)) push(`cells.${j}.${k}`, "too_long");
      if (c.d && parseDose(c.d) === "bad") push(`cells.${j}.d`, "bad_dose");
      const le = loads?.errors[j];
      if (le) push(`cells.${j}.l`, le);
      for (const k of measures) {
        const code = measureIssue(k, c[k] || "", true);
        if (code) push(`cells.${j}.${k}`, code);
      }
    });
  } else {
    if (tooLong(row.dose)) push("dose", "too_long");
    if (tooLong(row.load)) push("load", "too_long");
    if (row.dose && parseDose(row.dose) === "bad") push("dose", "bad_dose");
    if (row.kind === "ex" && /^\d+(?:[.,]\d+)?$/.test(row.load.trim())) push("load", "missing_unit");
    for (const k of measures) {
      const v = row.x?.[k] || "";
      if (tooLong(v)) push(`x.${k}`, "too_long");
      const code = measureIssue(k, v, false);
      if (code) push(`x.${k}`, code);
    }
  }
}

/** Every problem of a section, as `{ path, code }`. Empty list = valid. */
export function validateSection(section: PlanSection): PlanIssue[] {
  const out: PlanIssue[] = [];
  if (section.v !== PLAN_VERSION) out.push({ path: "v", code: "bad_version" });
  const F = FLOWS[section.flow];
  if (!F) {
    out.push({ path: "flow", code: "unknown_flow" });
    return out;
  }
  // add-ons
  for (const [m, on] of Object.entries(section.mods || {})) {
    if (on && !F.mods.includes(m as keyof typeof MODS)) out.push({ path: `mods.${m}`, code: "mod_not_allowed" });
  }
  // parameters: the flow's and its add-ons' (an add-on switched off may leave its value behind)
  const active = paramDefs(section.flow, section.mods);
  const allowed = new Set([...F.params, ...F.mods.flatMap((m) => MODS[m].params)].map((d) => d.key));
  for (const [key, value] of Object.entries(section.params || {})) {
    if (typeof value !== "string") continue;
    const path = `params.${key}`;
    if (!allowed.has(key as keyof PlanSection["params"])) {
      if (value.trim()) out.push({ path, code: "unknown_param" });
      continue;
    }
    if (tooLong(value)) out.push({ path, code: "too_long" });
    const def = active.find((d) => d.key === key);
    if (def && !paramValid(def, value)) out.push({ path, code: "bad_param" });
  }
  // score
  if (!(scoresFor(section) as string[]).includes(section.score)) out.push({ path: "score", code: "unknown_score" });
  // notes
  if (tooLong(section.note, PLAN_LIMITS.note)) out.push({ path: "note", code: "note_too_long" });
  if (tooLong(section.preset)) out.push({ path: "preset", code: "too_long" });
  for (const [level, note] of Object.entries(section.levelNotes || {})) {
    if (tooLong(level)) out.push({ path: `levelNotes.${level}`, code: "too_long" });
    if (tooLong(note, PLAN_LIMITS.note)) out.push({ path: `levelNotes.${level}`, code: "note_too_long" });
  }
  // rows
  if (F.layout === "none" && section.blocks.some((b) => b.length)) out.push({ path: "blocks", code: "blocks_not_allowed" });
  if (section.blocks.length > PLAN_LIMITS.blocks) out.push({ path: "blocks", code: "too_many_blocks" });
  const ids = new Set<string>();
  const checkId = (row: PlanRow, path: string) => {
    if (ids.has(row.id)) out.push({ path: `${path}.id`, code: "duplicate_id" });
    ids.add(row.id);
  };
  section.blocks.forEach((list, b) => {
    if (list.length > PLAN_LIMITS.rowsPerBlock) out.push({ path: `blocks.${b}`, code: "too_many_rows" });
    list.forEach((row, i) => {
      checkId(row, `blocks.${b}.${i}`);
      validateRow(section, row, `blocks.${b}.${i}`, false, out);
    });
  });
  const intr = section.interrupt || [];
  if (intr.length > PLAN_LIMITS.rowsPerBlock) out.push({ path: "interrupt", code: "too_many_rows" });
  intr.forEach((row, i) => {
    checkId(row, `interrupt.${i}`);
    validateRow(section, row, `interrupt.${i}`, true, out);
  });
  // structures
  for (const [key, st] of Object.entries(section.structs || {})) {
    const def = STRUCTS[st?.kind];
    if (!def) {
      out.push({ path: `structs.${key}`, code: "unknown_struct" });
      continue;
    }
    if (st.kind !== "single" && !F.structs.includes(st.kind)) out.push({ path: `structs.${key}`, code: "struct_not_allowed" });
    const fields = st as unknown as Record<string, unknown>;
    for (const f of def.params) {
      const v = typeof fields[f.key] === "string" ? (fields[f.key] as string) : "";
      const ok = f.kind === "count" ? !v.trim() || /^\d+$/.test(v.trim()) : f.kind === "time" ? !v.trim() || typeof parseClock(v, "smart") === "number" : !tooLong(v);
      if (!ok || tooLong(v)) out.push({ path: `structs.${key}.${f.key}`, code: "bad_struct_param" });
    }
  }
  return out;
}
