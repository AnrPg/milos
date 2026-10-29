/**
 * ADR-270: rounds, blocks and execution units of a section.
 *
 * Blocks are kinds of round that alternate: with two blocks, block 0 is
 * done in rounds 1, 3, 5… and block 1 in rounds 2, 4, 6…; with as many
 * blocks as rounds every round is its own. The same holds in every flow
 * (sets, rounds, EMOM minutes, intervals). AMRAP has no last round.
 */
import { FLOWS, STRUCTS } from "./catalog";
import { mmss, parseClock, parseCount, parseCountRange, type PlanText, type RoundWord } from "./parse";
import type { PlanRow, PlanSection, PlanStructure, PlanUnit } from "./types";

/** Most columns a block shows (sets / rounds) and most blocks a section has. */
export const MAX_COLUMNS = 12;

/** Execution units: one row, or consecutive rows of the same group done together (set-wise). */
export function unitsOf(list: PlanRow[]): PlanUnit[] {
  const out: PlanUnit[] = [];
  for (const r of list) {
    const last = out[out.length - 1];
    if (r.group && last && last.group === r.group) last.rows.push(r);
    else out.push({ group: r.group ?? null, rows: [r] });
  }
  return out;
}

/** The key a unit's structure is stored under: its group id, or its row id. */
export const unitKey = (u: PlanUnit): string => u.group || u.rows[0].id;

/**
 * The structure of a unit. A stored structure that does not fit (a group
 * structure on one row, or the reverse) is ignored: a group is a superset,
 * one row is single.
 */
export function structOf(section: Pick<PlanSection, "structs">, unit: PlanUnit): PlanStructure {
  const st = section.structs?.[unitKey(unit)];
  const isGroup = unit.rows.length > 1;
  if (st && STRUCTS[st.kind] && STRUCTS[st.kind].group === isGroup) return st;
  return { kind: isGroup ? "superset" : "single" };
}

/** A parameter as a time in seconds (cap and dur read bare numbers as minutes), or null. */
export function paramSecs(section: Pick<PlanSection, "params">, key: keyof PlanSection["params"]): number | null {
  const v = section.params?.[key];
  if (typeof v !== "string" || !v.trim()) return null;
  const secs = parseClock(v, key === "cap" || key === "dur" ? "min" : "smart");
  return typeof secs === "number" && secs > 0 ? secs : null;
}

/** A parameter as a positive whole number, or null. */
export function paramCount(section: Pick<PlanSection, "params">, key: keyof PlanSection["params"]): number | null {
  return parseCount(section.params?.[key]);
}

/** Sets of a `sets` flow: "4" → 4–4, "3-4" / "3 ή 4" → 3–4 (sets past `min` are "if they can"). Unreadable → 1–1. */
export function setsRange(section: Pick<PlanSection, "params">): { min: number; max: number } {
  return parseCountRange(section.params?.sets) ?? { min: 1, max: 1 };
}

/**
 * How many rounds (sets, intervals) the section runs: sets → the most sets,
 * EMOM → its times (Infinity when empty: Death by runs until you cannot
 * finish in time), AMRAP → Infinity, others → rounds (1 when empty).
 */
export function totalRounds(section: Pick<PlanSection, "flow" | "params">): number {
  if (section.flow === "sets") return setsRange(section).max;
  if (section.flow === "emom") return paramCount(section, "times") || Infinity;
  if (section.flow === "amrap") return Infinity;
  return paramCount(section, "rounds") || 1;
}

/** Last column (1-based) where any row of the list wrote a per-round value. */
function writtenColumns(section: Pick<PlanSection, "flow">, list: PlanRow[]): number {
  const grid = FLOWS[section.flow].layout === "grid";
  let filled = 0;
  for (const r of list) {
    if (!grid && !r.perRound) continue;
    if (!Array.isArray(r.cells)) continue;
    r.cells.forEach((c, i) => {
      if (c && Object.values(c).some((v) => String(v ?? "").trim())) filled = Math.max(filled, i + 1);
    });
  }
  return filled;
}

/**
 * The rounds (1-based) block `blockIndex` is done in, one column each, at
 * most 12. AMRAP and an EMOM without times are open (no last round): the
 * list is the rounds the coach wrote in that block plus one empty column,
 * at least 2; after the last written round the coach's own value applies.
 */
export function occurrences(
  section: Pick<PlanSection, "flow" | "params" | "blocks">,
  blockIndex: number,
): { list: number[]; open: boolean } {
  const k = Math.max(1, section.blocks.length);
  const total = totalRounds(section);
  const open = total === Infinity;
  const list: number[] = [];
  const want = open ? Math.max(2, writtenColumns(section, section.blocks[blockIndex] || []) + 1) : Infinity;
  for (let i = blockIndex; (open ? list.length < want : i < total) && list.length < MAX_COLUMNS; i += k) list.push(i + 1);
  return { list, open };
}

/** The word for one column: a set (sets), an interval (EMOM, intervals) or a round. */
export function roundWord(section: Pick<PlanSection, "flow">): RoundWord {
  if (section.flow === "sets") return "set";
  if (section.flow === "emom" || section.flow === "intervals") return "interval";
  return "round";
}

/** i18n key of that word: `PlanCore.roundWord.set|round|interval`. */
export const roundWordKey = (section: Pick<PlanSection, "flow">): string => `PlanCore.roundWord.${roundWord(section)}`;

const listText = (nums: (number | string)[], more: boolean) => nums.join(", ") + (more ? ", …" : "");

/**
 * The label of a block, for i18n (`PlanCore.block.*`):
 *  - `one`    {word, n}: the only occurrence ("Set 3");
 *  - `minute` {list}: EMOM every minute ("Minute 1, 3, 5, …");
 *  - `slot`   {word, list, at}: EMOM every other time ("Interval 1, 3, … · 0:00, 5:00, …");
 *  - `list`   {word, list}: everything else ("Round 1, 3, 5, …").
 */
export function blockLabel(section: Pick<PlanSection, "flow" | "params" | "blocks">, b: number): PlanText {
  const { list, open } = occurrences(section, b);
  const word = roundWord(section);
  const k = section.blocks.length;
  if (k >= totalRounds(section) && list.length === 1) return { key: "PlanCore.block.one", values: { word, n: list[0] } };
  if (section.flow === "emom") {
    const e = paramSecs(section, "every");
    if (e === 60) return { key: "PlanCore.block.minute", values: { list: listText(list.slice(0, 3), list.length > 3 || open) } };
    if (e) {
      const two = list.slice(0, 2);
      return { key: "PlanCore.block.slot", values: { word, list: listText(two, true), at: listText(two.map((n) => mmss(e * (n - 1))), true) } };
    }
  }
  return { key: "PlanCore.block.list", values: { word, list: listText(list.slice(0, 3), open || list.length > 3) } };
}

/** Values per round (Alt+V) are possible: not in the sets grid (always per set), and the block runs more than once. */
export function canPerRound(section: Pick<PlanSection, "flow" | "params" | "blocks">, b: number): boolean {
  return FLOWS[section.flow].layout !== "grid" && b >= 0 && occurrences(section, b).list.length > 1;
}

/** The section's flow writes values per column for this row (sets flow, or per-round on). */
export function usesCells(section: Pick<PlanSection, "flow">, row: Pick<PlanRow, "perRound">): boolean {
  return FLOWS[section.flow].layout === "grid" || Boolean(row.perRound);
}
