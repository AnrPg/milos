/**
 * TEMPORARY shim (agent 4): the pieces of `@/lib/structured-plan` (agent 1,
 * branch plan/1-core) the grid needs, ported from the approved mockup, until
 * that library lands. Every export is replaced by the library's own and this
 * file is deleted once plan/1-core is merged.
 */
import type { PlanCell, PlanMeasure, PlanRow, PlanSection, PlanStructure, PlanStructureKind, PlanUnit } from "@/lib/structured-plan/types";

type ValueKey = Exclude<keyof PlanCell, never>;

// ── dose ──────────────────────────────────────────────────────────────────
const NUM = "(\\d+(?:\\.\\d+)?(?::\\d{2})?)";
const toNum = (t: string) => (t.includes(":") ? t.split(":").reduce((a, x) => a * 60 + Number(x), 0) : Number(t));

type Entry = { min: number; max: number };
export type Dose = {
  sets: Entry | null;
  entries: Entry[] | null;
  unit: "reps" | "kcal" | "m" | "secs";
  perSide: boolean;
  cont: boolean;
  max: { within: number | null } | null;
};

export function parseClock(t: string, dflt: "min" | "smart" = "min"): number | "bad" | null {
  const v = t.trim().toLowerCase();
  if (!v) return null;
  let m = /^(\d+):(\d{2})$/.exec(v);
  if (m) return Number(m[1]) * 60 + Number(m[2]);
  m = /^(\d+)\s*(s|sec|″|"|δ)$/.exec(v);
  if (m) return Number(m[1]);
  m = /^(\d+)\s*(min|'|′|λ|λεπτά)$/.exec(v);
  if (m) return Number(m[1]) * 60;
  m = /^(\d+)$/.exec(v);
  if (m) return dflt === "min" || Number(m[1]) <= 10 ? Number(m[1]) * 60 : Number(m[1]);
  return "bad";
}

function parseNums(input: string): { entries: Entry[]; cont: boolean } | "bad" {
  let v = input;
  let cont = false;
  if (/(…|\.\.\.|\+)$/.test(v)) {
    cont = true;
    v = v.replace(/(…|\.\.\.|\+)$/, "").trim();
  }
  const words = new RegExp(`^${NUM}\\s*(?:έως|εως|to|~)\\s*${NUM}$`).exec(v);
  if (words) return { entries: [{ min: toNum(words[1]!), max: toNum(words[2]!) }], cont: false };
  if (v.includes(",")) {
    const sets = v.split(/\s*,\s*/).map((p) => {
      const r = new RegExp(`^${NUM}(?:\\s*(?:[-–]|έως|εως|to)\\s*${NUM})?$`).exec(p);
      return r ? { min: toNum(r[1]!), max: toNum(r[2] ?? r[1]!) } : null;
    });
    if (sets.some((e) => !e || e.max < e.min) || (cont && sets.length < 2)) return "bad";
    return { entries: sets as Entry[], cont };
  }
  const parts = v.split(/\s*[-–,]\s*/);
  if (!parts.every((p) => new RegExp(`^${NUM}$`).test(p))) return "bad";
  const nums = parts.map(toNum);
  if (cont && nums.length < 2) return "bad";
  if (nums.length === 2 && nums[0]! < nums[1]! && !cont) return { entries: [{ min: nums[0]!, max: nums[1]! }], cont };
  return { entries: nums.map((n) => ({ min: n, max: n })), cont };
}

const SIDE = /\s*(\/\s*(side|πλευρά|πλευρα|πλ\.?|χέρι|χερι|πόδι|ποδι)|(on\s+)?each(\s+(side|arm|leg))?|for each arm|ανά πλευρά|ανα πλευρα|ανά χέρι|ανα χερι|ανά πόδι|ανα ποδι)$/;
const UNIT = /\s*(reps|r|επ\.?|cal|kcal|θερμ\.?|km|m|sec|s|″|"|δ|min|'|′|λ)$/;

export function parseDose(text: string): Dose | "bad" | null {
  let v = text.trim().toLowerCase().replace(/\s+/g, " ");
  if (!v) return null;
  const out: Dose = { sets: null, entries: null, unit: "reps", perSide: false, cont: false, max: null };
  const sm = SIDE.exec(v);
  if (sm) {
    out.perSide = true;
    v = v.slice(0, sm.index).trim();
  }
  const sx = /^(\d+)(?:\s*-\s*(\d+))?\s*(?:sets?|σετ)?\s*[x×χ]\s*(.*)$/.exec(v);
  if (sx) {
    out.sets = { min: Number(sx[1]), max: Number(sx[2] ?? sx[1]) };
    v = sx[3]!.trim();
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
    const u = um[1]!;
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

// ── progressions ──────────────────────────────────────────────────────────
export type LoadError = "missing_unit" | "mixed_units";
export type LoadSeries = { values: string[]; errors: Record<number, LoadError>; unit: "kg" | "%" | null };

/** Load per column: unit stated once per row, `+x` keeps adding, `a→b` spreads, empty repeats. */
export function setLoads(cells: PlanCell[], n: number): LoadSeries {
  const values: string[] = [];
  const errors: Record<number, LoadError> = {};
  let prev: number | null = null;
  let delta: number | null = null;
  let spread: { a: number; b: number; i: number } | null = null;
  const raw = (i: number) =>
    (cells[i]?.l ?? "").trim().toLowerCase().replace(",", ".").replace(/κιλ[άα]?/, "kg");
  const RE = /^([+-]?\d+(?:\.\d+)?)\s*(%|kg)?(?:\s*(?:→|->|ως|έως)\s*(\d+(?:\.\d+)?)\s*(%|kg)?)?$/;
  const stated = Array.from({ length: n }, (_, i) => {
    const m = RE.exec(raw(i));
    return m ? ((m[4] ?? m[2] ?? null) as "kg" | "%" | null) : null;
  });
  const unit = stated.find(Boolean) ?? null;
  const fmt = (v: number) => `${Math.round(v * 10) / 10}${unit === "%" ? "%" : " kg"}`;
  for (let i = 0; i < n; i++) {
    const t = raw(i);
    const m = t ? RE.exec(t) : null;
    if (!t) {
      if (spread) prev = spread.a + ((spread.b - spread.a) * (i - spread.i)) / Math.max(1, n - 1 - spread.i);
      else if (delta != null && prev != null) prev += delta;
      values.push(prev != null && unit ? fmt(prev) : (values[i - 1] ?? ""));
      continue;
    }
    if (!m) {
      prev = null;
      delta = null;
      spread = null;
      values.push(cells[i]!.l!.trim());
      continue;
    }
    if (!unit) {
      errors[i] = "missing_unit";
      values.push("");
      continue;
    }
    if (stated[i] && stated[i] !== unit) {
      errors[i] = "mixed_units";
      values.push("");
      continue;
    }
    const relative = /^[+-]/.test(m[1]!);
    if (relative && prev != null && !m[3]) {
      delta = Number(m[1]);
      spread = null;
      prev += delta;
      values.push(fmt(prev));
      continue;
    }
    if (m[3]) {
      prev = Math.abs(Number(m[1]));
      spread = { a: prev, b: Number(m[3]), i };
      delta = null;
      values.push(fmt(prev));
      continue;
    }
    prev = Math.abs(Number(m[1]));
    delta = null;
    spread = null;
    values.push(fmt(prev));
  }
  return { values, errors, unit };
}

/** Any numeric measure: empty repeats (or keeps adding), `+x` adds, `a→b` spreads. */
export function progress(cells: PlanCell[], key: ValueKey, n: number, clockish = false): string[] {
  const toN = (t: string) => (clockish && /^\d+:\d\d$/.test(t) ? t.split(":").reduce((a, x) => a * 60 + Number(x), 0) : Number(t));
  const fmtN = (v: number) =>
    clockish && v >= 60 ? `${Math.floor(v / 60)}:${String(Math.round(v % 60)).padStart(2, "0")}` : `${Math.round(v * 10) / 10}`;
  const out: string[] = [];
  let prev: number | null = null;
  let delta: number | null = null;
  let spread: { a: number; b: number; i: number } | null = null;
  let suffix = "";
  for (let i = 0; i < n; i++) {
    const t = (cells[i]?.[key] ?? "").trim().replace(",", ".");
    let m: RegExpExecArray | null;
    if (!t) {
      if (spread) prev = spread.a + ((spread.b - spread.a) * (i - spread.i)) / Math.max(1, n - 1 - spread.i);
      else if (delta != null && prev != null) prev += delta;
      out.push(prev != null ? fmtN(prev) + suffix : (out[i - 1] ?? ""));
      continue;
    }
    if ((m = /^([+-])(\d+(?::\d\d)?(?:\.\d+)?)$/.exec(t)) && prev != null) {
      delta = (m[1] === "-" ? -1 : 1) * toN(m[2]!);
      spread = null;
      prev += delta;
      out.push(fmtN(prev) + suffix);
      continue;
    }
    if ((m = /^(\d+(?::\d\d)?(?:\.\d+)?)\s*(?:→|->)\s*(\d+(?::\d\d)?(?:\.\d+)?)(.*)$/.exec(t))) {
      prev = toN(m[1]!);
      spread = { a: prev, b: toN(m[2]!), i };
      delta = null;
      suffix = m[3]!;
      out.push(fmtN(prev) + suffix);
      continue;
    }
    if ((m = /^(\d+(?::\d\d)?(?:\.\d+)?)(.*)$/.exec(t))) {
      prev = toN(m[1]!);
      suffix = m[2]!;
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

/** Text values (tempo, reps) only repeat; they never count up. */
export function repeatText(cells: PlanCell[], key: ValueKey, n: number): string[] {
  const out: string[] = [];
  for (let i = 0; i < n; i++) out.push(cells[i]?.[key] || out[i - 1] || "");
  return out;
}

export const repeatDose = (cells: PlanCell[], n: number) => repeatText(cells, "d", n);

const TEMPO = /^([0-9xX])-?([0-9xX])-?([0-9xX])-?([0-9xX])$/;
/** The four tempo marks, or null when the text is not a tempo. */
export function parseTempo(text: string): [string, string, string, string] | null {
  const m = TEMPO.exec(text.trim());
  return m ? [m[1]!, m[2]!, m[3]!.toUpperCase(), m[4]!] : null;
}

// ── rounds ────────────────────────────────────────────────────────────────
export function unitsOf(list: PlanRow[]): PlanUnit[] {
  const out: PlanUnit[] = [];
  for (const r of list) {
    const last = out.at(-1);
    if (r.group && last && last.group === r.group) last.rows.push(r);
    else out.push({ group: r.group ?? null, rows: [r] });
  }
  return out;
}

export const unitKey = (u: PlanUnit) => u.group ?? u.rows[0]!.id;
export const isGroupStructure = (kind: PlanStructureKind) => kind === "superset" || kind === "complex";

export function structOf(plan: PlanSection, u: PlanUnit): PlanStructure {
  const st = plan.structs?.[unitKey(u)];
  const isGroup = u.rows.length > 1;
  if (st && isGroupStructure(st.kind) === isGroup) return st;
  return { kind: isGroup ? "superset" : "single" };
}

const count = (v: string | undefined) => (/^\d+$/.test((v ?? "").trim()) && Number(v) > 0 ? Number(v) : null);

export function setsRange(plan: PlanSection) {
  const m = /^(\d+)(?:\s*-\s*(\d+))?$/.exec((plan.params.sets ?? "").trim());
  return m ? { min: Number(m[1]), max: Number(m[2] ?? m[1]) } : { min: 1, max: 1 };
}

export function totalRounds(plan: PlanSection): number {
  if (plan.flow === "sets") return setsRange(plan).max;
  if (plan.flow === "emom") return count(plan.params.times) ?? 10;
  if (plan.flow === "amrap") return Infinity;
  return count(plan.params.rounds) ?? 1;
}

const filledCell = (c: PlanCell | undefined) => Boolean(c && Object.values(c).some((v) => String(v ?? "").trim()));

/**
 * The rounds (1-based) block `b` runs in. AMRAP has no last round: the
 * rounds the coach wrote plus one empty column that grows as they type.
 */
export function occurrences(plan: PlanSection, b: number): { list: number[]; open: boolean } {
  const k = Math.max(1, plan.blocks.length);
  const T = totalRounds(plan);
  const open = T === Infinity;
  const list: number[] = [];
  const rows = plan.blocks[b] ?? [];
  const filled = open ? Math.max(0, ...rows.map((r) => r.cells.reduce((a, c, i) => (filledCell(c) ? i + 1 : a), 0))) : 0;
  for (let i = b; (open ? list.length < Math.max(2, filled + 1) : i < T) && list.length < 12; i += k) list.push(i + 1);
  return { list, open };
}

// ── measures ──────────────────────────────────────────────────────────────
export type MeasureDef = {
  /** Placeholder / example value. */
  ph: string;
  /** Unit suffix for a typed value (empty when the value already says it). */
  unit: (value: string) => string;
  flag?: boolean;
  text?: boolean;
  clock?: boolean;
  max?: number;
  aliases: string;
};

export const MEASURES: Record<PlanMeasure, MeasureDef> = {
  pace: { ph: "2:00", unit: (v) => (/\/|km|m\b/.test(v) ? "" : "/500m"), clock: true, aliases: "pace split ρυθμος τρεξιμο κωπηλατικη ποδηλατο" },
  tempo: { ph: "31X1", unit: () => "", text: true, aliases: "tempo τεμπο ταχυτητα εκτελεσης κατεβασμα ανεβασμα" },
  rpe: { ph: "8", unit: () => "/10", max: 10, aliases: "rpe ενταση ποσο βαρυ" },
  rir: { ph: "2", unit: () => "", aliases: "rir reps in reserve επαναληψεις στην ακρη" },
  zone: { ph: "2", unit: () => "", aliases: "zone heart rate ζωνη παλμοι z2" },
  height: { ph: "60", unit: (v) => (/cm|m|″|'/.test(v) ? "" : "cm"), aliases: "height target box wall ball υψος στοχος κουτι" },
  dist: { ph: "400", unit: (v) => (/m/.test(v) ? "" : "m"), aliases: "distance meters αποσταση μετρα" },
  hold: { ph: "3", unit: (v) => (/[s″:]/.test(v) ? "" : "s"), clock: true, aliases: "hold isometric pause κρατημα παυση" },
  side: { ph: "", unit: () => "", flag: true, aliases: "per side each side unilateral πλευρα χερι ποδι" },
};
export const MEASURE_KEYS = Object.keys(MEASURES) as PlanMeasure[];

export const FLOW_STRUCTS: Record<PlanSection["flow"], PlanStructureKind[]> = {
  sets: ["single", "superset", "complex", "cluster", "drop", "restpause"],
  for_time: ["single", "superset", "complex"],
  amrap: ["single", "superset", "complex"],
  emom: ["single", "superset", "complex", "cluster"],
  intervals: ["single", "superset", "complex"],
  rest: [],
};

const STRUCT_DEFAULTS: Record<PlanStructureKind, PlanStructure> = {
  single: { kind: "single" },
  superset: { kind: "superset" },
  complex: { kind: "complex" },
  cluster: { kind: "cluster", clusters: "3", intra: "15″" },
  drop: { kind: "drop", drops: "2", dropby: "-20%" },
  restpause: { kind: "restpause", minis: "3", intra: "15″" },
};
export const structureDefaults = (kind: PlanStructureKind): PlanStructure => ({ ...STRUCT_DEFAULTS[kind] });

// ── fuzzy ─────────────────────────────────────────────────────────────────
export const fold = (s: string) => s.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().trim();

function editDistance(a: string, b: string) {
  const d = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array<number>(b.length).fill(0)]);
  for (let j = 1; j <= b.length; j++) d[0]![j] = j;
  for (let i = 1; i <= a.length; i++)
    for (let j = 1; j <= b.length; j++) {
      d[i]![j] = Math.min(d[i - 1]![j]! + 1, d[i]![j - 1]! + 1, d[i - 1]![j - 1]! + (a[i - 1] === b[j - 1] ? 0 : 1));
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d[i]![j] = Math.min(d[i]![j]!, d[i - 2]![j - 2]! + 1);
    }
  return d[a.length]![b.length]!;
}

export type FuzzyMatch = { score: number; marks: [number, number][] };

/** Every query word must match some word of the text: prefix, inside a word, or with one or two typos. */
export function fuzzy(query: string, text: string): FuzzyMatch | null {
  const q = fold(query).split(/[\s\-/]+/).filter(Boolean);
  if (!q.length) return { score: 0, marks: [] };
  const t = fold(text);
  const words: { w: string; at: number }[] = [];
  for (const m of t.matchAll(/[^\s\-/(),·]+/g)) words.push({ w: m[0], at: m.index });
  let score = 0;
  const marks: [number, number][] = [];
  for (const qw of q) {
    let best: { s: number; m: [number, number] } | null = null;
    for (const { w, at } of words) {
      let s: number | null = null;
      let m: [number, number] | null = null;
      if (w.startsWith(qw)) {
        s = 10 + (w === qw ? 3 : 0);
        m = [at, at + qw.length];
      } else if (w.includes(qw) && qw.length > 1) {
        s = 6;
        const i = w.indexOf(qw);
        m = [at + i, at + i + qw.length];
      } else if (qw.length >= 3) {
        const allow = qw.length >= 7 ? 2 : 1;
        const dist = Math.min(editDistance(qw, w.slice(0, qw.length)), editDistance(qw, w));
        if (dist <= allow) {
          s = 4 - dist;
          m = [at, at + Math.min(w.length, qw.length)];
        }
      }
      if (s != null && m && (!best || s > best.s)) best = { s, m };
    }
    if (!best) return null;
    score += best.s;
    marks.push(best.m);
  }
  return { score, marks };
}
