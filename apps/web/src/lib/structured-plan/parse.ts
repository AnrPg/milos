/**
 * ADR-270: parsers for every value a coach types in the structured WOD
 * editor (port of `docs/product/mockups/structured-wod-parsers.js` and the
 * mockup's in-page helpers). Pure: no DOM, no React, no translated text.
 *
 * Words a coach reads (captions, hints) are returned as i18n keys under the
 * `PlanCore` namespace with their values (`PlanText`); errors are stable
 * codes (`PlanErrorCode`) the UI maps to messages. The API
 * (`Palee.Workouts.Domain.StructuredPlan`) applies the same rules.
 */
import type { PlanCell, PlanMeasure, PlanRow } from "./types";

/** A translatable piece of text: an i18n key and its ICU values. */
export type PlanText = { key: string; values?: Record<string, string | number> };

/** The word for one column of a section: a set (Σετ), a round (Γύρος) or an interval (Διάστημα). */
export type RoundWord = "set" | "round" | "interval";

/** Error codes shared with the API (messages: `PlanCore.error.<code>`). */
export const PLAN_ERROR_CODES = [
  "bad_dose",
  "missing_unit",
  "mixed_unit",
  "bad_tempo",
  "bad_measure_value",
  "rpe_over_max",
  "bad_param",
  "unknown_param",
  "unknown_flow",
  "unknown_measure",
  "duplicate_measure",
  "unknown_struct",
  "struct_not_allowed",
  "bad_struct_param",
  "mod_not_allowed",
  "unknown_score",
  "bad_version",
  "bad_row_kind",
  "duplicate_id",
  "blocks_not_allowed",
  "too_many_blocks",
  "too_many_rows",
  "too_many_cells",
  "too_long",
  "note_too_long",
] as const;
export type PlanErrorCode = (typeof PLAN_ERROR_CODES)[number];

// ── clock formatting ───────────────────────────────────────────────────────

/** "1:30" from 90 seconds, "45″" below a minute (the mockup's `clock`). */
export const clock = (secs: number): string =>
  secs >= 60 ? `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, "0")}` : `${secs}″`;

/** Always "m:ss" ("0:45", "2:30"). */
export const mmss = (secs: number): string => `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, "0")}`;

/** A number with at most two decimals, no trailing zeros ("22.5", "60"). */
export const numStr = (n: number): string => String(Math.round(n * 100) / 100);

/**
 * Seconds in words for a sentence ("2 λεπτά 30 δευτ."): `PlanCore.human.min`
 * {min}, `.sec` {sec} or `.minSec` {min, sec}.
 */
export function human(secs: number): PlanText {
  const min = Math.floor(secs / 60);
  const sec = secs % 60;
  if (!min) return { key: "PlanCore.human.sec", values: { sec } };
  if (!sec) return { key: "PlanCore.human.min", values: { min } };
  return { key: "PlanCore.human.minSec", values: { min, sec } };
}

// ── time fields ────────────────────────────────────────────────────────────

/**
 * Reads one duration in seconds: "1:30", "90s", "90″", "2′", "2min", "2λ".
 * A bare number means minutes with `"min"`; with `"smart"` it means minutes
 * up to 10 and seconds above ("rest 2" vs "rest 90"). Empty → `null`,
 * unreadable → `"bad"`.
 */
