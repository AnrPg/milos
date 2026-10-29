/**
 * TEMPORARY shim (agent 3): the few catalog / factory pieces the editor store
 * needs from `@/lib/structured-plan` (agent 1, branch plan/1-core) before
 * that library lands. Every export here is replaced by the library's own and
 * this file is deleted once plan/1-core is merged.
 */
import type {
  PlanCell,
  PlanFlow,
  PlanMods,
  PlanParams,
  PlanRow,
  PlanSection,
  PlanStructure,
  PlanStructureKind,
} from "@/lib/structured-plan/types";
import { PLAN_VERSION } from "@/lib/structured-plan/types";

type ParamKey = keyof PlanParams;

export type FlowRule = {
  /** grid: per-set columns (sets); loop / slots / strip: same values every round unless per round; none: no exercises. */
  layout: "grid" | "loop" | "slots" | "strip" | "none";
  fields: { key: ParamKey; kind: "range" | "count" | "time" | "times"; dflt: string }[];
  scores: string[];
  structs: PlanStructureKind[];
  mods: (keyof PlanMods)[];
};

export const FLOW_RULES: Record<PlanFlow, FlowRule> = {
  sets: { layout: "grid", fields: [{ key: "sets", kind: "range", dflt: "4" }, { key: "rest", kind: "time", dflt: "90″" }], scores: ["none", "best_load", "reps"], structs: ["single", "superset", "complex", "cluster", "drop", "restpause"], mods: ["interrupt"] },
  for_time: { layout: "loop", fields: [{ key: "rounds", kind: "count", dflt: "1" }, { key: "cap", kind: "time", dflt: "" }], scores: ["time", "rounds_reps"], structs: ["single", "superset", "complex"], mods: ["interrupt"] },
  amrap: { layout: "loop", fields: [{ key: "dur", kind: "times", dflt: "12" }, { key: "rest", kind: "time", dflt: "" }], scores: ["rounds_reps", "reps"], structs: ["single", "superset", "complex"], mods: ["interrupt"] },
  emom: { layout: "slots", fields: [{ key: "every", kind: "time", dflt: "1:00" }, { key: "times", kind: "count", dflt: "10" }], scores: ["none", "done", "reps"], structs: ["single", "superset", "complex", "cluster"], mods: [] },
  intervals: { layout: "strip", fields: [{ key: "work", kind: "time", dflt: "20″" }, { key: "off", kind: "time", dflt: "10″" }, { key: "rounds", kind: "count", dflt: "8" }], scores: ["total_reps", "lowest_round", "distance"], structs: ["single", "superset", "complex"], mods: ["hr"] },
  rest: { layout: "none", fields: [{ key: "dur", kind: "time", dflt: "2:00" }], scores: ["none"], structs: [], mods: [] },
};

export const FLOW_KEYS = Object.keys(FLOW_RULES) as PlanFlow[];

/** Add-on fields with their defaults. */
export const MOD_FIELDS: Record<keyof PlanMods, { key: ParamKey; kind: "time" | "count"; dflt: string }> = {
  interrupt: { key: "intEvery", kind: "time", dflt: "2:00" },
  hr: { key: "hrTarget", kind: "count", dflt: "120" },
};

export type PresetDef = {
  key: string;
  flow: PlanFlow;
  params?: PlanParams;
  mods?: PlanMods;
  struct?: PlanStructureKind;
  reps?: string;
  slots?: number;
  score?: string;
};

export const PRESETS: PresetDef[] = [
  { key: "tabata", flow: "intervals", params: { work: "20″", off: "10″", rounds: "8" } },
  { key: "billat", flow: "intervals", params: { work: "30″", off: "30″", rounds: "10" }, score: "distance" },
  { key: "hrr", flow: "intervals", params: { work: "3:00", off: "", rounds: "3" }, mods: { hr: true } },
  { key: "death_by", flow: "emom", params: { every: "1:00", times: "" }, reps: "1-2-3…", score: "rounds_reps" },
  { key: "even_odd", flow: "emom", slots: 2 },
  { key: "complex_emom", flow: "emom", slots: 3 },
  { key: "edt", flow: "amrap", params: { dur: "15" }, struct: "superset", score: "reps" },
  { key: "chipper", flow: "for_time" },
  { key: "21_15_9", flow: "for_time", reps: "21-15-9" },
  { key: "ladder", flow: "for_time", reps: "2-4-6…" },
  { key: "calorie_target", flow: "for_time", reps: "100 cal" },
  { key: "to_failure", flow: "sets", reps: "max" },
  { key: "superset", flow: "sets", struct: "superset" },
  { key: "cluster", flow: "sets", struct: "cluster" },
  { key: "drop_set", flow: "sets", struct: "drop" },
  { key: "rest_pause", flow: "sets", struct: "restpause" },
  { key: "interrupt", flow: "for_time", mods: { interrupt: true } },
];

