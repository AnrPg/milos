/**
 * TEMPORARY local ports (agent 5) of the round and value rules of the
 * structured WOD mockup, needed by the read-only view before
 * `@/lib/structured-plan` (agent 1, branch plan/1-core) lands. Every export
 * here has the same meaning as the library's `unitsOf`, `structOf`,
 * `totalRounds`, `occurrences`, `setLoads`, `progress` and `repeatText`, and
 * is swapped for it once that branch is merged.
 */
import type { PlanCell, PlanMeasure, PlanRow, PlanSection, PlanStructure, PlanUnit } from "@/lib/structured-plan/types";

type CellKey = keyof PlanCell;

/** Consecutive rows of the same group form one execution unit. */
export function unitsOf(rows: PlanRow[]): PlanUnit[] {
  const units: PlanUnit[] = [];
  for (const row of rows) {
    const last = units.at(-1);
    if (row.group && last && last.group === row.group) last.rows.push(row);
    else units.push({ group: row.group ?? null, rows: [row] });
  }
  return units;
}

const GROUP_KINDS = new Set<PlanStructure["kind"]>(["superset", "complex"]);

/** The structure of a unit; a stored structure that does not fit the unit's shape falls back to plain. */
export function structOf(section: PlanSection, unit: PlanUnit): PlanStructure {
  const key = unit.group ?? unit.rows[0]?.id ?? "";
  const stored = section.structs?.[key];
  const isGroup = unit.rows.length > 1;
  if (stored && GROUP_KINDS.has(stored.kind) === isGroup) return stored;
  return { kind: isGroup ? "superset" : "single" };
}

const count = (value: string | undefined) => {
  const text = (value ?? "").trim();
  return /^\d+$/.test(text) && Number(text) > 0 ? Number(text) : null;
};

/** Rounds, sets or slots of a section; `Infinity` for AMRAP (it has no last round). */
export function totalRounds(section: PlanSection): number {
  if (section.flow === "sets") {
    const match = /^(\d+)(?:\s*-\s*(\d+))?$/.exec((section.params.sets ?? "").trim());
    return match ? Number(match[2] ?? match[1]) : 1;
  }
  if (section.flow === "emom") return count(section.params.times) ?? 10;
  if (section.flow === "amrap") return Infinity;
  return count(section.params.rounds) ?? 1;
}

const cellFilled = (cell: PlanCell | undefined) => Boolean(cell && Object.values(cell).some((value) => String(value ?? "").trim()));

/** How many columns of a row the coach actually wrote (trailing empty cells inherit). */
export function writtenColumns(row: PlanRow): number {
  return row.cells.reduce((last, cell, index) => (cellFilled(cell) ? index + 1 : last), 0);
}

/**
 * The round numbers (1-based) that block `b` runs in: blocks alternate
 * (1, 3, 5… / 2, 4, 6…). AMRAP is open: the rounds the coach wrote plus one.
 */
export function occurrences(section: PlanSection, block: number): { list: number[]; open: boolean } {
  const kinds = Math.max(1, section.blocks.length);
  const total = totalRounds(section);
  const open = total === Infinity;
  const filled = open ? Math.max(0, ...(section.blocks[block] ?? []).map(writtenColumns)) : 0;
  const list: number[] = [];
  for (let round = block; (open ? list.length < Math.max(2, filled + 1) : round < total) && list.length < 50; round += kinds) {
    list.push(round + 1);
  }
  return { list, open };
}

const NUMBER = "\\d+(?::\\d\\d)?(?:\\.\\d+)?";

/**
 * Values of one row and key over `n` columns, with the same rules as load:
 * empty repeats (or keeps adding), `+x` / `-x` changes from the column before,
 * `a→b` spreads to the last column. Words repeat as written.
 */
