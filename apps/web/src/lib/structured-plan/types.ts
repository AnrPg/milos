/**
 * ADR-270: the structured WOD plan, the data a coach writes in the structured
 * editor and an athlete runs in the execution screen. It is the shared
 * contract between the editor, the API (`workout_sections.plan`, validated by
 * `Palee.Workouts.Domain.StructuredPlan`), the WOD text view and execution.
 *
 * Three levels never mix (ANR, 2026-10-29):
 *   1. the section's flow: how the clock runs (`PlanFlow`);
 *   2. the structure of one set or round, per exercise or group
 *      (`PlanStructure`);
 *   3. optional add-ons on top of a flow (`PlanMods`).
 * Presets (Tabata, Death by, EDT, …) are shortcuts that pre-fill these levels;
 * a section only remembers which preset it came from (`preset`), never a
 * separate format.
 *
 * Every value the coach types is stored as the text they typed (`string`),
 * so nothing is lost or reformatted; parsers in `parse.ts` read it. The API
 * re-parses the same text with the same rules and refuses what does not
 * read. Empty string = not set / "as before".
 */

export const PLAN_VERSION = 1 as const;

/** Level 1: how the clock runs for a whole section. */
export type PlanFlow = "sets" | "for_time" | "amrap" | "emom" | "intervals" | "rest";

/** Level 2: what happens inside one set or round. `superset` and `complex` hold 2+ rows. */
export type PlanStructureKind = "single" | "cluster" | "drop" | "restpause" | "superset" | "complex";

/** Optional measures a row can add (Alt+P). `side` is a flag with no value. */
export type PlanMeasure = "pace" | "tempo" | "rpe" | "rir" | "zone" | "height" | "dist" | "hold" | "side";

/** Level 3: add-ons a flow may allow. */
export type PlanMods = {
  /** Every `params.intEvery`, stop and do `interrupt` rows, then resume where you left off. */
  interrupt?: boolean;
  /** Intervals: rest ends when heart rate falls to `params.hrTarget` bpm. */
  hr?: boolean;
};

/**
 * Flow parameters, as typed. Keys per flow:
 *  sets:      sets ("4" or "3-4"), rest ("90″", "2:00", "90-120″")
 *  for_time:  rounds ("1"), cap ("20" = minutes, or "20:00")
 *  amrap:     dur ("12" or windows "3-3-3-4"), rest (between windows)
 *  emom:      every ("1:00", "2:30"), times ("10"; empty = until failure)
 *  intervals: work ("20″"), off ("10″"), rounds ("8")
 *  rest:      dur ("2:00")
 *  add-ons:   intEvery ("2:00") when mods.interrupt, hrTarget ("120") when mods.hr
 */
export type PlanParams = Partial<Record<
  "sets" | "rest" | "rounds" | "cap" | "dur" | "every" | "times" | "work" | "off" | "intEvery" | "hrTarget",
  string
>>;

/**
 * Values of one row in one set / round (column). `d` = reps or quantity
 * ("12", "8-12", "max", "400 m", "15 cal", "60s"; for a rest row the rest
 * time), `l` = load ("60kg", "70%", "βαρύ", "+5", "60→80"). Other keys are
 * measures (`PlanMeasure`, never `side`). Empty / missing = same as the
 * previous column; "+x" / "-x" = change by x from the previous column;
 * "a→b" (or "a->b") = spread from a to b up to the last column.
 * Load unit (kg or %) is stated once per row; bare numbers inherit it.
 */
export type PlanCell = { d?: string; l?: string } & Partial<Record<Exclude<PlanMeasure, "side">, string>>;

export type PlanRow = {
  /** Client-generated stable id (uuid). */
  id: string;
  kind: "ex" | "rest";
  /** Exercise name as typed or picked (fuzzy suggestions). Empty for rest rows. */
  name: string;
  /** Optional link to the exercise library (`exercise_ref`). */
  exerciseRef?: string | null;
  /**
   * Same-for-every-set values (flows other than `sets`, while `perRound` is
   * off): `dose` = reps / quantity, `load`, `x` = measures.
   */
  dose: string;
  load: string;
  x?: Partial<Record<Exclude<PlanMeasure, "side">, string>>;
  /** Measures this row shows, in order (adding `side` marks "per side"). */
  extra?: PlanMeasure[];
  /**
   * Per set (flow `sets`) or per round (other flows when `perRound`): one
   * cell per column of this row's block, see `occurrences`. Trailing
   * missing cells inherit.
   */
  cells: PlanCell[];
  /** Other flows: values change per round (Alt+V). */
  perRound?: boolean;
  /** Rows with the same group id that are consecutive form one superset / complex. */
  group?: string | null;
  note?: string;
};

/** The structure of one execution unit (one row, or one group), keyed by row id or group id. */
export type PlanStructure =
  | { kind: "single" }
  | { kind: "superset" }
  | { kind: "complex" }
  | { kind: "cluster"; clusters: string; intra: string }
  | { kind: "drop"; drops: string; dropby: string }
  | { kind: "restpause"; minis: string; intra: string };

/**
 * One section of a structured WOD. `blocks` are kinds of round that alternate
 * (block 0 = rounds 1, 3, 5…; block 1 = rounds 2, 4, 6… with two blocks); one
 * block = every round the same. With as many blocks as rounds, every round is
 * its own. EMOM blocks are its alternating minutes / slots.
 */
export type PlanSection = {
  v: typeof PLAN_VERSION;
  flow: PlanFlow;
  /** Preset label key it was created from (`tabata`, `death_by`, …), for display only. */
  preset?: string | null;
  params: PlanParams;
  mods?: PlanMods;
  blocks: PlanRow[][];
  /** Rows done at every interruption (`mods.interrupt`). */
  interrupt?: PlanRow[];
  structs?: Record<string, PlanStructure>;
  /** Score key from `FLOWS[flow].scores`. */
  score: string;
  note?: string;
  /** Optional notes per scale level (key = the workout's level key, e.g. "rx", "scaled"). */
  levelNotes?: Record<string, string>;
};

/** Execution unit: one row, or consecutive rows of the same group done together (set-wise). */
export type PlanUnit = { group: string | null; rows: PlanRow[] };