const STRUCT_DEFAULTS: Record<PlanStructureKind, PlanStructure> = {
  single: { kind: "single" },
  superset: { kind: "superset" },
  complex: { kind: "complex" },
  cluster: { kind: "cluster", clusters: "3", intra: "15″" },
  drop: { kind: "drop", drops: "2", dropby: "-20%" },
  restpause: { kind: "restpause", minis: "3", intra: "15″" },
};

export const isGroupStructure = (kind: PlanStructureKind) => kind === "superset" || kind === "complex";
export const structureDefaults = (kind: PlanStructureKind): PlanStructure => ({ ...STRUCT_DEFAULTS[kind] });

export const newId = () => crypto.randomUUID();

export function newRow(kind: PlanRow["kind"] = "ex", init: Partial<PlanRow> = {}): PlanRow {
  return { id: newId(), kind, name: "", dose: "", load: "", cells: [], group: null, ...init };
}

export function defaultParams(flow: PlanFlow): PlanParams {
  return Object.fromEntries(FLOW_RULES[flow].fields.map((f) => [f.key, f.dflt]));
}

export function emptySection(flow: PlanFlow): PlanSection {
  return { v: PLAN_VERSION, flow, preset: null, params: defaultParams(flow), mods: {}, blocks: flow === "rest" ? [] : [[newRow()]], interrupt: [], structs: {}, score: FLOW_RULES[flow].scores[0] };
}

const cellOf = (row: PlanRow): PlanCell => ({ d: row.dose, l: row.load, ...(row.x ?? {}) });

/** Switches a section to another flow, keeping its exercises and their values. */
export function convertFlow(plan: PlanSection, flow: PlanFlow, preset: PresetDef | null = null): PlanSection {
  const from = FLOW_RULES[plan.flow].layout;
  const to = FLOW_RULES[flow].layout;
  let blocks = plan.blocks
    .map((block) => block.filter((row) => row.kind !== "rest" || to === "grid").map((row) => ({ ...row, cells: [...row.cells] })))
    .filter((block) => block.length);
  if (to === "none") blocks = [];
  else if (!blocks.length) blocks = [[newRow()]];
  if (to === "grid" && from !== "grid") {
    blocks = blocks.map((block) => block.map((row) => (row.perRound ? { ...row, perRound: false } : { ...row, perRound: false, cells: row.dose || row.load || row.x ? [cellOf(row)] : [] })));
  }
  if (to !== "grid" && from === "grid") {
    blocks = blocks.map((block) => block.map((row) => {
      const first = row.cells[0] ?? {};
      const x = Object.fromEntries((row.extra ?? []).filter((k) => k !== "side").map((k) => [k, first[k as keyof PlanCell] ?? ""]));
      return { ...row, dose: first.d ?? "", load: first.l ?? "", x, perRound: row.cells.length > 1 };
    }));
  }
  const allowedMods = FLOW_RULES[flow].mods;
  const mods: PlanMods = Object.fromEntries(Object.entries(preset?.mods ?? {}).filter(([m]) => allowedMods.includes(m as keyof PlanMods)));
  const params: PlanParams = { ...defaultParams(flow), ...(preset?.params ?? {}) };
  for (const m of Object.keys(mods) as (keyof PlanMods)[]) params[MOD_FIELDS[m].key] ??= MOD_FIELDS[m].dflt;
  const structs: Record<string, PlanStructure> = { ...(plan.structs ?? {}) };
  if (to === "slots" && preset?.slots) while (blocks.length < preset.slots) blocks.push([newRow()]);
  const main = blocks[0];
  if (preset?.struct && main) {
    if (isGroupStructure(preset.struct)) {
      while (main.length < 2) main.push(newRow());
      const group = main[0].group ?? newId();
      main[0] = { ...main[0], group };
      main[1] = { ...main[1], group };
      structs[group] = structureDefaults(preset.struct);
    } else structs[main[0].id] = structureDefaults(preset.struct);
  }
  if (preset?.reps && main?.[0]) {
    const row = main[0];
    main[0] = to === "grid" ? { ...row, cells: [{ ...(row.cells[0] ?? {}), d: preset.reps }, ...row.cells.slice(1)] } : { ...row, dose: preset.reps };
  }
  return {
    ...plan,
    flow,
    preset: preset?.key ?? null,
    params,
    mods,
    blocks,
    interrupt: mods.interrupt ? (plan.interrupt?.length ? plan.interrupt : [newRow()]) : [],
    structs,
    score: preset?.score ?? FLOW_RULES[flow].scores[0],
  };
}

/** How many rounds / sets / slots a section has; `Infinity` for AMRAP. */
export function totalRounds(plan: PlanSection): number {
  const count = (v: string | undefined) => (/^\d+$/.test((v ?? "").trim()) && Number(v) > 0 ? Number(v) : null);
  if (plan.flow === "sets") {
    const m = /^(\d+)(?:\s*-\s*(\d+))?$/.exec((plan.params.sets ?? "").trim());
    return m ? Number(m[2] ?? m[1]) : 1;
  }
  if (plan.flow === "emom") return count(plan.params.times) ?? 10;
  if (plan.flow === "amrap") return Infinity;
  return count(plan.params.rounds) ?? 1;
}