export function progress(row: PlanRow, key: CellKey, n: number, clockish = false): string[] {
  const toNumber = (text: string) => (clockish && /^\d+:\d\d$/.test(text) ? text.split(":").reduce((sum, part) => sum * 60 + Number(part), 0) : Number(text));
  const show = (value: number) =>
    clockish && value >= 60 ? `${Math.floor(value / 60)}:${String(Math.round(value % 60)).padStart(2, "0")}` : `${Math.round(value * 10) / 10}`;
  const out: string[] = [];
  let previous: number | null = null;
  let delta: number | null = null;
  let spread: { a: number; b: number; at: number } | null = null;
  let suffix = "";
  for (let index = 0; index < n; index += 1) {
    const text = String(row.cells[index]?.[key] ?? "").trim().replace(",", ".");
    let match: RegExpExecArray | null;
    if (!text) {
      if (spread) previous = spread.a + ((spread.b - spread.a) * (index - spread.at)) / Math.max(1, n - 1 - spread.at);
      else if (delta !== null && previous !== null) previous += delta;
      out.push(previous !== null ? show(previous) + suffix : (out[index - 1] ?? ""));
      continue;
    }
    if ((match = new RegExp(`^([+-])(${NUMBER})$`).exec(text)) && previous !== null) {
      delta = (match[1] === "-" ? -1 : 1) * toNumber(match[2]!);
      spread = null;
      previous += delta;
      out.push(show(previous) + suffix);
      continue;
    }
    if ((match = new RegExp(`^(${NUMBER})\\s*(?:→|->)\\s*(${NUMBER})(.*)$`).exec(text))) {
      previous = toNumber(match[1]!);
      spread = { a: previous, b: toNumber(match[2]!), at: index };
      delta = null;
      suffix = match[3] ?? "";
      out.push(show(previous) + suffix);
      continue;
    }
    if ((match = new RegExp(`^(${NUMBER})(.*)$`).exec(text))) {
      previous = toNumber(match[1]!);
      suffix = match[2] ?? "";
      delta = null;
      spread = null;
      out.push(text);
      continue;
    }
    previous = null;
    delta = null;
    spread = null;
    out.push(text);
  }
  return out;
}

/** Text values (tempo) only repeat; they never count up. */
export function repeatText(row: PlanRow, key: CellKey, n: number): string[] {
  const out: string[] = [];
  for (let index = 0; index < n; index += 1) out.push(String(row.cells[index]?.[key] ?? "").trim() || out[index - 1] || "");
  return out;
}

export type LoadValues = { values: string[]; unit: "kg" | "%" | null };

/**
 * Loads of a row over `n` columns. The unit (kg or %) is stated once per row
 * and bare numbers take it; words («βαρύ») are kept as written.
 */
export function setLoads(row: PlanRow, n: number): LoadValues {
  const raw = (index: number) =>
    String(row.cells[index]?.l ?? "")
      .trim()
      .toLowerCase()
      .replace(",", ".")
      .replace(/κιλ[άα]?/, "kg");
  const pattern = /^([+-]?\d+(?:\.\d+)?)\s*(%|kg)?(?:\s*(?:→|->|ως|έως)\s*(\d+(?:\.\d+)?)\s*(%|kg)?)?$/;
  const stated = Array.from({ length: n }, (_, index) => {
    const match = pattern.exec(raw(index));
    return match ? ((match[4] ?? match[2] ?? null) as "kg" | "%" | null) : null;
  });
  const unit = stated.find(Boolean) ?? null;
  const show = (value: number) => `${Math.round(value * 10) / 10}${unit === "%" ? "%" : " kg"}`;
  const values: string[] = [];
  let previous: number | null = null;
  let delta: number | null = null;
  let spread: { a: number; b: number; at: number } | null = null;
  for (let index = 0; index < n; index += 1) {
    const text = raw(index);
    const match = text ? pattern.exec(text) : null;
    if (!text) {
      if (spread) previous = spread.a + ((spread.b - spread.a) * (index - spread.at)) / Math.max(1, n - 1 - spread.at);
      else if (delta !== null && previous !== null) previous += delta;
      values.push(previous !== null && unit ? show(previous) : (values[index - 1] ?? ""));
      continue;
    }
    if (!match) {
      previous = null;
      delta = null;
      spread = null;
      values.push(String(row.cells[index]?.l ?? "").trim());
      continue;
    }
    if (!unit || (stated[index] && stated[index] !== unit)) {
      values.push(String(row.cells[index]?.l ?? "").trim());
      continue;
    }
    const relative = /^[+-]/.test(match[1]!);
    if (relative && previous !== null && !match[3]) {
      delta = Number(match[1]);
      spread = null;
      previous += delta;
      values.push(show(previous));
      continue;
    }
    if (match[3]) {
      previous = Math.abs(Number(match[1]));
      spread = { a: previous, b: Number(match[3]), at: index };
      delta = null;
      values.push(show(previous));
      continue;
    }
    previous = Math.abs(Number(match[1]));
    delta = null;
    spread = null;
    values.push(show(previous));
  }
  return { values, unit };
}

/** Measures that are text (repeat only) or clock values (count in mm:ss). */
export const TEXT_MEASURES = new Set<PlanMeasure>(["tempo"]);
export const CLOCK_MEASURES = new Set<PlanMeasure>(["pace", "hold"]);
