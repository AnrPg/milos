/**
 * ADR-270: what a structured WOD section can be made of. Three levels that
 * never mix: flows (how the clock runs), structures (one set or round of an
 * exercise or group), add-ons (mods). Presets are shortcuts that pre-fill a
 * flow. Values and defaults are the ones agreed in the approved mockup
 * (`docs/product/mockups/structured-wod-editor-mockup.html`); never add
 * defaults ANR did not agree.
 *
 * Labels are i18n keys (`PlanCore.*`); `aliases` (English + Greek, lower
 * case, unaccented where useful) feed the fuzzy search next to the
 * translated label.
 */
import type { PlanFlow, PlanMeasure, PlanMods, PlanParams, PlanStructureKind } from "./types";

export type ParamKey = keyof PlanParams;

/**
 * Kinds of parameter field: `time` one duration, `times` several durations
 * (AMRAP windows "3-3-3-4"), `count` a whole number, `range` "4" or "3-4",
 * `text` free text.
 */
export type ParamKind = "time" | "times" | "count" | "range" | "text";

export type ParamDef = {
  key: ParamKey;
  labelKey: string;
  kind: ParamKind;
  /** Default typed value ("" = empty). */
  dflt: string;
  /** How a bare number reads for time fields: minutes, or "smart" (≤ 10 minutes, else seconds). */
  bare: "min" | "smart";
};

/** How the exercises of a flow are laid out: rows × sets grid, a round loop, time slots, a work strip, none. */
export type FlowLayout = "grid" | "loop" | "slots" | "strip" | "none";

/** Stable score keys; labels are `PlanCore.score.<key>`. */
export type ScoreKey =
  | "none"
  | "best_load"
  | "reps"
  | "time"
  | "rounds_reps"
  | "done"
  | "total_reps"
  | "lowest_round"
  | "distance";

export type FlowDef = {
  key: PlanFlow;
  labelKey: string;
  hintKey: string;
  aliases: string[];
  layout: FlowLayout;
  params: ParamDef[];
  /** Score options; the first is the default. */
  scores: ScoreKey[];
  structs: PlanStructureKind[];
  mods: (keyof PlanMods)[];
};

const p = (key: ParamKey, kind: ParamKind, dflt: string, bare: "min" | "smart" = "smart"): ParamDef => ({
  key,
  labelKey: `PlanCore.param.${key}`,
  kind,
  dflt,
  bare,
});

export const FLOW_KEYS: PlanFlow[] = ["sets", "for_time", "amrap", "emom", "intervals", "rest"];

export const FLOWS: Record<PlanFlow, FlowDef> = {
  sets: {
    key: "sets",
    labelKey: "PlanCore.flow.sets",
    hintKey: "PlanCore.flowHint.sets",
    aliases: ["sets", "untimed", "strength", "hypertrophy", "σετ", "δύναμη", "υπερτροφία", "χωρίς χρόνο"],
    layout: "grid",
    params: [p("sets", "range", "4"), { ...p("rest", "time", "90″"), labelKey: "PlanCore.param.restBetween" }],
    scores: ["none", "best_load", "reps"],
    structs: ["single", "superset", "complex", "cluster", "drop", "restpause"],
    mods: ["interrupt"],
  },
  for_time: {
    key: "for_time",
    labelKey: "PlanCore.flow.for_time",
    hintKey: "PlanCore.flowHint.for_time",
    aliases: ["for time", "rft", "rounds for time", "για χρόνο"],
    layout: "loop",
    params: [p("rounds", "count", "1"), p("cap", "time", "", "min")],
    scores: ["time", "rounds_reps"],
    structs: ["single", "superset", "complex"],
    mods: ["interrupt"],
  },
  amrap: {
    key: "amrap",
    labelKey: "PlanCore.flow.amrap",
    hintKey: "PlanCore.flowHint.amrap",
    aliases: ["amrap", "as many rounds", "as many reps", "όσοι γύροι"],
    layout: "loop",
    params: [p("dur", "times", "12", "min"), { ...p("rest", "time", ""), labelKey: "PlanCore.param.restWindows" }],
    scores: ["rounds_reps", "reps"],
    structs: ["single", "superset", "complex"],
    mods: ["interrupt"],
  },
  emom: {
    key: "emom",
    labelKey: "PlanCore.flow.emom",
    hintKey: "PlanCore.flowHint.emom",
    aliases: ["emom", "e2mom", "every minute", "otm", "κάθε λεπτό"],
    layout: "slots",
    params: [p("every", "time", "1:00"), p("times", "count", "10")],
    scores: ["none", "done", "reps"],
    structs: ["single", "superset", "complex", "cluster"],
    mods: [],
  },
  intervals: {
    key: "intervals",
    labelKey: "PlanCore.flow.intervals",
    hintKey: "PlanCore.flowHint.intervals",
    aliases: ["intervals", "hiit", "custom", "διαλειμματική", "διαστήματα"],
    layout: "strip",
    params: [p("work", "time", "20″"), p("off", "time", "10″"), p("rounds", "count", "8")],
    scores: ["total_reps", "lowest_round", "distance"],
    structs: ["single", "superset", "complex"],
    mods: ["hr"],
  },
  rest: {
    key: "rest",
    labelKey: "PlanCore.flow.rest",
    hintKey: "PlanCore.flowHint.rest",
    aliases: ["rest", "break", "ξεκούραση", "διάλειμμα"],
    layout: "none",
    params: [{ ...p("dur", "time", "2:00"), labelKey: "PlanCore.param.dur" }],
    scores: ["none"],
    structs: [],
    mods: [],
  },
};

