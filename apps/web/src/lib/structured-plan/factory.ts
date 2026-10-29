/**
 * ADR-270: building and reshaping sections. Every function is pure: it
 * returns a new section and never changes its input. Ids are
 * `crypto.randomUUID()`.
 */
import { FLOWS, MEASURES, MODS, STRUCTS, presetByKey, structDefaults, type PresetDef } from "./catalog";
import { canPerRound, totalRounds, unitKey, unitsOf } from "./rounds";
import { PLAN_VERSION, type PlanCell, type PlanFlow, type PlanRow, type PlanSection, type PlanStructure, type PlanStructureKind } from "./types";

/** A new stable id (rows, groups). */
export const newId = (): string => crypto.randomUUID();

/** Default rest of a new rest row (the mockup's "+ rest" adds 30″). */
export const DEFAULT_REST_ROW = "30″";

/** An empty exercise row, or a rest row of 30″. `more` overrides fields. */
export function newRow(kind: PlanRow["kind"] = "ex", more: Partial<PlanRow> = {}): PlanRow {
  const base: PlanRow =
    kind === "rest"
      ? { id: newId(), kind, name: "", dose: DEFAULT_REST_ROW, load: "", group: null, cells: [{ d: DEFAULT_REST_ROW }] }
      : { id: newId(), kind, name: "", dose: "", load: "", group: null, cells: [] };
  return { ...base, ...more };
}

const clone = <T>(v: T): T => structuredClone(v);

/** A structure with its default fields. */
export function newStructure(kind: PlanStructureKind): PlanStructure {
  return { kind, ...structDefaults(kind) } as PlanStructure;
}

/** Non-flag measures a row shows. */
const valueMeasures = (r: PlanRow) => (r.extra || []).filter((k) => MEASURES[k] && !MEASURES[k].flag) as Exclude<PlanRow["extra"], undefined>;

/**
 * Moves the section to another flow, the mockup's `choose()`: parameters
 * reset to the flow's defaults (plus the preset's), score to its first (or
 * the preset's), add-ons to the preset's that the flow allows. Rows, their
 * measures and per-round values are kept; rest rows only stay in the sets
 * grid; the `rest` flow has no rows. Moving into the sets grid turns a row's
 * same-for-every-round values into its first set; moving out turns the
 * first set back into them (per round stays on when there were more sets).
 */
export function changeFlow(section: PlanSection, flow: PlanFlow, preset: PresetDef | null = null): PlanSection {
  const s = clone(section);
  const F = FLOWS[flow];
  const oldLayout = FLOWS[s.flow]?.layout;
  const keep = s.blocks.map((b) => b.filter((r) => r.kind !== "rest" || F.layout === "grid")).filter((b) => b.length);
  s.flow = flow;
  s.params = { ...Object.fromEntries(F.params.map((f) => [f.key, f.dflt])), ...(preset?.params || {}) };
  s.score = preset?.score || F.scores[0];
  s.preset = preset?.key ?? null;
  s.structs = s.structs || {};
  s.mods = Object.fromEntries(Object.entries(preset?.mods || {}).filter(([m, on]) => on && F.mods.includes(m as keyof typeof MODS)));
  for (const m of F.mods) if (s.mods[m]) for (const f of MODS[m].params) s.params[f.key] ||= f.dflt;
  if (s.mods.interrupt) {
    if (!s.interrupt?.length) s.interrupt = [newRow()];
  } else s.interrupt = [];
  const L = F.layout;
  s.blocks = L === "none" ? [] : keep.length ? keep : [[newRow()]];
  if (L === "slots" && preset?.slots) while (s.blocks.length < preset.slots) s.blocks.push([newRow()]);
  if (L === "grid" && oldLayout !== "grid") {
    for (const r of s.blocks.flat()) {
      if (!r.perRound) r.cells = r.dose || r.load || (r.x && Object.keys(r.x).length) ? [{ d: r.dose, l: r.load, ...(r.x || {}) }] : [];
      r.perRound = false;
    }
  }
  if (L !== "grid" && oldLayout === "grid") {
    for (const r of s.blocks.flat()) {
      const c: PlanCell = r.cells[0] || {};
      r.dose = c.d || "";
      r.load = c.l || "";
      const ms = valueMeasures(r);
      if (ms.length) r.x = Object.fromEntries(ms.map((k) => [k, c[k as keyof PlanCell] || ""]));
      r.perRound = r.cells.length > 1;
    }
  }
  const main = s.blocks[0];
  if (preset?.struct && main) {
    if (STRUCTS[preset.struct].group) {
      while (main.length < 2) main.push(newRow());
      const g = main[0].group || newId();
      main.slice(0, 2).forEach((r) => {
        r.group = g;
      });
      s.structs[g] = newStructure(preset.struct);
    } else s.structs[main[0].id] = newStructure(preset.struct);
  }
  if (preset?.reps && main?.[0]) {
    if (L === "grid") main[0].cells[0] = { ...(main[0].cells[0] || { d: "", l: "" }), d: preset.reps };
    else main[0].dose = preset.reps;
  }
  return s;
}

