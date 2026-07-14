export type PrescriptionUnit = "reps" | "secs" | "kcal";
export type LoadMode = "absolute" | "pct_1rm" | "bw";
export type LoadProgressionMode = "linear" | "per_set";
export type IntervalMode = "none" | "minute" | "odd_even";

export type LoadProgression = {
  mode: LoadProgressionMode;
  startValue: number;
  startMode: LoadMode;
  stepValue: number;
  perSetValues: number[];
};

export type ExerciseFormatContext = {
  showSets: boolean;
  showPrescription: boolean;
  prescriptionHint?: string;
  prescriptionSuffix?: string;
  ladderPrescription?: boolean;
  showClusters?: boolean;
  showLoad: boolean;
  intervalMode: IntervalMode;
};

export type WorkoutType =
  | "crossfit"
  | "strength"
  | "gymnastics"
  | "aerobics"
  | "flexibility"
  | "recovery";

export type SectionFormat =
  | "untimed"
  | "for_time"
  | "train_to_exhaustion"
  | "kcal_target"
  | "emom"
  | "complex_emom"
  | "even_odd"
  | "billat"
  | "amrap"
  | "edt"
  | "death_by"
  | "tabata"
  | "custom_hiit"
  | "cluster"
  | "hrr"
  | "ladder_ascending"
  | "ladder_descending"
  | "pyramid"
  | "rest";

export type ScoreType =
  | "time"
  | "reps"
  | "weight"
  | "rounds"
  | "rounds+reps"
  | "kcal"
  | "hr_drop"
  | "load"
  | "accumulated_work_time"
  | "pass_fail"
  | "intervals_survived";

export type EmomScoringMode = "for_time" | "for_quality" | "amrap" | "to_failure";

export const EMOM_SCORING_MODE_LABELS: Record<EmomScoringMode, string> = {
  for_time: "For Time",
  for_quality: "For Quality",
  amrap: "AMRAP",
  to_failure: "To Failure",
};

export const EMOM_SCORING_MODE_DESCRIPTIONS: Record<EmomScoringMode, string> = {
  for_time: "Sprint each window. Score = accumulated work time (lower is better).",
  for_quality: "Prioritize perfect form. Score = Pass / Fail.",
  amrap: "Max reps each window. Score = total cumulative reps.",
  to_failure: "Fixed reps each window, keep going until you fail. Score = windows survived.",
};

export const EMOM_SCORING_MODE_SCORE_TYPE: Record<EmomScoringMode, ScoreType> = {
  for_time: "accumulated_work_time",
  for_quality: "pass_fail",
  amrap: "reps",
  to_failure: "intervals_survived",
};

export type FormatParams = Record<string, number | null>;

export type DraftVariation = {
  scaleLevelSlug: string;
  exerciseNameOverride: string | null;
  sets: number | null;
  prescriptionValue: number | null;
  prescriptionUnit: PrescriptionUnit | null;
  loadValue: number | null;
  loadMode: LoadMode | null;
  excluded: boolean;
};

export type AdvancedSettings = {
  hrZone: { enabled: boolean; value: number };
  tempo: { enabled: boolean; value: string };
  restSeconds: { enabled: boolean; value: number };
  clusterRestSeconds: { enabled: boolean; value: number };
  restPauseSeconds: { enabled: boolean; value: number };
  pacing: { enabled: boolean; value: number };
};

export type DraftExercise = {
  localId: string;
  name: string;
  sets: number;
  prescriptionValue: number;
  prescriptionUnit: PrescriptionUnit;
  prescriptionStep: number | null;
  clustersPerSet: number | null;
  loadValue: number | null;
  loadMode: LoadMode;
  loadProgression: LoadProgression | null;
  isBodyweight: boolean;
  supersetGroupId: string | null;
  intervalAssignment: number | null;
  advanced: AdvancedSettings;
  variationsOpen: boolean;
  advancedOpen: boolean;
  variations: DraftVariation[];
  note: string | null;
};

export type DraftSection = {
  localId: string;
  name: string;
  format: SectionFormat;
  formatParams: FormatParams;
  scoreable: boolean;
  scoreType: ScoreType | null;
  emomScoringMode: EmomScoringMode | null;
  emomAmrapScoringStyle: "grand_total" | "lowest_window" | null;
  restAfterSeconds: number | null;
  exercises: DraftExercise[];
  note: string | null;
};

