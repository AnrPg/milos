import type { PlanCell, PlanFlow, PlanMeasure, PlanRow, PlanSection, PlanStructure, PlanUnit } from "@/lib/structured-plan/types";

import {
  CLOCK_MEASURES,
  occurrences,
  progress,
  repeatText,
  setLoads,
  structOf,
  TEXT_MEASURES,
  totalRounds,
  unitsOf,
  writtenColumns,
} from "./plan-values";

/**
 * ADR-270: what the read-only WOD view shows for one plan section, in the
 * compact notation coaches write on a whiteboard: per-set values as
 * «12-10-8-8», a spread load as «60→80%», tempo as «↓3 ·1 ↑X ·1». Every word
 * comes from `t` (the `PlanView` messages), so the same model renders the
 * view and the plain text a plan becomes when a coach switches to free text.
 */

export type Translate = (key: string, values?: Record<string, string | number>) => string;

export type PlanViewRow = {
  id: string;
  kind: PlanRow["kind"];
  name: string;
  perSide: boolean;
  /** Reps / quantity (or the rest time of a rest row), compact over the sets or rounds. */
  dose: string;
  load: string;
  /** Added measures, each already labelled («Tempo ↓3 ·1 ↑X ·1», «RPE 8»). */
  measures: string[];
  note: string;
};

export type PlanViewUnit = { key: string; structure: string | null; rows: PlanViewRow[] };
export type PlanViewBlock = { key: string; label: string | null; units: PlanViewUnit[] };

export type PlanViewSection = {
  flow: string;
  preset: string | null;
  params: string;
  blocks: PlanViewBlock[];
  interrupt: { label: string; units: PlanViewUnit[] } | null;
  score: string | null;
  note: string;
  levelNotes: Array<{ level: string; label: string; note: string }>;
};

export const PLAN_FLOWS: PlanFlow[] = ["sets", "for_time", "amrap", "emom", "intervals", "rest"];
const PRESET_KEYS = new Set([
  "tabata",
  "billat",
  "hrr",
  "death_by",
  "even_odd",
  "complex_emom",
  "edt",
  "chipper",
  "21_15_9",
  "ladder",
  "kcal_target",
  "to_failure",
  "superset",
  "cluster",
  "drop",
  "restpause",
  "interrupt",
]);
const SCORE_KEYS = new Set(["load", "reps", "time", "rounds_reps", "done", "total_reps", "lowest_round", "distance"]);

// ── time ───────────────────────────────────────────────────────────────

/**
 * Seconds of a typed time: «2:00», «90″», «90s», «3'», or a bare number read
 * as minutes (`min`), seconds (`sec`), or minutes up to 10 and seconds above
 * (`smart`: «rest 2» vs «rest 90»). Null when it does not read.
 */