export type StructDef = {
  key: PlanStructureKind;
  labelKey: string;
  hintKey: string;
  aliases: string[];
  /** Needs a group of 2+ rows (superset, complex). */
  group: boolean;
  /** Its own fields (cluster: clusters, intra; drop: drops, dropby; rest-pause: minis, intra). */
  params: { key: string; labelKey: string; kind: "count" | "time" | "text"; dflt: string }[];
};

const sp = (key: string, kind: "count" | "time" | "text", dflt: string) => ({
  key,
  labelKey: `PlanCore.structParam.${key}`,
  kind,
  dflt,
});

export const STRUCT_KEYS: PlanStructureKind[] = ["single", "cluster", "drop", "restpause", "superset", "complex"];

export const STRUCTS: Record<PlanStructureKind, StructDef> = {
  single: { key: "single", labelKey: "PlanCore.struct.single", hintKey: "PlanCore.structHint.single", aliases: ["single", "plain", "απλό"], group: false, params: [] },
  cluster: {
    key: "cluster",
    labelKey: "PlanCore.struct.cluster",
    hintKey: "PlanCore.structHint.cluster",
    aliases: ["cluster", "κομμάτια"],
    group: false,
    params: [sp("clusters", "count", "3"), sp("intra", "time", "15″")],
  },
  drop: {
    key: "drop",
    labelKey: "PlanCore.struct.drop",
    hintKey: "PlanCore.structHint.drop",
    aliases: ["drop set", "dropset", "μείωση βάρους"],
    group: false,
    params: [sp("drops", "count", "2"), sp("dropby", "text", "-20%")],
  },
  restpause: {
    key: "restpause",
    labelKey: "PlanCore.struct.restpause",
    hintKey: "PlanCore.structHint.restpause",
    aliases: ["rest pause", "rest-pause", "myo reps", "μέχρι αποτυχία"],
    group: false,
    params: [sp("minis", "count", "3"), sp("intra", "time", "15″")],
  },
  superset: { key: "superset", labelKey: "PlanCore.struct.superset", hintKey: "PlanCore.structHint.superset", aliases: ["superset", "giant set", "σούπερσετ"], group: true, params: [] },
  complex: { key: "complex", labelKey: "PlanCore.struct.complex", hintKey: "PlanCore.structHint.complex", aliases: ["complex", "barbell complex", "χωρίς να αφήσεις τη μπάρα"], group: true, params: [] },
};

export type ModKey = keyof PlanMods;
export type ModDef = { key: ModKey; labelKey: string; hintKey: string; params: ParamDef[] };

export const MODS: Record<ModKey, ModDef> = {
  interrupt: {
    key: "interrupt",
    labelKey: "PlanCore.mod.interrupt",
    hintKey: "PlanCore.modHint.interrupt",
    params: [p("intEvery", "time", "2:00")],
  },
  hr: {
    key: "hr",
    labelKey: "PlanCore.mod.hr",
    hintKey: "PlanCore.modHint.hr",
    params: [p("hrTarget", "count", "120")],
  },
};

