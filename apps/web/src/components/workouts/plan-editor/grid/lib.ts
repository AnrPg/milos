/**
 * The pieces of `@/lib/structured-plan` the grid uses, with the row-free
 * signatures its model is written against (cells in, values out).
 */
import {
  FLOWS,
  MEASURES,
  STRUCTS,
  measureUnit as coreMeasureUnit,
  newStructure,
  progress as coreProgress,
  repeatText as coreRepeatText,
  setLoads as coreSetLoads,
  tempoParts,
  type CellMeasure,
  type MeasureUnit,
  type PlanCell,
  type PlanSection,
  type PlanStructureKind,
} from "@/lib/structured-plan";

export {
  MEASURE_KEYS,
  MEASURES,
  STRUCTS,
  fold,
  fuzzy,
  occurrences,
  parseClock,
  parseDose,
  parseLoad,
  setsRange,
  structOf,
  totalRounds,
  unitKey,
  unitsOf,
  type FuzzyMatch,
  type ParsedDose as Dose,
} from "@/lib/structured-plan";

type CellKey = keyof PlanCell;

export type LoadError = "missing_unit" | "mixed_unit";
export type LoadSeries = { values: string[]; errors: Record<number, LoadError>; unit: "kg" | "%" | null };

export function setLoads(cells: PlanCell[], n: number): LoadSeries {
  const out = coreSetLoads({ cells }, n);
  const errors: Record<number, LoadError> = {};
  out.errors.forEach((e, i) => {
    if (e === "missing_unit" || e === "mixed_unit") errors[i] = e;
  });
  return { values: out.values, errors, unit: out.unit };
}

export const progress = (cells: PlanCell[], key: CellKey, n: number, clockish = false) => coreProgress({ cells }, key, n, clockish);
export const repeatText = (cells: PlanCell[], key: CellKey, n: number) => coreRepeatText({ cells }, key, n);
export const repeatDose = (cells: PlanCell[], n: number) => repeatText(cells, "d", n);

/** The four tempo marks as typed ("X" upper case), or null. */
export function parseTempo(text: string): [string, string, string, string] | null {
  const p = tempoParts(text);
  return p ? [String(p.down), String(p.bottom), String(p.up), String(p.top)] : null;
}

/** Unit code (`PlanCore.unit.<code>`) next to a measure value, or "" when the value says it. */
export const measureUnit = (k: CellMeasure, value: string): MeasureUnit | "" => coreMeasureUnit(k, value) ?? "";

export const flowStructs = (flow: PlanSection["flow"]): PlanStructureKind[] => FLOWS[flow].structs;
export const isGroupStructure = (kind: PlanStructureKind) => STRUCTS[kind].group;
export const structureDefaults = newStructure;
export const measureAliases = (k: keyof typeof MEASURES) => MEASURES[k].aliases.join(" ");

/** The fields ↑ ↓ move between, row to row (value fields, names and notes). */
export const NAV_FIELDS = "input[data-key], textarea[data-key]";