export type DraftWorkoutState = {
  draftId: string | null;
  title: string;
  type: WorkoutType | null;
  isTeamWorkout: boolean;
  sections: DraftSection[];
};

export type MobileView = "sections" | "exercises" | "preview";

export const AUTO_SCORE_MAP: Partial<Record<SectionFormat, ScoreType>> = {
  for_time: "time",
  kcal_target: "kcal",
  amrap: "rounds+reps",
  edt: "reps",
  death_by: "reps",
  ladder_descending: "time",
  pyramid: "time",
  hrr: "hr_drop",
};

export const FORMAT_GROUPS: { label: string; formats: SectionFormat[] }[] = [
  {
    label: "Basic",
    formats: ["untimed", "for_time", "train_to_exhaustion", "kcal_target"],
  },
  {
    label: "Interval",
    formats: ["emom", "complex_emom", "even_odd", "billat"],
  },
  {
    label: "Sustained Cardio",
    formats: ["amrap", "edt", "death_by"],
  },
  {
    label: "Set-Based",
    formats: ["tabata", "custom_hiit", "cluster", "hrr"],
  },
  {
    label: "Progressive",
    formats: ["ladder_ascending", "ladder_descending", "pyramid"],
  },
  { label: "Rest", formats: ["rest"] },
];

export const FORMAT_LABELS: Record<SectionFormat, string> = {
  untimed: "Untimed",
  for_time: "For Time",
  train_to_exhaustion: "Train to Exhaustion",
  kcal_target: "Kcal Target",
  emom: "EMOM",
  complex_emom: "Complex EMOM",
  even_odd: "Even / Odd",
  billat: "Billat",
  amrap: "AMRAP",
  edt: "EDT",
  death_by: "Death By",
  tabata: "Tabata",
  custom_hiit: "Custom HIIT",
  cluster: "Cluster",
  hrr: "HRR",
  ladder_ascending: "Ladder Ascending",
  ladder_descending: "Ladder Descending",
  pyramid: "Pyramid",
  rest: "Rest",
};

export const FORMAT_TOOLTIPS: Record<
  SectionFormat,
  {
    bestFor: string;
    trains: string;
    how: string;
    score?: string;
  }
> = {
  untimed: {
    bestFor: "Strength, skill work, warm-ups",
    trains: "Technique, strength",
    how: "No time constraint. Quality over speed.",
  },
  for_time: {
    bestFor: "High-intensity WODs",
    trains: "Speed, conditioning",
    how: "Complete all reps or rounds as fast as possible.",
    score: "Time",
  },
  train_to_exhaustion: {
    bestFor: "Hypertrophy, muscular endurance",
    trains: "Muscular endurance",
    how: "Push each set to technical failure.",
    score: "Total reps",
  },
  kcal_target: {
    bestFor: "Cardio machines",
    trains: "Aerobic capacity",
    how: "Reach the calorie target as fast as possible.",
    score: "Kcal",
  },
  emom: {
    bestFor: "Interval training with defined objectives",
    trains: "Power output, pacing, endurance, or technique",
    how: "Same movement every interval. Choose a mode: For Time (sprint + rest), For Quality (form focus), AMRAP (max reps), or To Failure (survive as many windows as possible).",
    score: "Accumulated work time / Pass-Fail / Total reps / Windows survived",
  },
  complex_emom: {
    bestFor: "Mixed modality circuit training",
    trains: "Varied skills, pacing, multi-modal conditioning",
    how: "2+ movements rotating each interval window. Choose: For Time, For Quality, AMRAP (grand total or lowest window), or To Failure.",
    score: "Accumulated work time / Pass-Fail / Total reps or lowest window / Stations cleared",
  },
  even_odd: {
    bestFor: "Paired movement training",
    trains: "Alternating skills",
    how: "Even minutes and odd minutes run different tasks.",
  },
  billat: {
    bestFor: "VO2max development",
    trains: "Aerobic power",
    how: "Repeated max-effort intervals with equal rest.",
  },
  amrap: {
    bestFor: "Benchmark WODs, capacity testing",
    trains: "Conditioning, mental toughness",
    how: "Accumulate as many rounds and reps as possible.",
    score: "Rounds + reps",
  },
  edt: {
    bestFor: "Volume accumulation",
    trains: "Muscular endurance",
    how: "Accumulate as many reps as possible in the time window.",
    score: "Reps",
  },
  death_by: {
    bestFor: "Progressive overload, competition",
    trains: "Endurance, max capacity",
    how: "Add reps every round until the round cannot be completed.",
    score: "Total reps",
  },
  tabata: {
    bestFor: "HIIT conditioning",
    trains: "Anaerobic capacity",
    how: "Short work and rest intervals for fixed rounds.",
  },
  custom_hiit: {
    bestFor: "Custom interval protocols",
    trains: "Anaerobic and aerobic mix",
    how: "Custom work and rest ratio for fixed rounds.",
  },
  cluster: {
    bestFor: "Heavy strength, cluster sets",
    trains: "Maximal strength",
    how: "Short intra-set rest between each rep cluster.",
  },
  hrr: {
    bestFor: "Heart rate-guided recovery",
    trains: "Cardiovascular recovery",
    how: "Rest until heart rate drops to the target zone.",
    score: "HR drop rate",
  },
  ladder_ascending: {
    bestFor: "Progressive loading",
    trains: "Strength endurance",
    how: "Start at base reps and add step reps every round.",
  },
  ladder_descending: {
    bestFor: "Countdown workouts",
    trains: "Speed, conditioning",
    how: "Start high and subtract reps every round.",
    score: "Time",
  },
  pyramid: {
    bestFor: "Volume and intensity balance",
    trains: "Strength, endurance",
    how: "Reps climb to a peak and then descend.",
    score: "Time",
  },
  rest: {
    bestFor: "Programmed recovery",
    trains: "Recovery",
    how: "Passive rest for the given duration.",
  },
};

