/**
 * ADR-270: parsers for every value a coach types in the structured WOD
 * editor (port of `docs/product/mockups/structured-wod-parsers.js` and the
 * mockup's in-page helpers, hardened). Pure: no DOM, no React, no
 * translated text. The full notation is in
 * `docs/product/structured-wod-notation.md`; in short:
 *
 * Normalisation (`normText`, before any rule): trimmed, lower case, Greek
 * accents removed, spaces collapsed; every dash (‐ ‒ – — ― −) is "-";
 * minute marks ' ’ ‘ ′ are "′"; second marks " “ ” ″ '' ′′ are "″";
 * "..." is "…"; "->" and "=>" are "→".
 *
 * Numbers: whole or decimal with "." ("22.5"), or "," followed by exactly
 * one digit ("22,5"); "m:ss" is a time.
 *
 * Ambiguity rules (the reading wins; `ambiguous` names the other one):
 *  - two ascending values joined by "-" ("10-12") are a range the athlete
 *    picks from; for two sets write "10, 12";
 *  - descending or equal values ("12-10-8-8", "21-15-9", "8-8") are a list,
 *    one per set / round, the last repeating;
 *  - three or more values rising by the same step ("5-10-15") are a list;
 *    to keep climbing after the last, write "5-10-15…";
 *  - AMRAP durations are windows: "3-3-3-4" four windows, "12-15" two;
 *  - a bare time in a "smart" field is minutes up to 10 and seconds above,
 *    and all bare parts of one field share the unit ("5-15" = 5″–15″).
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
  "wrong_unit",
  "no_base",
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
  "bad_shape",
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

/**
 * A reading that could have meant something else: `alt` names the other
 * reading, `write` is how to type it, `hint` the line the UI shows
 * (`PlanCore.ambiguous.*`), e.g. «εύρος 10–12 · για 2 σετ γράψε 10, 12».
 */
export type Ambiguity = { alt: "list" | "ladder" | "range" | "seconds" | "minutes"; write: string; hint: PlanText };

// ── normalisation ──────────────────────────────────────────────────────────

/**
 * The form every rule reads: trimmed, lower case, accents removed, spaces
 * collapsed, look-alike characters unified (dashes, primes, quotes,
 * ellipsis, arrows). Final sigma stays. Never throws.
 */