/** A new section of a flow with its defaults and one empty exercise (none for `rest`). */
export function newSection(flow: PlanFlow): PlanSection {
  const empty: PlanSection = { v: PLAN_VERSION, flow, preset: null, params: {}, mods: {}, blocks: [], interrupt: [], structs: {}, score: "" };
  return changeFlow(empty, flow);
}

/** Applies a preset by key (`tabata`, `death_by`, …): its flow, values, structure, add-ons. Unknown key → unchanged copy. */
export function applyPreset(section: PlanSection, presetKey: string): PlanSection {
  const preset = presetByKey(presetKey);
  return preset ? changeFlow(section, preset.flow, preset) : clone(section);
}

/** Where a row sits: block index (-1 = interrupt rows) and position. */
export function findRow(section: PlanSection, rowId: string): { b: number; i: number; row: PlanRow } | null {
  for (let b = -1; b < section.blocks.length; b++) {
    const list = b === -1 ? section.interrupt || [] : section.blocks[b];
    const i = list.findIndex((r) => r.id === rowId);
    if (i >= 0) return { b, i, row: list[i] };
  }
  return null;
}

const listOf = (s: PlanSection, b: number): PlanRow[] => (b === -1 ? (s.interrupt ||= []) : (s.blocks[b] ||= []));

/**
 * Adds a different kind of round (Alt+S): a new block with one empty row.
 * A new kind of round needs a round to happen in, so the sets / times /
 * rounds count grows to the number of blocks when it is lower.
 */
export function addBlock(section: PlanSection): { section: PlanSection; row: PlanRow } {
  const s = clone(section);
  const row = newRow();
  s.blocks.push([row]);
  const k = s.blocks.length;
  if (totalRounds(s) < k) {
    if (s.flow === "sets") s.params.sets = String(k);
    else if (s.flow === "emom") s.params.times = String(k);
    else s.params.rounds = String(k);
  }
  return { section: s, row };
}

/**
 * Sets the structure of the unit that holds `key` (a row id or group id) in
 * block `b`. A group structure on one row takes the next ungrouped row as
 * its partner, or adds an empty one; a single-row structure on a group
 * breaks the group and applies to its first row.
 */
export function setStructure(section: PlanSection, b: number, key: string, kind: PlanStructureKind): PlanSection {
  const s = clone(section);
  const list = listOf(s, b);
  const u = unitsOf(list).find((x) => unitKey(x) === key || x.rows.some((r) => r.id === key));
  if (!u) return s;
  s.structs ||= {};
  const first = u.rows[0];
  if (STRUCTS[kind].group && u.rows.length === 1) {
    const i = list.indexOf(first);
    const next = list[i + 1];
    const g = newId();
    first.group = g;
    if (next && !next.group) next.group = g;
    else list.splice(i + 1, 0, newRow("ex", { group: g }));
    delete s.structs[first.id];
    s.structs[g] = newStructure(kind);
  } else if (!STRUCTS[kind].group && u.rows.length > 1) {
    if (u.group) delete s.structs[u.group];
    u.rows.forEach((r) => {
      r.group = null;
    });
    if (kind !== "single") s.structs[first.id] = newStructure(kind);
  } else if (kind === "single" || (kind === "superset" && u.group)) delete s.structs[unitKey(u)];
  else s.structs[unitKey(u)] = newStructure(kind);
  return s;
}

/**
 * Superset with the row above (Alt+G), or out of its group when it is in
 * one (a group left with one row dissolves).
 */
export function toggleGroupWithAbove(section: PlanSection, rowId: string): PlanSection {
  const s = clone(section);
  const f = findRow(s, rowId);
  if (!f) return s;
  const list = listOf(s, f.b);
  const r = list[f.i];
  if (r.group) {
    const g = r.group;
    r.group = null;
    const left = list.filter((x) => x.group === g);
    if (left.length === 1) {
      left[0].group = null;
      if (s.structs) delete s.structs[g];
    }
  } else if (f.i > 0) {
    const prev = list[f.i - 1];
    prev.group ||= newId();
    r.group = prev.group;
  }
  return s;
}

/**
 * Values per round on / off (Alt+V) for a row outside the sets grid. On:
 * the same-for-every-round values become round 1. Off: round 1 becomes the
 * same-for-every-round values. Unchanged when the block runs once.
 */
export function togglePerRound(section: PlanSection, rowId: string): PlanSection {
  const s = clone(section);
  const f = findRow(s, rowId);
  if (!f || !canPerRound(s, f.b)) return s;
  const r = listOf(s, f.b)[f.i];
  if (r.perRound) {
    const c: PlanCell = r.cells[0] || {};
    r.dose = c.d || "";
    r.load = c.l || "";
    const ms = valueMeasures(r);
    if (ms.length) r.x = { ...(r.x || {}), ...Object.fromEntries(ms.map((k) => [k, c[k as keyof PlanCell] || ""])) };
    r.perRound = false;
  } else {
    r.cells = [{ d: r.dose, l: r.load, ...(r.x || {}) }];
    r.perRound = true;
  }
  return s;
}