type FormatFieldDef = {
  key: string;
  defaultValue: number;
  required?: boolean;
};

export const FORMAT_FIELD_DEFS: Partial<Record<SectionFormat, FormatFieldDef[]>> = {
  for_time: [{ key: "time_cap_seconds", defaultValue: 900 }],
  train_to_exhaustion: [{ key: "rest_seconds", defaultValue: 90 }],
  kcal_target: [{ key: "kcal_target", defaultValue: 100, required: true }, { key: "time_cap_seconds", defaultValue: 900 }],
  emom: [
    { key: "duration_seconds", defaultValue: 600, required: true },
    { key: "interval_seconds", defaultValue: 60, required: true },
    { key: "max_windows", defaultValue: 100 },
  ],
  complex_emom: [
    { key: "duration_seconds", defaultValue: 600, required: true },
    { key: "interval_seconds", defaultValue: 60, required: true },
    { key: "max_windows", defaultValue: 100 },
  ],
  even_odd: [{ key: "duration_seconds", defaultValue: 600, required: true }],
  billat: [
    { key: "work_seconds", defaultValue: 30, required: true },
    { key: "rest_seconds", defaultValue: 30, required: true },
    { key: "cycles", defaultValue: 8, required: true },
  ],
  amrap: [{ key: "duration_seconds", defaultValue: 720, required: true }],
  edt: [{ key: "duration_seconds", defaultValue: 900, required: true }, { key: "pr_zone_rounds", defaultValue: 5 }],
  death_by: [
    { key: "max_rounds", defaultValue: 0 },
  ],
  tabata: [
    { key: "work_seconds", defaultValue: 20, required: true },
    { key: "rest_seconds", defaultValue: 10, required: true },
    { key: "rounds", defaultValue: 8, required: true },
  ],
  custom_hiit: [
    { key: "work_seconds", defaultValue: 40, required: true },
    { key: "rest_seconds", defaultValue: 20, required: true },
    { key: "rounds", defaultValue: 10, required: true },
  ],
  cluster: [
    { key: "intra_rest_seconds", defaultValue: 15, required: true },
  ],
  hrr: [
    { key: "hr_ceiling_bpm", defaultValue: 175, required: true },
    { key: "hr_floor_bpm", defaultValue: 130, required: true },
    { key: "cycles", defaultValue: 0 },
    { key: "effort_cap_seconds", defaultValue: 0 },
  ],
  ladder_ascending: [
    { key: "time_cap_seconds", defaultValue: 0 },
  ],
  ladder_descending: [
    { key: "min_reps", defaultValue: 1 },
    { key: "time_cap_seconds", defaultValue: 0 },
  ],
  pyramid: [
    { key: "time_cap_seconds", defaultValue: 0 },
  ],
  rest: [{ key: "duration_seconds", defaultValue: 60, required: true }],
};