export function parseClock(text: string, dflt: "min" | "smart" = "min"): number | null | "bad" {
  const v = text.trim().toLowerCase();
  if (!v) return null;
  let m = /^(\d+):(\d{2})$/.exec(v);
  if (m) return +m[1] * 60 + +m[2];
  m = /^(\d+)\s*(s|sec|″|"|δ)$/.exec(v);
  if (m) return +m[1];
  m = /^(\d+)\s*(min|'|′|λ|λεπτά)$/.exec(v);
  if (m) return +m[1] * 60;
  m = /^(\d+)$/.exec(v);
  if (m) return dflt === "min" || +m[1] <= 10 ? +m[1] * 60 : +m[1];
  return "bad";
}

export type ParsedTimes = { range: boolean; secs: number[] };

/**
 * Several durations: AMRAP windows "3-3-3-4" / "3'-3'-3'-4'", or a range
 * "90-120″" (two ascending values without a comma). A trailing unit applies
 * to every bare number. Every part must be a positive duration.
 */
export function parseTimes(text: string, dflt: "min" | "smart" = "min"): ParsedTimes | null | "bad" {
  const v = text.trim().toLowerCase();
  if (!v) return null;
  const um = /\s*(s|sec|″|"|δ|min|'|′|λ)$/.exec(v);
  const parts = v.split(/\s*[-–,]\s*/).map((p) => (um && /^\d+$/.test(p) ? p + um[1] : p));
  const secs = parts.map((p) => parseClock(p, dflt));
  if (secs.some((x) => x === "bad" || x === null || x <= 0)) return "bad";
  const nums = secs as number[];
  const range = nums.length === 2 && !v.includes(",") && nums[0] < nums[1];
  return { range, secs: nums };
}

/** "1:30–2:00" for a range, "3:00 · 3:00 · 4:00" for windows. */
export const showTimes = (p: ParsedTimes | null | "bad"): string =>
  !p || p === "bad" ? "" : p.range ? `${clock(p.secs[0])}–${clock(p.secs[1])}` : p.secs.map(clock).join(" · ");

// ── dose notation ──────────────────────────────────────────────────────────

/** One value or a range the athlete picks from ("8-10"). */
export type NumEntry = { min: number; max: number };
/** Values per set; `cont` = the last step keeps going ("5-10-15…"). */
export type ParsedNums = { entries: NumEntry[]; cont: boolean };

const NUM = "(\\d+(?:\\.\\d+)?(?::\\d{2})?)";
const toNum = (t: string): number => {
  if (!t.includes(":")) return +t;
  const [a, b] = t.split(":");
  return +a * 60 + +b;
};

/**
 * A list of numbers: "12-10-8-8" (per set), "8-12" (two ascending = range),
 * "8-10, 6-8" (commas separate sets, dashes inside are ranges), "8 έως 12",
 * "5-10-15…" / "5-10-15+" (keeps going).
 */
export function parseNums(text: string): ParsedNums | "bad" {
  let v = text;
  let cont = false;
  if (/(…|\.\.\.|\+)$/.test(v)) {
    cont = true;
    v = v.replace(/(…|\.\.\.|\+)$/, "").trim();
  }
  const words = new RegExp(`^${NUM}\\s*(?:έως|εως|to|~)\\s*${NUM}$`).exec(v);
  if (words) return { entries: [{ min: toNum(words[1]), max: toNum(words[2]) }], cont: false };
  if (v.includes(",")) {
    const one = new RegExp(`^${NUM}(?:\\s*(?:[-–]|έως|εως|to)\\s*${NUM})?$`);
    const sets = v.split(/\s*,\s*/).map((p) => {
      const r = one.exec(p);
      return r ? { min: toNum(r[1]), max: toNum(r[2] || r[1]) } : null;
    });
    if (sets.some((e) => !e || e.max < e.min) || (cont && sets.length < 2)) return "bad";
    return { entries: sets as NumEntry[], cont };
  }
  const parts = v.split(/\s*[-–,]\s*/);
  const whole = new RegExp(`^${NUM}$`);
  if (!parts.every((p) => whole.test(p))) return "bad";
  const nums = parts.map(toNum);
  if (cont && nums.length < 2) return "bad";
  if (nums.length === 2 && nums[0] < nums[1] && !cont) return { entries: [{ min: nums[0], max: nums[1] }], cont };
  return { entries: nums.map((n) => ({ min: n, max: n })), cont };
}

/** What a dose counts. */
export type DoseUnit = "reps" | "kcal" | "m" | "secs";

export type ParsedDose = {
  /** "4×10", "3-4 sets x 12": sets written inside the dose. */
  sets: NumEntry | null;
  entries: NumEntry[] | null;
  unit: DoseUnit;
  /** "/side", "each side", "ανά πλευρά". */
  perSide: boolean;
  cont: boolean;
  /** "max", "60s max cal": as many as possible, optionally within a time (seconds). */
  max: { within: number | null } | null;
};

const SIDE =
  /\s*(\/\s*(side|πλευρά|πλευρα|πλ\.?|χέρι|χερι|πόδι|ποδι)|(on\s+)?each(\s+(side|arm|leg))?|for each arm|ανά πλευρά|ανα πλευρα|ανά χέρι|ανα χερι|ανά πόδι|ανα ποδι)$/;
const UNIT = /\s*(reps|r|επ\.?|cal|kcal|θερμ\.?|km|m|sec|s|″|"|δ|min|'|′|λ)$/;

/**
 * Reps or quantity: "10", "4×10", "12-10-8-8", "8-10", "3-4×12-15",
 * "5-10-15…", "30s", "1:00", "500m", "2km", "15 cal", "max", "60s max cal",
 * "8-10 each side". Empty → `null`, unreadable → `"bad"`.
 */
export function parseDose(text: string): ParsedDose | null | "bad" {
  let v = text.trim().toLowerCase().replace(/\s+/g, " ");
  if (!v) return null;
  const out: ParsedDose = { sets: null, entries: null, unit: "reps", perSide: false, cont: false, max: null };
  const sm = SIDE.exec(v);
  if (sm) {
    out.perSide = true;
    v = v.slice(0, sm.index).trim();
  }
  const sx = /^(\d+)(?:\s*-\s*(\d+))?\s*(?:sets?|σετ)?\s*[x×χ]\s*(.*)$/.exec(v);
  if (sx) {
    out.sets = { min: +sx[1], max: +(sx[2] || sx[1]) };
    v = sx[3].trim();
    if (!out.sets.min || out.sets.max < out.sets.min) return "bad";
    if (!v) return out;
  }
  const mx = /^(?:(\S+)\s+)?(max|μέγιστ\S*)\s*(reps|cal|m)?$/.exec(v);
  if (mx) {
    const within = mx[1] ? parseClock(mx[1], "smart") : null;
    if (within === "bad") return "bad";
    out.max = { within };
    out.unit = mx[3] === "cal" ? "kcal" : mx[3] === "m" ? "m" : "reps";
    return out;
  }
  const um = UNIT.exec(v);
  let scale = 1;
  if (um) {
    const u = um[1];
    v = v.slice(0, um.index).trim();
    if (["cal", "kcal", "θερμ", "θερμ."].includes(u)) out.unit = "kcal";
    else if (u === "m") out.unit = "m";
    else if (u === "km") {
      out.unit = "m";
      scale = 1000;
    } else if (["sec", "s", "″", '"', "δ"].includes(u)) out.unit = "secs";
    else if (["min", "'", "′", "λ"].includes(u)) {
      out.unit = "secs";
      scale = 60;
    }
  }
  if (v.includes(":")) out.unit = "secs";
  const p = parseNums(v);
  if (p === "bad") return "bad";
  out.entries = p.entries.map((e) => ({ min: e.min * scale, max: e.max * scale }));
  out.cont = p.cont;
  if (out.entries.some((e) => e.min <= 0)) return "bad";
  if (out.sets && (out.entries.length > 1 || out.cont)) return "bad";
  return out;
}

export type ParsedLoad =
  | { kind: "bw" }
  | { kind: "rpe"; min: number; max: number }
  | { kind: "zone"; zone: number }
  | { kind: "pace"; per: string; secs: number }
  | { kind: "kg" | "pct"; entries: NumEntry[]; up: boolean }
  | { kind: "text"; text: string };

/**
 * Load or intensity, as written in one field: "60kg", "70%", "60-70%",
 * "60%+" / "60%↑" (start there and build up), "bw", "rpe 8", "z2",
 * "2:00/500m". Never fails: anything else is the coach's words ("βαρύ").
 */
export function parseLoad(text: string): ParsedLoad | null {
  let v = text.trim().toLowerCase().replace(/\s+/g, " ");
  if (!v) return null;
  if (["bw", "σβ", "body", "bodyweight", "σωματικό βάρος"].includes(v)) return { kind: "bw" };
  let m = /^rpe\s*(\d+(?:\.\d)?)(?:\s*-\s*(\d+(?:\.\d)?))?$/.exec(v);
  if (m) return { kind: "rpe", min: +m[1], max: +(m[2] || m[1]) };
  m = /^(?:z|zone|ζώνη|ζωνη)\s*([1-5])$/.exec(v);
  if (m) return { kind: "zone", zone: +m[1] };
  m = /^(\d+:\d{2})\s*\/\s*(500m|500|km|100m|mi)$/.exec(v);
  if (m) return { kind: "pace", per: m[2] === "500" ? "500m" : m[2], secs: toNum(m[1]) };
  let up = false;
  if (/(\+|↑)$/.test(v)) {
    up = true;
    v = v.slice(0, -1).trim();
  }
  const um = /\s*(kg|κιλά|κιλα|%)$/.exec(v);
  if (um) {
    const n = parseNums(v.slice(0, um.index).trim().replace(/(\d),(\d)$/, "$1.$2"));
    if (n !== "bad" && !n.cont) return { kind: um[1] === "%" ? "pct" : "kg", entries: n.entries, up };
  }
  return { kind: "text", text: text.trim() };
}

/** How many sets a dose implies (its own "4×", or one per listed value). */
export const setCountOf = (d: ParsedDose | null | "bad"): number =>
  !d || d === "bad" ? 1 : d.sets ? d.sets.max : d.entries ? d.entries.length : 1;

/** The dose's value for set / round `i` (0-based); "5-10-15…" keeps adding the last step. */
export function entryAt(d: ParsedDose | null | "bad", i: number): NumEntry | null {
  if (!d || d === "bad" || !d.entries) return null;
  const es = d.entries;
  if (es.length === 1) return es[0];
  if (i < es.length) return es[i];
  const last = es[es.length - 1];
  if (d.cont) {
    const step = last.min - es[es.length - 2].min;
    const n = last.min + step * (i - es.length + 1);
    return { min: n, max: n };
  }
  return last;
}

type ShowUnit = DoseUnit | "kg" | "pct";

function showOne(n: number, unit: ShowUnit): string {
  if (unit === "secs") return clock(n);
  if (unit === "kcal") return `${numStr(n)} cal`;
  if (unit === "m") return n >= 1000 && n % 100 === 0 ? `${numStr(n / 1000)} km` : `${numStr(n)} m`;
  if (unit === "kg") return `${numStr(n)} kg`;
  if (unit === "pct") return `${numStr(n)}%`;
  return numStr(n);
}

/** One value or range with its unit: "10", "8–12", "60–70%", "1:00", "400 m". */
export function showEntry(e: NumEntry | null, unit: ShowUnit): string {
  if (!e) return "";
  if (e.min === e.max) return showOne(e.min, unit);
  return unit === "reps"
    ? `${numStr(e.min)}–${numStr(e.max)}`
    : `${showOne(e.min, unit).replace(/ ?(kg|cal|m|km|%|″)$/, "")}–${showOne(e.max, unit)}`;
}

/**
 * The few words that appear inside a shown value; the UI passes them
 * translated (`PlanCore.show.*`). Defaults are English.
 */
export type ShowWords = { perSide: string; within: string; from: string; zone: string };
export const SHOW_WORDS_EN: ShowWords = { perSide: "/side", within: "in", from: "from", zone: "zone" };
/** i18n keys of `ShowWords`. */
export const SHOW_WORD_KEYS: Record<keyof ShowWords, string> = {
  perSide: "PlanCore.show.perSide",
  within: "PlanCore.show.within",
  from: "PlanCore.show.from",
  zone: "PlanCore.show.zone",
};

/** The dose as shown in set / round `i`: "10", "8–12/side", "max cal in 1:00". */
export function showDoseAt(d: ParsedDose | null | "bad", i: number, words: ShowWords = SHOW_WORDS_EN): string {
  if (!d || d === "bad") return "";
  if (d.max) {
    const unit = d.unit === "kcal" ? " cal" : d.unit === "m" ? " m" : "";
    return `max${unit}${d.max.within ? ` ${words.within} ${clock(d.max.within)}` : ""}`;
  }
  const e = entryAt(d, i);
  return e ? showEntry(e, d.unit) + (d.perSide ? words.perSide : "") : "";
}

/** The load as shown in set `i`: "60 kg", "70%", "BW", "RPE 8", "2:00/500m", "↑ from 60%". */
export function showLoadAt(l: ParsedLoad | null, i: number, words: ShowWords = SHOW_WORDS_EN): string {
  if (!l) return "";
  switch (l.kind) {
    case "bw":
      return "BW";
    case "text":
      return l.text;
    case "zone":
      return `${words.zone} ${l.zone}`;
    case "rpe":
      return l.min === l.max ? `RPE ${l.min}` : `RPE ${l.min}–${l.max}`;
    case "pace":
      return `${clock(l.secs)}/${l.per}`;
    default: {
      const e = l.entries.length === 1 ? l.entries[0] : l.entries[i] || l.entries[l.entries.length - 1];
      return l.up && l.entries.length === 1 && i > 0 ? `↑ ${words.from} ${showEntry(e, l.kind)}` : showEntry(e, l.kind);
    }
  }
}

/**
 * The meaning of a dose, as parts the UI translates and joins with " · ":
 * keys `PlanCore.caption.*`. `word` names one column ("set", "round",
 * "interval"). Unreadable → `[{ key: "PlanCore.caption.badDose" }]`.
 */
export function doseCaption(d: ParsedDose | null | "bad", word: RoundWord): PlanText[] {
  if (!d) return [];
  if (d === "bad") return [{ key: "PlanCore.caption.badDose" }];
  const out: PlanText[] = [];
  if (d.sets) {
    out.push(
      d.sets.min === d.sets.max
        ? { key: "PlanCore.caption.sets", values: { count: d.sets.min } }
        : { key: "PlanCore.caption.setsRange", values: { min: d.sets.min, max: d.sets.max } },
    );
  }
  if (d.max) {
    out.push(
      d.max.within
        ? { key: "PlanCore.caption.maxWithin", values: { unit: d.unit, within: clock(d.max.within) } }
        : { key: "PlanCore.caption.max", values: { unit: d.unit } },
    );
  } else if (d.entries && d.entries.length > 1) {
    const list = d.entries.map((e) => showEntry(e, d.unit)).join(" · ");
    if (word === "set" && !d.cont) out.push({ key: "PlanCore.caption.setList", values: { count: d.entries.length, list } });
    else out.push({ key: "PlanCore.caption.perList", values: { word, list } });
    if (d.cont) {
      const next = entryAt(d, d.entries.length);
      const step = (next?.min ?? 0) - d.entries[d.entries.length - 1].min;
      out.push({ key: "PlanCore.caption.cont", values: { step: `${step > 0 ? "+" : ""}${numStr(step)}`, word } });
    }
  } else if (d.entries) {
    const e = d.entries[0];
    if (e.min !== e.max) out.push({ key: "PlanCore.caption.range", values: { range: showEntry(e, d.unit) } });
    else if (d.unit === "reps") out.push({ key: "PlanCore.caption.reps", values: { count: e.min } });
    else out.push({ key: "PlanCore.caption.value", values: { value: showEntry(e, d.unit) } });
  }
  if (d.perSide) out.push({ key: "PlanCore.caption.perSide" });
  return out;
}

/** The meaning of a load field: keys `PlanCore.loadCaption.*`. */
export function loadCaption(l: ParsedLoad | null): PlanText | null {
  if (!l) return null;
  switch (l.kind) {
    case "bw":
      return { key: "PlanCore.loadCaption.bw" };
    case "text":
      return { key: "PlanCore.loadCaption.text" };
    case "zone":
      return { key: "PlanCore.loadCaption.zone", values: { zone: l.zone } };
    case "rpe":
      return { key: "PlanCore.loadCaption.rpe" };
    case "pace":
      return { key: "PlanCore.loadCaption.pace", values: { pace: clock(l.secs), per: l.per } };
    default: {
      const kind = l.kind;
      if (l.entries.length > 1) {
        return { key: "PlanCore.loadCaption.perSet", values: { kind, list: l.entries.map((e) => showEntry(e, kind)).join(" · ") } };
      }
      const e = l.entries[0];
      const value = showEntry(e, kind);
      if (l.up) return { key: "PlanCore.loadCaption.buildUp", values: { kind, value } };
      if (e.min !== e.max) return { key: "PlanCore.loadCaption.range", values: { kind, value } };
      return { key: "PlanCore.loadCaption.value", values: { kind, value } };
    }
  }
}

// ── values per set / round ─────────────────────────────────────────────────

type CellKey = keyof PlanCell;
const cellText = (row: Pick<PlanRow, "cells">, i: number, key: CellKey): string => row.cells[i]?.[key] ?? "";

/** A relative value (computed from the column before): "+5", "-0:05", "60→80", "60 ως 80". */
export const isRelative = (t: string): boolean => /^[+-]|→|->|ως|έως/.test(t.trim());

/** Text measures (tempo) only repeat: an empty column is the one before. */
export function repeatText(row: Pick<PlanRow, "cells">, key: CellKey, n: number): string[] {
  const out: string[] = [];
  for (let i = 0; i < n; i++) out.push(cellText(row, i, key) || out[i - 1] || "");
  return out;
}

/** Reps per column: an empty column repeats the one before. */
export const repeatDose = (row: Pick<PlanRow, "cells">, n: number): string[] => repeatText(row, "d", n);

export type LoadUnit = "kg" | "%";
export type SetLoads = {
  /** Shown value per column ("65 kg", "70%", the coach's words, or "" when unknown). */
  values: string[];
  /** Error code per column (`missing_unit`, `mixed_unit`) or null. */
  errors: (PlanErrorCode | null)[];
  /** The row's unit, written once in any column. */
  unit: LoadUnit | null;
};

const LOAD_NUM = /^([+-]?\d+(?:\.\d+)?)\s*(%|kg)?(?:\s*(?:→|->|ως|έως)\s*(\d+(?:\.\d+)?)\s*(%|kg)?)?$/;
const normLoad = (t: string) =>
  t.trim().toLowerCase().replace(",", ".").replace(/κιλ[άα]?/, "kg");

/**
 * Loads of one row over `n` columns. The unit (kg or %) is written once per
 * row; bare numbers ("70", "+5", "60→80") inherit it. A row of numbers with
 * no unit anywhere → `missing_unit`; kg and % mixed → `mixed_unit`. Empty =
 * as before (or keeps adding the last `+x`, or keeps spreading `a→b` to the
 * last column). Words ("βαρύ", "με βάρος") pass through.
 */
export function setLoads(row: Pick<PlanRow, "cells">, n: number): SetLoads {
  const values: string[] = [];
  const errors: (PlanErrorCode | null)[] = [];
  let prev: number | null = null;
  let delta: number | null = null;
  let spread: { a: number; b: number; i: number } | null = null;
  const raw = (i: number) => normLoad(cellText(row, i, "l"));
  const stated = Array.from({ length: n }, (_, i) => {
    const m = LOAD_NUM.exec(raw(i));
    return m ? ((m[4] || m[2] || null) as LoadUnit | null) : null;
  });
  const unit = stated.find((u): u is LoadUnit => Boolean(u)) ?? null;
  const fmt = (v: number) => `${Math.round(v * 10) / 10}${unit === "%" ? "%" : " kg"}`;
  for (let i = 0; i < n; i++) {
    const t = raw(i);
    const m = t ? LOAD_NUM.exec(t) : null;
    errors.push(null);
    if (!t) {
      if (spread) prev = spread.a + ((spread.b - spread.a) * (i - spread.i)) / Math.max(1, n - 1 - spread.i);
      else if (delta != null && prev != null) prev += delta;
      values.push(prev != null && unit ? fmt(prev) : values[i - 1] || "");
      continue;
    }
    if (!m) {
      prev = null;
      delta = null;
      spread = null;
      values.push(cellText(row, i, "l").trim());
      continue;
    }
    if (!unit) {
      errors[i] = "missing_unit";
      values.push("");
      continue;
    }
    if (stated[i] && stated[i] !== unit) {
      errors[i] = "mixed_unit";
      values.push("");
      continue;
    }
    const relative = /^[+-]/.test(m[1]);
    if (relative && prev != null && !m[3]) {
      delta = +m[1];
      spread = null;
      prev += delta;
      values.push(fmt(prev));
      continue;
    }
    if (m[3]) {
      prev = Math.abs(+m[1]);
      spread = { a: prev, b: +m[3], i };
      delta = null;
      values.push(fmt(prev));
      continue;
    }
    prev = Math.abs(+m[1]);
    delta = null;
    spread = null;
    values.push(fmt(prev));
  }
  return { values, errors, unit };
}

/**
 * Any numeric measure over `n` columns, with the same rules as load: empty
 * repeats (or keeps adding the last `+x`), `+x`/`-x` changes, `a→b` spreads
 * to the last column. With `isClock`, "m:ss" values count in seconds
 * (pace, hold). Text it cannot read passes through.
 */
export function progress(row: Pick<PlanRow, "cells">, measure: CellKey, n: number, isClock = false): string[] {
  const toN = (t: string) =>
    isClock && /^\d+:\d\d$/.test(t) ? t.split(":").reduce((a, x) => a * 60 + +x, 0) : +t;
  const fmtN = (v: number) =>
    isClock && v >= 60 ? `${Math.floor(v / 60)}:${String(Math.round(v % 60)).padStart(2, "0")}` : `${Math.round(v * 10) / 10}`;
  const out: string[] = [];
  let prev: number | null = null;
  let delta: number | null = null;
  let spread: { a: number; b: number; i: number } | null = null;
  let suffix = "";
  for (let i = 0; i < n; i++) {
    const t = cellText(row, i, measure).trim().replace(",", ".");
    let m: RegExpExecArray | null;
    if (!t) {
      if (spread) prev = spread.a + ((spread.b - spread.a) * (i - spread.i)) / Math.max(1, n - 1 - spread.i);
      else if (delta != null && prev != null) prev += delta;
      out.push(prev != null ? fmtN(prev) + suffix : out[i - 1] || "");
      continue;
    }
    if ((m = /^([+-])(\d+(?::\d\d)?(?:\.\d+)?)$/.exec(t)) && prev != null) {
      delta = (m[1] === "-" ? -1 : 1) * toN(m[2]);
      spread = null;
      prev += delta;
      out.push(fmtN(prev) + suffix);
      continue;
    }
    if ((m = /^(\d+(?::\d\d)?(?:\.\d+)?)\s*(?:→|->)\s*(\d+(?::\d\d)?(?:\.\d+)?)(.*)$/.exec(t))) {
      prev = toN(m[1]);
      spread = { a: prev, b: toN(m[2]), i };
      delta = null;
      suffix = m[3];
      out.push(fmtN(prev) + suffix);
      continue;
    }
    if ((m = /^(\d+(?::\d\d)?(?:\.\d+)?)(.*)$/.exec(t))) {
      prev = toN(m[1]);
      suffix = m[2];
      delta = null;
      spread = null;
      out.push(t);
      continue;
    }
    prev = null;
    delta = null;
    spread = null;
    out.push(t);
  }
  return out;
}

// ── tempo ──────────────────────────────────────────────────────────────────

/** Four marks: seconds down · pause at the bottom · up (X = explosive) · pause at the top. */
export const TEMPO = /^([0-9xX])-?([0-9xX])-?([0-9xX])-?([0-9xX])$/;

/** One tempo mark: seconds, or "X" (explosive). */
export type TempoMark = number | "X";
export type TempoParts = { down: TempoMark; bottom: TempoMark; up: TempoMark; top: TempoMark };

/** "31X1" → { down: 3, bottom: 1, up: "X", top: 1 }; anything else → null. */
export function tempoParts(text: string): TempoParts | null {
  const m = TEMPO.exec(text.trim());
  if (!m) return null;
  const mark = (c: string): TempoMark => (/x/i.test(c) ? "X" : +c);
  return { down: mark(m[1]), bottom: mark(m[2]), up: mark(m[3]), top: mark(m[4]) };
}

/** "31X1" → "↓3 ·1 ↑X ·1" (the WOD text view). */
export const tempoShort = (text: string): string | null => {
  const m = TEMPO.exec(text.trim());
  return m ? `↓${m[1].toUpperCase()} ·${m[2].toUpperCase()} ↑${m[3].toUpperCase()} ·${m[4].toUpperCase()}` : null;
};

/**
 * Tempo in words as parts (`PlanCore.tempo.*`): down / bottom / up / top,
 * each with `{ secs }` or the `explosive` variant for X.
 */
export function tempoText(text: string): PlanText[] | null {
  const p = tempoParts(text);
  if (!p) return null;
  return (["down", "bottom", "up", "top"] as const).map((k) =>
    p[k] === "X" ? { key: `PlanCore.tempo.${k}Explosive` } : { key: `PlanCore.tempo.${k}`, values: { secs: p[k] } },
  );
}

/** Measure keys a cell can hold (every measure but the `side` flag). */
export type CellMeasure = Exclude<PlanMeasure, "side">;