export function normText(text: unknown): string {
  if (typeof text !== "string") return "";
  return text
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[‐-―−﹘﹣－]/g, "-")
    .replace(/(?:''|′′|[“”„"])/g, "″")
    .replace(/[’‘'`´]/g, "′")
    .replace(/\.\.\./g, "…")
    .replace(/\s*(?:->|=>)\s*/g, "→")
    .replace(/\s+/g, " ")
    .trim();
}

/** "22,5" → "22.5" (a comma followed by exactly one digit is a decimal point). */
const decimalComma = (v: string) => v.replace(/(\d),(\d)(?!\d)/g, "$1.$2");

/** `normText` plus the decimal comma rule ("22,5" → "22.5"). */
export const decimalCommaNorm = (text: unknown): string => decimalComma(normText(text));

const escapeRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
/** An alternation of words, longest first, as a regex source. */
const alt = (words: string[]) => [...words].sort((a, b) => b.length - a.length).map(escapeRe).join("|");

/** Unit words (normalised: lower case, no accents). */
export const UNIT_WORDS = {
  secs: ["s", "sec", "secs", "second", "seconds", "″", "δ", "δευτ", "δευτ.", "δευτερολεπτο", "δευτερολεπτα"],
  mins: ["min", "mins", "minute", "minutes", "′", "λ", "λ.", "λεπτ", "λεπτ.", "λεπτο", "λεπτα"],
  reps: ["reps", "rep", "r", "επαναληψεις", "επαναληψη", "επαν", "επαν.", "επ", "επ."],
  kcal: ["cal", "cals", "kcal", "calories", "θερμιδες", "θερμ", "θερμ."],
  m: ["m", "meters", "metres", "μ", "μ.", "μετρα"],
  km: ["km", "χλμ", "χλμ."],
  kg: ["kg", "kgs", "kgr", "κιλα", "κιλο", "κ", "κ."],
  pct: ["%"],
} as const;

const SEC_RE = alt([...UNIT_WORDS.secs]);
const MIN_RE = alt([...UNIT_WORDS.mins]);
const KG_RE = alt([...UNIT_WORDS.kg]);

// ── clock formatting ───────────────────────────────────────────────────────

/** "1:30" from 90 seconds, "45″" below a minute (the mockup's `clock`). */
export const clock = (secs: number): string =>
  secs >= 60 ? `${Math.floor(secs / 60)}:${String(Math.round(secs % 60)).padStart(2, "0")}` : `${numStr(secs)}″`;

/** Always "m:ss" ("0:45", "2:30"). */
export const mmss = (secs: number): string => `${Math.floor(secs / 60)}:${String(Math.round(secs % 60)).padStart(2, "0")}`;

/** A number with at most two decimals, no trailing zeros ("22.5", "60"). */
export const numStr = (n: number): string => String(Math.round(n * 100) / 100);

/**
 * Seconds in words for a sentence ("2 λεπτά 30 δευτ."): `PlanCore.human.min`
 * {min}, `.sec` {sec} or `.minSec` {min, sec}.
 */
export function human(secs: number): PlanText {
  const min = Math.floor(secs / 60);
  const sec = Math.round(secs % 60);
  if (!min) return { key: "PlanCore.human.sec", values: { sec } };
  if (!sec) return { key: "PlanCore.human.min", values: { min } };
  return { key: "PlanCore.human.minSec", values: { min, sec } };
}

// ── time fields ────────────────────────────────────────────────────────────

const CLOCK_MSS = /^(\d+):([0-5]\d)$/;

/** One duration in normalised text, with how a bare number was read. */
function readClock(v: string, dflt: "min" | "smart"): { secs: number; assumed: "min" | "sec" | null } | "bad" {
  let m = CLOCK_MSS.exec(v);
  if (m) return { secs: +m[1] * 60 + +m[2], assumed: null };
  m = new RegExp(`^(\\d+)\\s*(?:${MIN_RE})\\s*(\\d+)\\s*(?:${SEC_RE})?$`).exec(v);
  if (m && +m[2] < 60) return { secs: +m[1] * 60 + +m[2], assumed: null };
  m = new RegExp(`^(\\d+(?:\\.\\d+)?)\\s*(?:${SEC_RE})$`).exec(v);
  if (m) return { secs: Math.round(+m[1]), assumed: null };
  m = new RegExp(`^(\\d+(?:\\.\\d+)?)\\s*(?:${MIN_RE})$`).exec(v);
  if (m) return { secs: Math.round(+m[1] * 60), assumed: null };
  m = /^(\d+)$/.exec(v);
  if (m) return dflt === "min" || +m[1] <= 10 ? { secs: +m[1] * 60, assumed: "min" } : { secs: +m[1], assumed: "sec" };
  return "bad";
}

/**
 * Reads one duration in seconds: "1:30", "90s", "90″", "90 δευτ.", "2′",
 * "2min", "2 λεπτά", "1.5 min", "2′30″". A bare number means minutes with
 * `"min"`; with `"smart"` it means minutes up to 10 and seconds above
 * ("rest 2" vs "rest 90"). "m:ss" needs seconds below 60. Empty → `null`,
 * unreadable → `"bad"`.
 */
export function parseClock(text: string, dflt: "min" | "smart" = "min"): number | null | "bad" {
  const v = decimalComma(normText(text));
  if (!v) return null;
  const r = readClock(v, dflt);
  return r === "bad" ? "bad" : r.secs;
}

/**
 * How a bare number in a time field was read, with the other reading
 * (`PlanCore.ambiguous.clock` {reading, write}): "10" in a smart field is
 * 10 minutes, "write 10″ for seconds". Null when the unit is written.
 */
export function clockAmbiguity(text: string, dflt: "min" | "smart" = "min"): Ambiguity | null {
  const v = normText(text);
  const r = v ? readClock(v, dflt) : "bad";
  if (r === "bad" || !r.assumed) return null;
  const n = +v;
  return r.assumed === "min"
    ? { alt: "seconds", write: `${n}″`, hint: { key: "PlanCore.ambiguous.clock", values: { reading: clock(r.secs), write: `${n}″` } } }
    : { alt: "minutes", write: `${n}′`, hint: { key: "PlanCore.ambiguous.clock", values: { reading: clock(r.secs), write: `${n}′` } } };
}

export type ParsedTimes = { range: boolean; secs: number[] };

/**
 * Several durations: AMRAP windows "3-3-3-4" / "3′-3′-3′-4′" / "3, 3, 3, 4"
 * / "3/3/3/4", or a range "90-120″" (two ascending values joined by "-").
 * A trailing unit applies to every bare part; with `"smart"`, bare parts
 * share one unit (seconds if any is above 10). Every part must be positive.
 */
export function parseTimes(text: string, dflt: "min" | "smart" = "min"): ParsedTimes | null | "bad" {
  const v = decimalComma(normText(text));
  if (!v) return null;
  const um = new RegExp(`\\s*(${SEC_RE}|${MIN_RE})$`).exec(v);
  const raw = v.split(/\s*[-,/]\s*/);
  if (raw.some((p) => !p)) return "bad";
  const bare = raw.filter((p) => /^\d+$/.test(p)).map(Number);
  const shared = !um && dflt === "smart" && bare.length > 1 ? (bare.some((n) => n > 10) ? "″" : "′") : null;
  const parts = raw.map((p) => (/^\d+$/.test(p) ? p + (um ? um[1] : shared ?? "") : p));
  const secs = parts.map((p) => readClock(p, dflt));
  if (secs.some((x) => x === "bad" || x.secs <= 0)) return "bad";
  const nums = secs.map((x) => (x as { secs: number }).secs);
  const range = nums.length === 2 && !/[,/]/.test(v) && nums[0] < nums[1];
  return { range, secs: nums };
}

/** "1:30–2:00" for a range, "3:00 · 3:00 · 4:00" for windows. */
export const showTimes = (p: ParsedTimes | null | "bad"): string =>
  !p || p === "bad" ? "" : p.range ? `${clock(p.secs[0])}–${clock(p.secs[1])}` : p.secs.map(clock).join(" · ");

/**
 * A whole positive count ("8"), or null. Spaces are ignored.
 */
export function parseCount(text: unknown): number | null {
  const v = normText(text);
  return /^\d+$/.test(v) && +v > 0 ? +v : null;
}

/**
 * A count or a count range: "4", "3-4", "3 ή 4", "3 or 4", "3/4" (sets past
 * `min` are "if they can"). Null when unreadable or not ascending.
 */
export function parseCountRange(text: unknown): { min: number; max: number } | null {
  const m = /^(\d+)(?:\s*(?:-|\/|η|or|εως|to)\s*(\d+))?$/.exec(normText(text));
  if (!m) return null;
  const min = +m[1];
  const max = +(m[2] || m[1]);
  return min > 0 && max >= min ? { min, max } : null;
}

// ── number lists ───────────────────────────────────────────────────────────

/** One value or a range the athlete picks from ("8-10"). */
export type NumEntry = { min: number; max: number };
/**
 * Values per set; `cont` = the last step keeps going ("5-10-15…").
 * `ambiguous`: "10-12" read as a range could be two sets (`list`); a
 * rising list "5-10-15" could be meant to keep climbing (`ladder`).
 */
export type ParsedNums = { entries: NumEntry[]; cont: boolean; ambiguous?: "list" | "ladder" };

const NUM = "(\\d+(?:\\.\\d+)?(?::[0-5]\\d)?)";
const toNum = (t: string): number => {
  if (!t.includes(":")) return +t;
  const [a, b] = t.split(":");
  return +a * 60 + +b;
};
const RANGE_WORDS = "εως|ως|to|~";

/**
 * A list of numbers (normalised text): "12-10-8-8" (per set), "8-12" (two
 * ascending = range), "8-10, 6-8" (commas separate sets, dashes inside are
 * ranges), "8 έως 12" / "8 to 12" (range), "5-10-15…" / "5-10-15+" (keeps
 * going).
 */
export function parseNums(text: string): ParsedNums | "bad" {
  let v = normText(text);
  let cont = false;
  if (/(…|\+)$/.test(v)) {
    cont = true;
    v = v.replace(/(…|\+)$/, "").trim();
  }
  if (!v) return "bad";
  const words = new RegExp(`^${NUM}\\s*(?:${RANGE_WORDS})\\s*${NUM}$`).exec(v);
  if (words) {
    const a = toNum(words[1]);
    const b = toNum(words[2]);
    return a <= b && !cont ? { entries: [{ min: a, max: b }], cont: false } : "bad";
  }
  if (v.includes(",")) {
    const one = new RegExp(`^${NUM}(?:\\s*(?:-|${RANGE_WORDS})\\s*${NUM})?$`);
    const sets = v.split(/\s*,\s*/).map((p) => {
      const r = one.exec(p);
      return r ? { min: toNum(r[1]), max: toNum(r[2] || r[1]) } : null;
    });
    if (sets.some((e) => !e || e.max < e.min) || (cont && sets.length < 2)) return "bad";
    return { entries: sets as NumEntry[], cont };
  }
  const parts = v.split(/\s*-\s*/);
  const whole = new RegExp(`^${NUM}$`);
  if (!parts.every((p) => whole.test(p))) return "bad";
  const nums = parts.map(toNum);
  if (cont && nums.length < 2) return "bad";
  if (nums.length === 2 && nums[0] < nums[1] && !cont) return { entries: [{ min: nums[0], max: nums[1] }], cont, ambiguous: "list" };
  const out: ParsedNums = { entries: nums.map((n) => ({ min: n, max: n })), cont };
  if (!cont && nums.length >= 3) {
    const step = nums[1] - nums[0];
    if (step > 0 && nums.every((n, i) => i === 0 || n - nums[i - 1] === step)) out.ambiguous = "ladder";
  }
  return out;
}

/**
 * Strips a unit written after every number ("30s-45s", "60kg-70kg",
 * "3′-3′") down to one at the end, so the list rules apply. `unitRe` is
 * the trailing unit's own text (escaped), already removed from the end.
 */
function stripRepeatedUnit(v: string, unitRe: string): string {
  return v.replace(new RegExp(`(\\d)\\s*(?:${unitRe})(?=\\s*(?:-|,|${RANGE_WORDS}|$))`, "g"), "$1");
}

// ── dose notation ──────────────────────────────────────────────────────────

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
  /** "max", "60s max cal", "max cal σε 1:00": as many as possible, optionally within a time (seconds). */
  max: { within: number | null } | null;
  /** The other reading of "10-12" (two sets) or "5-10-15" (keep climbing). */
  ambiguous?: Ambiguity;
};

const SIDE = new RegExp(
  `\\s*(?:\\/\\s*(?:side|leg|arm|πλευρα|πλ\\.?|χερι|ποδι)|(?:on\\s+)?each(?:\\s+(?:side|arm|leg))?|for each (?:side|arm|leg)|per (?:side|arm|leg)|e\\/s|ανα (?:πλευρα|χερι|ποδι))$`,
);
const DOSE_UNITS: [string[], DoseUnit, number][] = [
  [[...UNIT_WORDS.reps], "reps", 1],
  [[...UNIT_WORDS.kcal], "kcal", 1],
  [[...UNIT_WORDS.km], "m", 1000],
  [[...UNIT_WORDS.m], "m", 1],
  [[...UNIT_WORDS.secs], "secs", 1],
  [[...UNIT_WORDS.mins], "secs", 60],
];
const DOSE_UNIT_RE = alt(DOSE_UNITS.flatMap(([w]) => w));
const doseUnitOf = (word: string): [DoseUnit, number] => {
  const hit = DOSE_UNITS.find(([w]) => (w as string[]).includes(word));
  return hit ? [hit[1], hit[2]] : ["reps", 1];
};
const MAX_UNIT: Record<string, DoseUnit> = Object.fromEntries([
  ...UNIT_WORDS.reps.map((w) => [w, "reps"]),
  ...UNIT_WORDS.kcal.map((w) => [w, "kcal"]),
  ...UNIT_WORDS.m.map((w) => [w, "m"]),
]);

/** The canonical way to write entries ("10, 12", "60 kg, 70 kg", "30″, 45″"). */
const writeList = (es: NumEntry[], unit: DoseUnit | "kg" | "pct") => es.map((e) => showOne(e.min, unit)).join(", ");
const writeLadder = (es: NumEntry[], unit: DoseUnit | "kg" | "pct") => `${es.map((e) => numStr(e.min)).join("-")}…${unitSuffix(unit)}`;
const unitSuffix = (unit: DoseUnit | "kg" | "pct") =>
  unit === "kcal" ? " cal" : unit === "m" ? " m" : unit === "secs" ? "″" : unit === "kg" ? " kg" : unit === "pct" ? "%" : "";

function ambiguityOf(n: ParsedNums, unit: DoseUnit | "kg" | "pct"): Ambiguity | undefined {
  if (n.ambiguous === "list") {
    const e = n.entries[0];
    const pair = [
      { min: e.min, max: e.min },
      { min: e.max, max: e.max },
    ];
    const write = writeList(pair, unit);
    return { alt: "list", write, hint: { key: "PlanCore.ambiguous.rangeOrList", values: { range: showEntry(e, unit), count: 2, write } } };
  }
  if (n.ambiguous === "ladder") {
    const write = writeLadder(n.entries, unit);
    return { alt: "ladder", write, hint: { key: "PlanCore.ambiguous.listOrLadder", values: { list: n.entries.map((e) => showOne(e.min, unit)).join(" · "), write } } };
  }
  return undefined;
}

/**
 * Reps or quantity: "10", "4×10", "4 x 10", "12-10-8-8", "8-10", "8 έως 12",
 * "3-4×12-15", "5-10-15…", "30s", "30-45s", "1:00", "500m", "2km",
 * "15 cal", "max", "max reps", "max cal", "60s max cal", "max cal σε 1:00",
 * "8-10 each side", "8 ανά πόδι". Empty → `null`, unreadable → `"bad"`.
 */
export function parseDose(text: string): ParsedDose | null | "bad" {
  let v = decimalComma(normText(text));
  if (!v) return null;
  const out: ParsedDose = { sets: null, entries: null, unit: "reps", perSide: false, cont: false, max: null };
  const sm = SIDE.exec(v);
  if (sm) {
    out.perSide = true;
    v = v.slice(0, sm.index).trim();
  }
  // "4x10", "4 χ 10", "3-4 sets x 12": the x must be followed by a value (so "2 χλμ" stays 2 km)
  const sx = /^(\d+)(?:\s*-\s*(\d+))?\s*(?:sets?|σετ)?\s*[x×χ*]\s*(?=$|\d|max|amrap|μεγιστ)(.*)$/.exec(v);
  if (sx) {
    out.sets = { min: +sx[1], max: +(sx[2] || sx[1]) };
    v = sx[3].trim();
    if (!out.sets.min || out.sets.max < out.sets.min) return "bad";
    if (!v) return out;
  }
  const mx = new RegExp(`^(?:(\\S+)\\s+)?(?:max|amrap|μεγιστ\\S*)(?:\\s*(${alt(Object.keys(MAX_UNIT))}))?(?:\\s+(?:in|σε)\\s+(\\S+))?$`).exec(v);
  if (mx) {
    if (mx[1] && mx[3]) return "bad";
    const t = mx[1] || mx[3];
    const within = t ? parseClock(t, "smart") : null;
    if (within === "bad" || within === 0) return "bad";
    out.max = { within };
    out.unit = mx[2] ? MAX_UNIT[mx[2]] : "reps";
    return out;
  }
  const um = new RegExp(`\\s*(${DOSE_UNIT_RE})$`).exec(v);
  let scale = 1;
  if (um) {
    const [unit, s] = doseUnitOf(um[1]);
    out.unit = unit;
    scale = s;
    v = stripRepeatedUnit(v.slice(0, um.index).trim(), escapeRe(um[1]));
  }
  if (v.includes(":")) {
    if (um && out.unit !== "secs") return "bad";
    out.unit = "secs";
    scale = 1;
  }
  const p = parseNums(v);
  if (p === "bad") return "bad";
  out.entries = p.entries.map((e) => ({ min: e.min * scale, max: e.max * scale }));
  out.cont = p.cont;
  if (out.entries.some((e) => e.min <= 0)) return "bad";
  if (out.sets && (out.entries.length > 1 || out.cont)) return "bad";
  // with sets written ("4x8-10") a dash can only be a range
  const amb = out.sets ? undefined : ambiguityOf({ ...p, entries: out.entries }, out.unit);
  if (amb) out.ambiguous = amb;
  return out;
}

// ── load notation ──────────────────────────────────────────────────────────

export type ParsedLoad =
  | { kind: "bw" }
  | { kind: "rpe"; min: number; max: number }
  | { kind: "zone"; zone: number }
  | { kind: "pace"; per: string; secs: number }
  | { kind: "kg" | "pct"; entries: NumEntry[]; up: boolean; ambiguous?: Ambiguity }
  /** A number with a unit that is not a load ("60 km", "20 reps"). */
  | { kind: "wrong"; text: string }
  | { kind: "text"; text: string };

const LOAD_UNIT_RE = `${KG_RE}|%`;
const NOT_LOAD_UNIT = new RegExp(`^[+-]?\\d+(?:\\.\\d+)?\\s*(?:${alt([...UNIT_WORDS.km, ...UNIT_WORDS.m, ...UNIT_WORDS.kcal, ...UNIT_WORDS.reps, ...UNIT_WORDS.secs, ...UNIT_WORDS.mins])})$`);
/** Normalised load text: decimal comma, "@70%", "70% 1RM" / "του 1RM" / "of 1RM". */
const normLoadText = (text: string) =>
  decimalComma(normText(text))
    .replace(/^@\s*/, "")
    .replace(/%\s*(?:(?:του|of)\s*)?1\s*rm$/, "%");

/**
 * Load or intensity, as written in one field: "60kg", "60 κιλά", "22,5kg",
 * "70%", "70% 1RM", "60-70%", "60%+" / "60%↑" (start there and build up),
 * "bw", "rpe 8", "@8", "z2", "2:00/500m". A number with a unit that is not
 * a load ("60 km") is `wrong`. Anything else is the coach's words ("βαρύ").
 */
export function parseLoad(text: string): ParsedLoad | null {
  let v = normLoadText(text);
  if (!v) return null;
  if (["bw", "σβ", "body", "bodyweight", "body weight", "σωματικο βαρος", "βαρος σωματος"].includes(v)) return { kind: "bw" };
  let m = /^(?:rpe\s*|@\s*)(\d+(?:\.\d)?)(?:\s*-\s*(\d+(?:\.\d)?))?$/.exec(text.trim().startsWith("@") ? `@${v}` : v);
  if (m) return { kind: "rpe", min: +m[1], max: +(m[2] || m[1]) };
  m = /^(?:z|zone|ζωνη)\s*([1-5])$/.exec(v);
  if (m) return { kind: "zone", zone: +m[1] };
  m = /^(\d+:[0-5]\d)\s*\/\s*(500m|500|1km|km|100m|mi)$/.exec(v);
  if (m) return { kind: "pace", per: m[2] === "500" ? "500m" : m[2] === "1km" ? "km" : m[2], secs: toNum(m[1]) };
  if (NOT_LOAD_UNIT.test(v)) return { kind: "wrong", text: text.trim() };
  let up = false;
  if (/(\+|↑)$/.test(v)) {
    up = true;
    v = v.slice(0, -1).trim();
  }
  const um = new RegExp(`\\s*(${LOAD_UNIT_RE})$`).exec(v);
  if (um) {
    const kind = um[1] === "%" ? "pct" : "kg";
    const n = parseNums(stripRepeatedUnit(v.slice(0, um.index).trim(), escapeRe(um[1])));
    if (n !== "bad" && !n.cont) {
      const amb = up ? undefined : ambiguityOf(n, kind);
      return amb ? { kind, entries: n.entries, up, ambiguous: amb } : { kind, entries: n.entries, up };
    }
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
    : `${showOne(e.min, unit).replace(/ ?(kg|cal|km|m|%|″)$/, "")}–${showOne(e.max, unit)}`;
}

/** The canonical text of a dose (`parseDose(showDose(d))` reads the same). */
export function showDose(d: ParsedDose): string {
  const side = d.perSide ? " each side" : "";
  const sets = d.sets ? `${d.sets.min === d.sets.max ? d.sets.min : `${d.sets.min}-${d.sets.max}`}x` : "";
  if (d.max) {
    const unit = d.unit === "kcal" ? " cal" : d.unit === "m" ? " m" : "";
    return `${sets}${d.max.within ? `${d.max.within}s ` : ""}max${unit}${side}`;
  }
  if (!d.entries) return `${sets}${side}`;
  const one = (e: NumEntry) => (e.min === e.max ? numStr(e.min) : `${numStr(e.min)}-${numStr(e.max)}`);
  const es = d.entries;
  // "-" joins a list, except when it would read as a range: ranges inside, or two rising values
  const dash = es.length > 1 && es.every((e) => e.min === e.max) && !(es.length === 2 && es[0].min < es[1].min);
  const body = es.map(one).join(dash ? "-" : ", ");
  const suffix = d.unit === "kcal" ? " cal" : d.unit === "m" ? " m" : d.unit === "secs" ? "s" : "";
  return `${sets}${body}${d.cont ? "…" : ""}${suffix}${side}`;
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
    case "wrong":
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
 * keys `PlanCore.caption.*`, then the ambiguity hint if any
 * (`PlanCore.ambiguous.*`). `word` names one column ("set", "round",
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
  if (d.ambiguous) out.push(d.ambiguous.hint);
  return out;
}

/** The meaning of a load field: keys `PlanCore.loadCaption.*` (the ambiguity hint is `l.ambiguous.hint`). */
export function loadCaption(l: ParsedLoad | null): PlanText | null {
  if (!l) return null;
  switch (l.kind) {
    case "bw":
      return { key: "PlanCore.loadCaption.bw" };
    case "text":
      return { key: "PlanCore.loadCaption.text" };
    case "wrong":
      return { key: "PlanCore.error.wrong_unit" };
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
/** One cell value as typed ("" for missing cells, non-strings, junk). */
const cellText = (row: Pick<PlanRow, "cells">, i: number, key: CellKey): string => {
  const cells: unknown = row?.cells;
  if (!Array.isArray(cells)) return "";
  const c: unknown = cells[i];
  if (!c || typeof c !== "object") return "";
  const v = (c as Record<string, unknown>)[key];
  return typeof v === "string" ? v : "";
};

/** A relative value (computed from the column before): "+5", "-0:05", "60→80", "60->80", "60 ως 80". */
export const isRelative = (t: string): boolean => {
  const v = normText(t);
  return /^[+-]/.test(v) || /→|(?:^|\s|\d)(?:ως|εως)(?:\s|\d|$)/.test(v);
};

/** Text measures (tempo) only repeat: an empty column is the one before. */
export function repeatText(row: Pick<PlanRow, "cells">, key: CellKey, n: number): string[] {
  const out: string[] = [];
  for (let i = 0; i < n; i++) out.push(cellText(row, i, key).trim() || out[i - 1] || "");
  return out;
}

/** Reps per column: an empty column repeats the one before. */
export const repeatDose = (row: Pick<PlanRow, "cells">, n: number): string[] => repeatText(row, "d", n);

export type LoadUnit = "kg" | "%";
export type SetLoads = {
  /** Shown value per column ("65 kg", "70%", "60–70%", the coach's words, or "" when unknown). */
  values: string[];
  /** Error code per column (`missing_unit`, `mixed_unit`, `wrong_unit`, `no_base`) or null. */
  errors: (PlanErrorCode | null)[];
  /** The row's unit, written once in any column. */
  unit: LoadUnit | null;
};

/** One load cell, read. */
type LoadToken =
  | { t: "empty" }
  | { t: "abs"; n: number; unit: LoadUnit | null }
  | { t: "delta"; n: number; unit: LoadUnit | null }
  | { t: "up"; n: number; unit: LoadUnit | null }
  | { t: "spread"; a: number; b: number; unit: LoadUnit | null }
  | { t: "range"; a: number; b: number; unit: LoadUnit | null }
  | { t: "wrong" }
  | { t: "words"; text: string };

const LN = "(\\d+(?:\\.\\d+)?)";
const LU = `\\s*(${LOAD_UNIT_RE})?`;
const unitOfLoad = (u: string | undefined): LoadUnit | null => (!u ? null : u === "%" ? "%" : "kg");

function readLoadCell(raw: string): LoadToken {
  const v = normLoadText(raw);
  if (!v) return { t: "empty" };
  let m = new RegExp(`^([+-])${LN}${LU}$`).exec(v);
  if (m) return { t: "delta", n: (m[1] === "-" ? -1 : 1) * +m[2], unit: unitOfLoad(m[3]) };
  m = new RegExp(`^${LN}${LU}$`).exec(v);
  if (m) return { t: "abs", n: +m[1], unit: unitOfLoad(m[2]) };
  m = new RegExp(`^${LN}${LU}\\s*(?:\\+|↑)$`).exec(v);
  if (m) return { t: "up", n: +m[1], unit: unitOfLoad(m[2]) };
  m = new RegExp(`^${LN}${LU}\\s*(?:→|ως|εως)\\s*${LN}${LU}$`).exec(v);
  if (m) {
    const a = unitOfLoad(m[2]);
    const b = unitOfLoad(m[4]);
    return a && b && a !== b ? { t: "wrong" } : { t: "spread", a: +m[1], b: +m[3], unit: b || a };
  }
  m = new RegExp(`^${LN}${LU}\\s*-\\s*${LN}${LU}$`).exec(v);
  if (m && +m[1] < +m[3]) {
    const a = unitOfLoad(m[2]);
    const b = unitOfLoad(m[4]);
    return a && b && a !== b ? { t: "wrong" } : { t: "range", a: +m[1], b: +m[3], unit: b || a };
  }
  if (NOT_LOAD_UNIT.test(v)) return { t: "wrong" };
  return { t: "words", text: raw.trim() };
}

/**
 * Loads of one row over `n` columns. The unit (kg or %) is written once per
 * row; bare numbers ("70", "+5", "60→80", "60-70") inherit it. Errors:
 * numbers with no unit anywhere in the row → `missing_unit`; kg and % mixed
 * → `mixed_unit`; a unit that is not a load ("60 km") → `wrong_unit`; a
 * change ("+5") with nothing before it to change → `no_base`. Empty = as
 * before (or keeps adding the last `+x`, or keeps spreading `a→b` to the
 * last column). "60-70" is a range for the athlete in that column; "60%+"
 * / "60%↑" starts there and builds up (the columns after it show "↑ 60%"
 * until another value). Words
 * ("βαρύ", "με βάρος") pass through and reset the progression.
 */
export function setLoads(row: Pick<PlanRow, "cells">, n: number): SetLoads {
  const values: string[] = [];
  const errors: (PlanErrorCode | null)[] = [];
  const tokens = Array.from({ length: Math.max(0, n) }, (_, i) => readLoadCell(cellText(row, i, "l")));
  const stated = tokens.map((t) => ("unit" in t ? t.unit : null));
  const unit = stated.find((u): u is LoadUnit => Boolean(u)) ?? null;
  const fmt = (v: number) => `${Math.round(v * 100) / 100}${unit === "%" ? "%" : " kg"}`;
  let prev: number | null = null;
  let delta: number | null = null;
  let spread: { a: number; b: number; i: number } | null = null;
  let rising = false;
  tokens.forEach((tok, i) => {
    errors.push(null);
    const fail = (code: PlanErrorCode) => {
      errors[i] = code;
      values.push("");
      prev = null;
      delta = null;
      spread = null;
      rising = false;
    };
    if (tok.t !== "empty") rising = false;
    switch (tok.t) {
      case "empty":
        if (rising && prev != null && unit) {
          values.push(`↑ ${fmt(prev)}`);
          return;
        }
        if (spread) prev = spread.a + ((spread.b - spread.a) * (i - spread.i)) / Math.max(1, n - 1 - spread.i);
        else if (delta != null && prev != null) prev += delta;
        values.push(prev != null && unit ? fmt(prev) : values[i - 1] || "");
        return;
      case "words":
        prev = null;
        delta = null;
        spread = null;
        values.push(tok.text);
        return;
      case "wrong":
        fail("wrong_unit");
        return;
    }
    if (!unit) return fail("missing_unit");
    if (tok.unit && tok.unit !== unit) return fail("mixed_unit");
    if (tok.t === "delta") {
      if (prev == null) return fail("no_base");
      delta = tok.n;
      spread = null;
      prev += delta;
      values.push(fmt(prev));
    } else if (tok.t === "spread") {
      prev = tok.a;
      spread = { a: tok.a, b: tok.b, i };
      delta = null;
      values.push(fmt(prev));
    } else if (tok.t === "up") {
      prev = tok.n;
      delta = null;
      spread = null;
      rising = true;
      values.push(fmt(prev));
    } else if (tok.t === "range") {
      prev = null;
      delta = null;
      spread = null;
      values.push(`${numStr(tok.a)}–${fmt(tok.b)}`);
    } else {
      prev = tok.n;
      delta = null;
      spread = null;
      values.push(fmt(prev));
    }
  });
  return { values, errors, unit };
}

/** One measure cell, read: absolute, change, spread, range or text. */
function readMeasureCell(raw: string, isClock: boolean) {
  const v = decimalComma(normText(raw)).replace(/^z(?:one)?\s*(?=\d)/, "");
  const N = isClock ? "(\\d+(?::[0-5]\\d)?(?:\\.\\d+)?)" : "(\\d+(?:\\.\\d+)?)";
  const toN = (t: string) => (isClock && t.includes(":") ? t.split(":").reduce((a, x) => a * 60 + +x, 0) : +t);
  let m: RegExpExecArray | null;
  if (!v) return { t: "empty" as const };
  if ((m = new RegExp(`^([+-])${N}$`).exec(v))) return { t: "delta" as const, n: (m[1] === "-" ? -1 : 1) * toN(m[2]) };
  if ((m = new RegExp(`^${N}\\s*(?:→|ως|εως)\\s*${N}(.*)$`).exec(v))) return { t: "spread" as const, a: toN(m[1]), b: toN(m[2]), suffix: m[3] };
  if ((m = new RegExp(`^${N}\\s*-\\s*${N}(.*)$`).exec(v))) return { t: "text" as const, text: raw.trim(), numeric: true };
  if ((m = new RegExp(`^${N}(.*)$`).exec(v))) return { t: "abs" as const, n: toN(m[1]), suffix: m[2] };
  return { t: "text" as const, text: raw.trim(), numeric: false };
}

/**
 * Any numeric measure over `n` columns, with the same rules as load: empty
 * repeats (or keeps adding the last `+x`), `+x`/`-x` changes, `a→b` spreads
 * to the last column. With `isClock`, "m:ss" values count in seconds
 * (pace, hold). A range ("7-8") and text repeat as typed and reset the
 * progression; a change with nothing before it shows as typed.
 */
export function progress(row: Pick<PlanRow, "cells">, measure: CellKey, n: number, isClock = false): string[] {
  const fmtN = (v: number) =>
    isClock && v >= 60 ? `${Math.floor(v / 60)}:${String(Math.round(v % 60)).padStart(2, "0")}` : `${Math.round(v * 10) / 10}`;
  const out: string[] = [];
  let prev: number | null = null;
  let delta: number | null = null;
  let spread: { a: number; b: number; i: number } | null = null;
  let suffix = "";
  for (let i = 0; i < n; i++) {
    const raw = cellText(row, i, measure);
    const tok = readMeasureCell(raw, isClock);
    if (tok.t === "empty") {
      if (spread) prev = spread.a + ((spread.b - spread.a) * (i - spread.i)) / Math.max(1, n - 1 - spread.i);
      else if (delta != null && prev != null) prev += delta;
      out.push(prev != null ? fmtN(prev) + suffix : out[i - 1] || "");
    } else if (tok.t === "delta" && prev != null) {
      delta = tok.n;
      spread = null;
      prev += delta;
      out.push(fmtN(prev) + suffix);
    } else if (tok.t === "spread") {
      prev = tok.a;
      spread = { a: tok.a, b: tok.b, i };
      delta = null;
      suffix = tok.suffix;
      out.push(fmtN(prev) + suffix);
    } else if (tok.t === "abs") {
      prev = tok.n;
      suffix = tok.suffix;
      delta = null;
      spread = null;
      out.push(raw.trim());
    } else {
      prev = null;
      delta = null;
      spread = null;
      out.push(raw.trim());
    }
  }
  return out;
}

/**
 * Errors of a numeric measure's cells: `no_base` for a change ("+1") with
 * no number before it (first column, or after a range / text).
 */
export function measureCellErrors(row: Pick<PlanRow, "cells">, measure: CellKey, n: number, isClock = false): (PlanErrorCode | null)[] {
  let base = false;
  return Array.from({ length: Math.max(0, n) }, (_, i) => {
    const tok = readMeasureCell(cellText(row, i, measure), isClock);
    if (tok.t === "empty") return null;
    if (tok.t === "delta") return base ? null : "no_base";
    base = tok.t === "abs" || tok.t === "spread";
    return null;
  });
}

// ── tempo ──────────────────────────────────────────────────────────────────

/**
 * Four marks: seconds down · pause at the bottom · up (X = explosive) ·
 * pause at the top. Marks may be separated by "-", ".", "/" or a space.
 * X is Latin x or Greek χ, any case (read on normalised text).
 */
export const TEMPO = /^([0-9xχ])[-./ ]?([0-9xχ])[-./ ]?([0-9xχ])[-./ ]?([0-9xχ])$/;

/** One tempo mark: seconds, or "X" (explosive). */
export type TempoMark = number | "X";
export type TempoParts = { down: TempoMark; bottom: TempoMark; up: TempoMark; top: TempoMark };

/** "31X1" → { down: 3, bottom: 1, up: "X", top: 1 }; anything else → null. */
export function tempoParts(text: string): TempoParts | null {
  const m = TEMPO.exec(normText(text));
  if (!m) return null;
  const mark = (c: string): TempoMark => (/[xχ]/.test(c) ? "X" : +c);
  return { down: mark(m[1]), bottom: mark(m[2]), up: mark(m[3]), top: mark(m[4]) };
}

/** "31X1" → "↓3 ·1 ↑X ·1" (the WOD text view). */
export const tempoShort = (text: string): string | null => {
  const p = tempoParts(text);
  return p ? `↓${p.down} ·${p.bottom} ↑${p.up} ·${p.top}` : null;
};

/** The canonical tempo text ("31X1"). */
export const tempoCanonical = (text: string): string | null => {
  const p = tempoParts(text);
  return p ? `${p.down}${p.bottom}${p.up}${p.top}` : null;
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