export function makeDefaultFormatParams(format: SectionFormat): FormatParams {
  const fields = FORMAT_FIELD_DEFS[format] ?? [];
  return Object.fromEntries(fields.map((f) => [f.key, f.defaultValue]));
}

export function makeDefaultAdvancedSettings(): AdvancedSettings {
  return {
    hrZone: { enabled: false, value: 3 },
    tempo: { enabled: false, value: "3-1-2-0" },
    restSeconds: { enabled: false, value: 90 },
    clusterRestSeconds: { enabled: false, value: 15 },
    restPauseSeconds: { enabled: false, value: 20 },
    pacing: { enabled: false, value: 300 },
  };
}

export const FORMAT_EXERCISE_CONTEXT: Record<SectionFormat, ExerciseFormatContext> = {
  untimed:             { showSets: true,  showPrescription: true,  showLoad: true,  intervalMode: "none" },
  for_time:            { showSets: true,  showPrescription: true,  showLoad: true,  intervalMode: "none" },
  // No rep count for TTE — load is the prescription; athlete goes until failure
  train_to_exhaustion: { showSets: true,  showPrescription: false, showLoad: true,  intervalMode: "none" },
  kcal_target:         { showSets: false, showPrescription: false, showLoad: false, intervalMode: "none" },
  emom:                { showSets: false, showPrescription: true,  showLoad: true,  intervalMode: "none" },
  complex_emom:        { showSets: false, showPrescription: true,  showLoad: true,  intervalMode: "minute" },
  even_odd:            { showSets: false, showPrescription: true,  showLoad: true,  intervalMode: "odd_even" },
  billat:              { showSets: false, showPrescription: true,  prescriptionSuffix: "max", showLoad: true,  intervalMode: "none" },
  amrap:               { showSets: false, showPrescription: true,  showLoad: true,  intervalMode: "none" },
  // Starting reps; athlete reduces as fatigue accumulates through the PR zone
  edt:                 { showSets: false, showPrescription: true,  prescriptionSuffix: "starting", showLoad: true,  intervalMode: "none" },
  // Death By: each exercise has its own start + step (like a per-exercise ladder)
  death_by:            { showSets: false, showPrescription: true,  ladderPrescription: true, showLoad: true,  intervalMode: "none" },
  tabata:              { showSets: false, showPrescription: true,  prescriptionSuffix: "per interval", showLoad: true,  intervalMode: "none" },
  custom_hiit:         { showSets: false, showPrescription: true,  prescriptionSuffix: "per interval", showLoad: true,  intervalMode: "none" },
  // showClusters exposes the second prescription dimension: clusters per set
  cluster:             { showSets: true,  showPrescription: true,  showClusters: true, showLoad: true, intervalMode: "none" },
  // HR ceiling/floor are section-level; per-exercise shows effort intensity
  hrr:                 { showSets: false, showPrescription: true,  prescriptionHint: "until HR ceiling", showLoad: true,  intervalMode: "none" },
  ladder_ascending:    { showSets: false, showPrescription: true,  ladderPrescription: true, showLoad: true, intervalMode: "none" },
  ladder_descending:   { showSets: false, showPrescription: true,  ladderPrescription: true, showLoad: true, intervalMode: "none" },
  // Pyramid reuses ladderPrescription to show peak + step inline
  pyramid:             { showSets: false, showPrescription: true,  ladderPrescription: true, showLoad: true, intervalMode: "none" },
  rest:                { showSets: false, showPrescription: false, showLoad: false, intervalMode: "none" },
};

export function makeDefaultExercise(): DraftExercise {
  return {
    localId: crypto.randomUUID(),
    name: "",
    sets: 3,
    prescriptionValue: 10,
    prescriptionUnit: "reps",
    prescriptionStep: null,
    clustersPerSet: null,
    loadValue: null,
    loadMode: "absolute",
    loadProgression: null,
    isBodyweight: false,
    supersetGroupId: null,
    intervalAssignment: null,
    advanced: makeDefaultAdvancedSettings(),
    variationsOpen: false,
    advancedOpen: false,
    variations: [],
    note: null,
  };
}

function fmins(secs: number | null | undefined): string {
  if (!secs) return "—";
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return s > 0 ? `${m}:${String(s).padStart(2, "0")}` : `${m}min`;
}

function fsecs(secs: number | null | undefined): string {
  return secs ? `${secs}s` : "—";
}