export function parseClock(text: string | undefined, bare: "min" | "sec" | "smart"): number | null {
  const value = (text ?? "").trim().toLowerCase();
  if (!value) return null;
  let match = /^(\d+):(\d{2})$/.exec(value);
  if (match) return Number(match[1]) * 60 + Number(match[2]);
  match = /^(\d+)\s*(s|sec|″|"|δ|δευτ\.?)$/.exec(value);
  if (match) return Number(match[1]);
  match = /^(\d+)\s*(min|'|′|λ|λεπτά)$/.exec(value);
  if (match) return Number(match[1]) * 60;
  match = /^(\d+)$/.exec(value);
  if (match) {
    const number = Number(match[1]);
    return bare === "min" || (bare === "smart" && number <= 10) ? number * 60 : number;
  }
  return null;
}

/** A duration the calm way: «45″», «12′», «2:30». */
export function showDuration(seconds: number): string {
  if (seconds < 60) return `${seconds}″`;
  if (seconds % 60 === 0) return `${seconds / 60}′`;
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

/** A typed time shown nicely, or as typed when it does not read. Ranges («90-120″») stay ranges. */
export function showTime(text: string | undefined, bare: "min" | "sec" | "smart"): string {
  const value = (text ?? "").trim();
  if (!value) return "";
  const seconds = parseClock(value, bare);
  if (seconds !== null) return showDuration(seconds);
  const unit = /\s*(s|sec|″|"|δ|min|'|′|λ)$/i.exec(value);
  const parts = value.split(/\s*[-–]\s*/).map((part) => (unit && /^\d+$/.test(part) ? part + unit[1] : part));
  if (parts.length === 2) {
    const [a, b] = parts.map((part) => parseClock(part, bare));
    if (a != null && b != null) return `${showDuration(a)}–${showDuration(b)}`;
  }
  return value;
}

// ── compact WOD notation ───────────────────────────────────────────────

const TEMPO = /^([0-9xX])-?([0-9xX])-?([0-9xX])-?([0-9xX])$/;

/** Tempo «31X1» as «↓3 ·1 ↑X ·1»: down, pause at the bottom, up (X = explosive), pause at the top. */
export function tempoShort(text: string): string {
  const match = TEMPO.exec(text.trim());
  return match ? `↓${match[1]} ·${match[2]} ↑${match[3]!.toUpperCase()} ·${match[4]}` : text.trim();
}

/**
 * Values of every set / round in one short string: the same value once,
 * otherwise «12-10-8-8» with a shared unit written once («60-65-70 kg»);
 * values that are ranges or words are joined with « / ». `more` adds «…»
 * (an AMRAP that keeps going).
 */
export function compactValues(values: string[], more = false): string {
  const trimmed = values.map((value) => value.trim());
  if (trimmed.every((value) => !value)) return "";
  const ellipsis = more ? "…" : "";
  if (trimmed.every((value) => value === trimmed[0])) return trimmed[0] + ellipsis;
  const parts = trimmed.map((value) => /^(\d+(?:[.:]\d+)?)(.*)$/.exec(value));
  const suffix = parts[0]?.[2] ?? "";
  if (parts.every((part) => part && part[2] === suffix) && !/^\s*[-–]/.test(suffix)) {
    return parts.map((part) => part![1]).join("-") + suffix + ellipsis;
  }
  return trimmed.map((value) => value || "—").join(" / ") + ellipsis;
}

// ── rows ───────────────────────────────────────────────────────────────

/** `open`: an AMRAP row per round, which keeps going after the last written round. */
type Columns = { row: PlanRow; n: number; open: boolean };

/** The columns a row is read over: its sets or rounds, or one column of same-every-time values. */
function columnsOf(section: PlanSection, row: PlanRow, block: number): Columns {
  const perColumn = section.flow === "sets" || row.perRound;
  if (!perColumn) {
    const cell: PlanCell = { d: row.dose, l: row.load, ...(row.x ?? {}) };
    return { row: { ...row, cells: [cell] }, n: 1, open: false };
  }
  if (block < 0) return { row, n: Math.max(1, writtenColumns(row)), open: false };
  const { list, open } = occurrences(section, block);
  // AMRAP: the rounds written; «…» follows when the last value keeps changing.
  return open ? { row, n: Math.max(1, writtenColumns(row)), open } : { row, n: list.length, open };
}

function keepsChanging(values: (n: number) => string[], n: number): boolean {
  const next = values(n + 1);
  return next.length > 1 && next[n] !== next[n - 1];
}

function loadText(columns: Columns): string {
  const { row, n } = columns;
  const first = String(row.cells[0]?.l ?? "").trim();
  const spread = /^(\d+(?:[.,]\d+)?)\s*(%|kg)?\s*(?:→|->)\s*(\d+(?:[.,]\d+)?)\s*(%|kg)?$/i.exec(first);
  const loads = setLoads(row, n);
  if (spread && n > 1 && row.cells.slice(1, n).every((cell) => !String(cell?.l ?? "").trim())) {
    const unit = loads.unit === "%" ? "%" : " kg";
    return `${spread[1]}→${spread[3]}${unit}`;
  }
  return compactValues(loads.values, columns.open && keepsChanging((count) => setLoads(row, count).values, n));
}

const MEASURE_UNIT: Partial<Record<PlanMeasure, (value: string) => string>> = {
  pace: (value) => (/\/|km/.test(value) ? "" : "/500m"),
  height: (value) => (/cm|m|″|'/.test(value) ? "" : " cm"),
  dist: (value) => (/m/.test(value) ? "" : " m"),
  hold: (value) => (/[s″:]/.test(value) ? "" : "″"),
};

function measureTexts(columns: Columns, t: Translate): string[] {
  const { row, n } = columns;
  return (row.extra ?? [])
    .filter((key): key is Exclude<PlanMeasure, "side"> => key !== "side")
    .flatMap((key) => {
      const values = TEXT_MEASURES.has(key) ? repeatText(row, key, n) : progress(row, key, n, CLOCK_MEASURES.has(key));
      const shown = key === "tempo" ? values.map(tempoShort) : key === "zone" ? values.map((value) => value.replace(/^(z|zone|ζώνη|ζωνη)\s*/i, "")) : values;
      const compact = compactValues(shown);
      if (!compact) return [];
      return [t(`measure.${key}`, { value: compact + (MEASURE_UNIT[key]?.(compact) ?? "") })];
    });
}

function viewRow(section: PlanSection, row: PlanRow, block: number, t: Translate): PlanViewRow {
  const columns = columnsOf(section, row, block);
  const doseValues = progress(columns.row, "d", columns.n);
  const doseMore = columns.open && keepsChanging((count) => progress(columns.row, "d", count), columns.n);
  const dose = compactValues(row.kind === "rest" ? doseValues.map((value) => showTime(value, "sec")) : doseValues, doseMore);
  return {
    id: row.id,
    kind: row.kind,
    name: row.kind === "rest" ? t("rest") : row.name.trim(),
    perSide: (row.extra ?? []).includes("side"),
    dose,
    load: row.kind === "rest" ? "" : loadText(columns),
    measures: row.kind === "rest" ? [] : measureTexts(columns, t),
    note: (row.note ?? "").trim(),
  };
}

/** The structure header of a unit; null for one plain exercise. */
export function structureText(structure: PlanStructure, t: Translate): string | null {
  switch (structure.kind) {
    case "single":
      return null;
    case "superset":
    case "complex":
      return t(`struct.${structure.kind}`);
    case "cluster":
      return t("struct.cluster", { clusters: structure.clusters || "?", intra: showTime(structure.intra, "sec") || "?" });
    case "drop":
      return t("struct.drop", { drops: structure.drops || "?", dropby: structure.dropby || "?" });
    case "restpause":
      return t("struct.restpause", { minis: structure.minis || "?", intra: showTime(structure.intra, "sec") || "?" });
  }
}

function viewUnits(section: PlanSection, rows: PlanRow[], block: number, t: Translate): PlanViewUnit[] {
  return unitsOf(rows)
    .map((unit: PlanUnit) => ({
      key: unit.group ?? unit.rows[0]!.id,
      structure: block < 0 && unit.rows.length === 1 ? null : structureText(structOf(section, unit), t),
      rows: unit.rows
        .filter((row) => row.kind === "rest" || row.name.trim() || row.dose.trim() || row.cells.some((cell) => cell.d?.trim()))
        .map((row) => viewRow(section, row, block, t)),
    }))
    .filter((unit) => unit.rows.length > 0);
}

// ── section ────────────────────────────────────────────────────────────

/** «Γύρος 1, 3, …»: which rounds (sets, slots) one kind of round runs in. Null with one kind. */
export function blockLabel(section: PlanSection, block: number, t: Translate): string | null {
  if (section.blocks.length < 2) return null;
  const { list, open } = occurrences(section, block);
  const every = section.flow === "emom" ? parseClock(section.params.every, "smart") : null;
  const word =
    section.flow === "sets"
      ? "set"
      : section.flow === "emom"
        ? every === 60
          ? "minute"
          : "interval"
        : section.flow === "intervals"
          ? "interval"
          : "round";
  const total = totalRounds(section);
  if (section.blocks.length >= total && list.length === 1) return t(`roundWord.${word}`, { numbers: String(list[0]) });
  const numbers = list.slice(0, 3).join(", ") + (open || list.length > 3 ? ", …" : "");
  return t(`roundWord.${word}`, { numbers });
}

/** The flow's parameters in one line: «4 σετ · 2′ ξεκούραση», «κάθε 1′ × 10». */
export function paramsLine(section: PlanSection, t: Translate): string {
  const p = section.params;
  const parts: string[] = [];
  switch (section.flow) {
    case "sets":
      if (p.sets?.trim()) parts.push(t("params.sets", { sets: p.sets.trim() }));
      if (p.rest?.trim()) parts.push(t("params.rest", { time: showTime(p.rest, "smart") }));
      break;
    case "for_time": {
      const rounds = Number((p.rounds ?? "").trim());
      if (rounds > 1) parts.push(t("params.rounds", { rounds }));
      if (p.cap?.trim()) parts.push(t("params.cap", { time: showTime(p.cap, "min") }));
      break;
    }
    case "amrap": {
      const windows = (p.dur ?? "").split(/\s*[-–,]\s*/).filter(Boolean);
      if (windows.length > 1) {
        parts.push(t("params.windows", { count: windows.length, times: windows.map((window) => showTime(window, "min")).join(" · ") }));
        if (p.rest?.trim()) parts.push(t("params.restBetween", { time: showTime(p.rest, "smart") }));
      } else if (windows[0]) {
        parts.push(showTime(windows[0], "min"));
      }
      break;
    }
    case "emom":
      parts.push(t("params.every", { time: showTime(p.every, "smart") || "?" }));
      parts.push(p.times?.trim() ? t("params.times", { count: p.times.trim() }) : t("params.untilFailure"));
      break;
    case "intervals": {
      const rounds = p.rounds?.trim() || "?";
      const work = showTime(p.work, "sec") || "?";
      parts.push(
        section.mods?.hr
          ? t("params.intervalsHr", { rounds, work, bpm: p.hrTarget?.trim() || "?" })
          : t("params.intervals", { rounds, work, off: showTime(p.off, "sec") || "?" }),
      );
      break;
    }
    case "rest":
      if (p.dur?.trim()) parts.push(showTime(p.dur, "smart"));
      break;
  }
  return parts.join(" · ");
}

const levelLabelOf = (key: string, labels?: Record<string, string>) => labels?.[key] ?? (key ? key[0]!.toUpperCase() + key.slice(1) : key);

export function buildPlanView(plan: PlanSection, t: Translate, levelLabels?: Record<string, string>): PlanViewSection {
  const flow = PLAN_FLOWS.includes(plan.flow) ? plan.flow : "sets";
  const preset = plan.preset && PRESET_KEYS.has(plan.preset) ? t(`preset.${plan.preset}`) : null;
  const blocks =
    flow === "rest"
      ? []
      : plan.blocks
          .map((rows, block) => ({ key: `block-${block}`, label: blockLabel(plan, block, t), units: viewUnits(plan, rows, block, t) }))
          .filter((block) => block.units.length > 0);
  const interruptUnits = plan.mods?.interrupt ? viewUnits(plan, plan.interrupt ?? [], -1, t) : [];
  return {
    flow: t(`flow.${flow}`),
    preset,
    params: paramsLine(plan, t),
    blocks,
    interrupt:
      plan.mods?.interrupt && interruptUnits.length > 0
        ? { label: t("interruptEvery", { time: showTime(plan.params.intEvery, "smart") || "?" }), units: interruptUnits }
        : null,
    score: SCORE_KEYS.has(plan.score) ? t("scoreLine", { score: t(`score.${plan.score}`) }) : null,
    note: (plan.note ?? "").trim(),
    levelNotes: Object.entries(plan.levelNotes ?? {})
      .filter(([, note]) => note.trim())
      .map(([level, note]) => ({ level, label: levelLabelOf(level, levelLabels), note: note.trim() })),
  };
}

/** One row as one line: «Back Squat (ανά πλευρά) 12-10-8-8 @ 60→80% · Tempo ↓3 ·1 ↑X ·1». */
export function rowLine(row: PlanViewRow, t: Translate): string {
  const name = row.perSide ? `${row.name} (${t("perSide")})` : row.name;
  const values = [row.dose, row.load ? `@ ${row.load}` : ""].filter(Boolean).join(" ");
  return [[name, values].filter(Boolean).join(" "), ...row.measures].join(" · ");
}

/**
 * A plan section as plain text a coach can keep editing (used when a
 * structured workout is switched back to free text): nothing written is lost.
 */
export function planSectionText(name: string, plan: PlanSection, t: Translate, levelLabels?: Record<string, string>): string {
  const view = buildPlanView(plan, t, levelLabels);
  const lines: string[] = [];
  const heading = [name.trim(), view.flow, view.preset ? `(${view.preset})` : ""].filter(Boolean).join(" · ");
  lines.push(heading);
  if (view.params) lines.push(view.params);
  const unitLines = (units: PlanViewUnit[], indent: string) => {
    for (const unit of units) {
      if (unit.structure) lines.push(`${indent}${unit.structure}:`);
      for (const row of unit.rows) {
        lines.push(`${indent}${unit.structure ? "  " : ""}${rowLine(row, t)}`);
        if (row.note) lines.push(`${indent}${unit.structure ? "    " : "  "}${row.note}`);
      }
    }
  };
  for (const block of view.blocks) {
    if (block.label) lines.push(`${block.label}:`);
    unitLines(block.units, block.label ? "  " : "");
  }
  if (view.interrupt) {
    lines.push(`${view.interrupt.label}:`);
    unitLines(view.interrupt.units, "  ");
  }
  if (view.score) lines.push(view.score);
  if (view.note) lines.push(view.note);
  for (const level of view.levelNotes) lines.push(`${level.label}: ${level.note}`);
  return lines.join("\n");
}
