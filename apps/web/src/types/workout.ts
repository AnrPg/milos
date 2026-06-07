export type PrescriptionUnit = "reps" | "secs" | "kcal";
export type LoadMode = "absolute" | "pct_1rm";
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
  | "load";

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
  loadValue: number | null;
  loadMode: LoadMode;
  isBodyweight: boolean;
  supersetGroupId: string | null;
  intervalAssignment: number | null;
  advanced: AdvancedSettings;
  variationsOpen: boolean;
  advancedOpen: boolean;
  variations: DraftVariation[];
};

export type DraftSection = {
  localId: string;
  name: string;
  format: SectionFormat;
  formatParams: FormatParams;
  scoreable: boolean;
  scoreType: ScoreType | null;
  exercises: DraftExercise[];
};

export type DraftWorkoutState = {
  draftId: string | null;
  title: string;
  type: WorkoutType | null;
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
    bestFor: "Pacing and power output",
    trains: "Power, pacing",
    how: "Complete prescribed work every minute on the minute.",
  },
  complex_emom: {
    bestFor: "Mixed modality pacing",
    trains: "Varied skills, pacing",
    how: "Alternate different work across the minute structure.",
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
  ],
  complex_emom: [
    { key: "duration_seconds", defaultValue: 600, required: true },
    { key: "interval_seconds", defaultValue: 60, required: true },
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
    { key: "start_reps", defaultValue: 1, required: true },
    { key: "step_reps", defaultValue: 1, required: true },
    { key: "ladder_cap", defaultValue: 20 },
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
    { key: "sets", defaultValue: 5, required: true },
  ],
  hrr: [{ key: "effort_seconds", defaultValue: 30, required: true }, { key: "hr_zone", defaultValue: 3 }],
  ladder_ascending: [
    { key: "start_reps", defaultValue: 1, required: true },
    { key: "step_reps", defaultValue: 1, required: true },
    { key: "ladder_cap", defaultValue: 10 },
  ],
  ladder_descending: [
    { key: "start_reps", defaultValue: 10, required: true },
    { key: "step_reps", defaultValue: 1, required: true },
    { key: "min_reps", defaultValue: 1, required: true },
  ],
  pyramid: [
    { key: "peak_reps", defaultValue: 10, required: true },
    { key: "step_reps", defaultValue: 2, required: true },
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

export function makeDefaultExercise(): DraftExercise {
  return {
    localId: crypto.randomUUID(),
    name: "",
    sets: 3,
    prescriptionValue: 10,
    prescriptionUnit: "reps",
    loadValue: null,
    loadMode: "absolute",
    isBodyweight: false,
    supersetGroupId: null,
    intervalAssignment: null,
    advanced: makeDefaultAdvancedSettings(),
    variationsOpen: false,
    advancedOpen: false,
    variations: [],
  };
}

export function makeDefaultSection(): DraftSection {
  return {
    localId: crypto.randomUUID(),
    name: "",
    format: "untimed",
    formatParams: {},
    scoreable: false,
    scoreType: null,
    exercises: [],
  };
}