export function getFormatInstruction(format: SectionFormat, params: FormatParams): string {
  switch (format) {
    case "untimed":
      return "";
    case "for_time":
      return params.time_cap_seconds
        ? `Complete for time · cap ${fmins(params.time_cap_seconds)}`
        : "Complete for time";
    case "train_to_exhaustion":
      return params.rest_seconds
        ? `Sets to failure · ${fsecs(params.rest_seconds)} rest between sets`
        : "Sets to failure";
    case "kcal_target":
      return params.kcal_target
        ? `Machine to ${params.kcal_target}kcal${params.time_cap_seconds ? ` · cap ${fmins(params.time_cap_seconds)}` : ""}`
        : "Machine calorie target";
    case "emom":
      return `EMOM ${fmins(params.duration_seconds)} · every ${fsecs(params.interval_seconds)}`;
    case "complex_emom": {
      const perMinuteKeys = Object.keys(params)
        .filter((k) => /^interval_seconds_\d+$/.test(k))
        .sort((a, b) => Number(a.replace("interval_seconds_", "")) - Number(b.replace("interval_seconds_", "")));
      if (perMinuteKeys.length === 0) {
        return `Complex EMOM ${fmins(params.duration_seconds)} · ${fsecs(params.interval_seconds)} intervals`;
      }
      const minuteParts = perMinuteKeys.map((k) => {
        const min = k.replace("interval_seconds_", "");
        return `Min${min}: ${fsecs(params[k])}`;
      });
      return `Complex EMOM ${fmins(params.duration_seconds)} · ${minuteParts.join(", ")}`;
    }
    case "even_odd":
      return `E/O EMOM ${fmins(params.duration_seconds)} · alternate odd/even minutes`;
    case "billat":
      return `${params.cycles ?? 8}× ${fsecs(params.work_seconds)} @vVO2max / ${fsecs(params.rest_seconds)} @50%`;
    case "amrap":
      return `AMRAP ${fmins(params.duration_seconds)}`;
    case "edt":
      return `EDT ${fmins(params.duration_seconds)} · accumulate max reps, reduce as needed`;
    case "death_by":
      return `EMOM · +N/round per exercise until failure${params.max_rounds ? ` · max ${params.max_rounds} rounds` : ""}`;
    case "tabata":
      return `Tabata · ${fsecs(params.work_seconds)} on / ${fsecs(params.rest_seconds)} off × ${params.rounds ?? 8} rounds`;
    case "custom_hiit":
      return `${fsecs(params.work_seconds)} on / ${fsecs(params.rest_seconds)} off × ${params.rounds ?? 10} rounds`;
    case "cluster":
      return params.intra_rest_seconds
        ? `Cluster sets · ${fsecs(params.intra_rest_seconds)} intra-set rest`
        : "Cluster sets";
    case "hrr":
      return `Work → rest to ${params.hr_floor_bpm ?? 130}bpm · resume at ${params.hr_ceiling_bpm ?? 175}bpm${params.cycles ? ` · ${params.cycles} cycles` : ""}`;
    case "ladder_ascending":
      return `Ladder ↑${params.time_cap_seconds ? ` · cap ${fmins(params.time_cap_seconds)}` : ""}`;
    case "ladder_descending":
      return `Ladder ↓ (for time)${params.time_cap_seconds ? ` · cap ${fmins(params.time_cap_seconds)}` : ""}`;
    case "pyramid":
      return `Pyramid — up to peak then back down${params.time_cap_seconds ? ` · cap ${fmins(params.time_cap_seconds)}` : ""}`;
    case "rest":
      return "";
  }
}

export function makeDefaultSection(): DraftSection {
  return {
    localId: crypto.randomUUID(),
    name: "",
    format: "untimed",
    formatParams: {},
    scoreable: false,
    scoreType: null,
    emomScoringMode: null,
    emomAmrapScoringStyle: null,
    restAfterSeconds: null,
    exercises: [],
    note: null,
  };
}

export function adaptExerciseToDestination(
  exercise: DraftExercise,
  destFormat: SectionFormat,
): DraftExercise {
  const destCtx = FORMAT_EXERCISE_CONTEXT[destFormat];
  return {
    ...exercise,
    prescriptionStep: destCtx.ladderPrescription ? (exercise.prescriptionStep ?? 1) : null,
    intervalAssignment: null,
    clustersPerSet: destCtx.showClusters ? (exercise.clustersPerSet ?? 5) : null,
    advancedOpen: false,
    variationsOpen: false,
  };
}