/**
 * Unit codes shown next to a value (`PlanCore.unit.<code>`), or none when
 * the value already says it.
 */
export type MeasureUnit = "per500m" | "outOf10" | "repsLeft" | "zone" | "cm" | "m" | "sec";

export type MeasureDef = {
  key: PlanMeasure;
  labelKey: string;
  hintKey?: string;
  aliases: string[];
  /** Example value (placeholder). */
  ph: string;
  /** Unit code, and when the typed value already states its own unit. */
  unit: MeasureUnit | null;
  unitStated?: RegExp;
  /** "m:ss" values count in seconds when progressing. */
  clock?: boolean;
  /** Text that only repeats, never progresses (tempo). */
  text?: boolean;
  /** No value: a tag next to the name ("per side"). */
  flag?: boolean;
  /** Highest allowed value. */
  max?: number;
};

export const MEASURE_KEYS: PlanMeasure[] = ["pace", "tempo", "rpe", "rir", "zone", "height", "dist", "hold", "side"];

export const MEASURES: Record<PlanMeasure, MeasureDef> = {
  pace: { key: "pace", labelKey: "PlanCore.measure.pace", aliases: ["pace", "split", "ρυθμός", "τρέξιμο", "κωπηλατική", "ποδήλατο"], ph: "2:00", unit: "per500m", unitStated: /\/|km|m\b/, clock: true },
  tempo: { key: "tempo", labelKey: "PlanCore.measure.tempo", hintKey: "PlanCore.measureHint.tempo", aliases: ["tempo", "τέμπο", "ταχύτητα εκτέλεσης", "κατέβασμα", "ανέβασμα"], ph: "31X1", unit: null, text: true },
  rpe: { key: "rpe", labelKey: "PlanCore.measure.rpe", aliases: ["rpe", "ένταση", "πόσο βαρύ"], ph: "8", unit: "outOf10", max: 10 },
  rir: { key: "rir", labelKey: "PlanCore.measure.rir", aliases: ["rir", "reps in reserve", "επαναλήψεις στην άκρη"], ph: "2", unit: "repsLeft" },
  zone: { key: "zone", labelKey: "PlanCore.measure.zone", aliases: ["zone", "heart rate", "ζώνη", "παλμοί", "z2"], ph: "2", unit: "zone", unitStated: /z/i },
  height: { key: "height", labelKey: "PlanCore.measure.height", aliases: ["height", "target", "box", "wall ball", "ύψος", "στόχος", "κουτί"], ph: "60", unit: "cm", unitStated: /cm|m|″|'/ },
  dist: { key: "dist", labelKey: "PlanCore.measure.dist", aliases: ["distance", "meters", "απόσταση", "μέτρα"], ph: "400", unit: "m", unitStated: /m/ },
  hold: { key: "hold", labelKey: "PlanCore.measure.hold", aliases: ["hold", "isometric", "pause", "κράτημα", "παύση"], ph: "3", unit: "sec", unitStated: /[s″:]/, clock: true },
  side: { key: "side", labelKey: "PlanCore.measure.side", aliases: ["per side", "each side", "unilateral", "πλευρά", "χέρι", "πόδι"], ph: "", unit: null, flag: true },
};

/** The unit to show next to a measure's value, or null when the value already says it. */
export function measureUnit(key: PlanMeasure, value: string): MeasureUnit | null {
  const m = MEASURES[key];
  if (!m.unit) return null;
  return m.unitStated && m.unitStated.test(value) ? null : m.unit;
}

export type PresetKey =
  | "tabata"
  | "billat"
  | "hrr"
  | "death_by"
  | "even_odd"
  | "complex_emom"
  | "edt"
  | "chipper"
  | "21_15_9"
  | "ladder"
  | "calorie_target"
  | "to_failure"
  | "superset"
  | "cluster"
  | "drop_set"
  | "rest_pause"
  | "interrupt";

export type PresetDef = {
  key: PresetKey;
  labelKey: string;
  aliases: string[];
  flow: PlanFlow;
  /** Parameters it fills in over the flow's defaults. */
  params?: PlanParams;
  /** Structure of the first unit (a group structure makes the first two rows a group). */
  struct?: PlanStructureKind;
  mods?: PlanMods;
  /** Dose of the first exercise. */
  reps?: string;
  score?: ScoreKey;
  /** EMOM: this many alternating slots (blocks). */
  slots?: number;
};

const preset = (key: PresetKey, flow: PlanFlow, aliases: string[], more: Omit<PresetDef, "key" | "labelKey" | "aliases" | "flow"> = {}): PresetDef => ({
  key,
  labelKey: `PlanCore.preset.${key}`,
  aliases,
  flow,
  ...more,
});

/** The 17 agreed presets, in the mockup's order. */
export const PRESETS: PresetDef[] = [
  preset("tabata", "intervals", ["tabata", "20 10"], { params: { work: "20″", off: "10″", rounds: "8" } }),
  preset("billat", "intervals", ["billat", "30 30"], { params: { work: "30″", off: "30″", rounds: "10" }, score: "distance" }),
  preset("hrr", "intervals", ["hrr", "heart rate recovery", "ανάκαμψη παλμών", "παλμοί"], { params: { work: "3:00", off: "", rounds: "3" }, mods: { hr: true } }),
  preset("death_by", "emom", ["death by", "deathby", "θάνατος"], { params: { every: "1:00", times: "" }, reps: "1-2-3…", score: "rounds_reps" }),
  preset("even_odd", "emom", ["even odd", "alternating", "μονά ζυγά", "εναλλάξ"], { slots: 2 }),
  preset("complex_emom", "emom", ["complex emom", "πολλαπλά διαστήματα"], { slots: 3 }),
  preset("edt", "amrap", ["edt", "escalating density"], { params: { dur: "15" }, struct: "superset", score: "reps" }),
  preset("chipper", "for_time", ["chipper"]),
  preset("21_15_9", "for_time", ["21 15 9", "fran", "couplet"], { reps: "21-15-9" }),
  preset("ladder", "for_time", ["ladder", "pyramid", "ascending", "descending", "σκάλα", "πυραμίδα"], { reps: "2-4-6…" }),
  preset("calorie_target", "for_time", ["kcal", "calories", "target", "θερμίδες", "στόχος"], { reps: "100 cal" }),
  preset("to_failure", "sets", ["train to exhaustion", "failure", "αποτυχία"], { reps: "max" }),
  preset("superset", "sets", ["superset", "giant set"], { struct: "superset" }),
  preset("cluster", "sets", ["cluster"], { struct: "cluster" }),
  preset("drop_set", "sets", ["drop set", "dropset"], { struct: "drop" }),
  preset("rest_pause", "sets", ["rest pause", "myo reps"], { struct: "restpause" }),
  preset("interrupt", "for_time", ["interrupt every", "διακοπή", "παρεμβολή"], { mods: { interrupt: true } }),
];

export const presetByKey = (key: string): PresetDef | undefined => PRESETS.find((x) => x.key === key);

/** Default values of a structure's own fields: `{ kind: "cluster", clusters: "3", intra: "15″" }`. */
export function structDefaults(kind: PlanStructureKind): Record<string, string> {
  return Object.fromEntries(STRUCTS[kind].params.map((f) => [f.key, f.dflt]));
}

/** Parameter definitions active for a flow and its add-ons. */
export function paramDefs(flow: PlanFlow, mods: PlanMods | undefined): ParamDef[] {
  const extra = FLOWS[flow].mods.filter((m) => mods?.[m]).flatMap((m) => MODS[m].params);
  return [...FLOWS[flow].params, ...extra];
}

/** The flow has a time step (any parameter) / an exercises step (any layout). */
export const hasTimeStep = (flow: PlanFlow): boolean => FLOWS[flow].params.length > 0;
export const hasExercises = (flow: PlanFlow): boolean => FLOWS[flow].layout !== "none";

/** i18n key of a score label. */
export const scoreLabelKey = (score: string): string => `PlanCore.score.${score}`;

/**
 * Score options for a section: its flow's, plus the score its preset chose
 * when the flow does not list it (Death by is an EMOM scored in rounds + reps).
 */
export function scoresFor(section: { flow: PlanFlow; preset?: string | null }): ScoreKey[] {
  const base = FLOWS[section.flow].scores;
  const extra = section.preset ? presetByKey(section.preset)?.score : undefined;
  return extra && !base.includes(extra) ? [...base, extra] : base;
}
