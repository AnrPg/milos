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

type UiTranslate = (key: string, values?: Record<string, string | number>) => string;

export function getEmomScoringModeLabels(i18n: UiTranslate): Record<EmomScoringMode, string> {
  return {
    for_time: i18n("emomModeForTime"), for_quality: i18n("emomModeForQuality"),
    amrap: i18n("emomModeAmrap"), to_failure: i18n("emomModeToFailure"),
  };
}

export function getEmomScoringModeDescriptions(i18n: UiTranslate): Record<EmomScoringMode, string> {
  return {
    for_time: i18n("emomModeForTimeDescription"), for_quality: i18n("emomModeForQualityDescription"),
    amrap: i18n("emomModeAmrapDescription"), to_failure: i18n("emomModeToFailureDescription"),
  };
}

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

const FORMAT_GROUP_DEFINITIONS: { labelKey: string; formats: SectionFormat[] }[] = [
  {
    labelKey: "formatGroupBasic",
    formats: ["untimed", "for_time", "train_to_exhaustion", "kcal_target"],
  },
  {
    labelKey: "formatGroupInterval",
    formats: ["emom", "complex_emom", "even_odd", "billat"],
  },
  {
    labelKey: "formatGroupSustainedCardio",
    formats: ["amrap", "edt", "death_by"],
  },
  {
    labelKey: "formatGroupSetBased",
    formats: ["tabata", "custom_hiit", "cluster", "hrr"],
  },
  {
    labelKey: "formatGroupProgressive",
    formats: ["ladder_ascending", "ladder_descending", "pyramid"],
  },
  { labelKey: "formatGroupRest", formats: ["rest"] },
];

export function getFormatGroups(i18n: UiTranslate) {
  return FORMAT_GROUP_DEFINITIONS.map(({labelKey, formats}) => ({label: i18n(labelKey), formats}));
}

const ALL_SECTION_FORMATS: SectionFormat[] = [
  "untimed", "for_time", "train_to_exhaustion", "kcal_target", "emom", "complex_emom", "even_odd",
  "billat", "amrap", "edt", "death_by", "tabata", "custom_hiit", "cluster", "hrr",
  "ladder_ascending", "ladder_descending", "pyramid", "rest",
];

export function getFormatLabels(i18n: UiTranslate): Record<SectionFormat, string> {
  return Object.fromEntries(ALL_SECTION_FORMATS.map((format) => [format, i18n(`formatLabel_${format}`)])) as Record<SectionFormat, string>;
}

const FORMAT_TOOLTIP_SCORE_FORMATS = new Set<SectionFormat>([
  "for_time", "train_to_exhaustion", "kcal_target", "emom", "complex_emom", "amrap", "edt",
  "death_by", "hrr", "ladder_descending", "pyramid",
]);

export function getFormatTooltips(i18n: UiTranslate) {
  return Object.fromEntries(ALL_SECTION_FORMATS.map((format) => [format, {
    bestFor: i18n(`formatTooltip_${format}_bestFor`),
    trains: i18n(`formatTooltip_${format}_trains`),
    how: i18n(`formatTooltip_${format}_how`),
    ...(FORMAT_TOOLTIP_SCORE_FORMATS.has(format) ? {score: i18n(`formatTooltip_${format}_score`)} : {}),
  }])) as Record<SectionFormat, {bestFor: string; trains: string; how: string; score?: string}>;
}

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
  billat:              { showSets: false, showPrescription: true,  prescriptionSuffix: "prescriptionSuffixMax", showLoad: true,  intervalMode: "none" },
  amrap:               { showSets: false, showPrescription: true,  showLoad: true,  intervalMode: "none" },
  // Starting reps; athlete reduces as fatigue accumulates through the PR zone
  edt:                 { showSets: false, showPrescription: true,  prescriptionSuffix: "prescriptionSuffixStarting", showLoad: true,  intervalMode: "none" },
  // Death By: each exercise has its own start + step (like a per-exercise ladder)
  death_by:            { showSets: false, showPrescription: true,  ladderPrescription: true, showLoad: true,  intervalMode: "none" },
  tabata:              { showSets: false, showPrescription: true,  prescriptionSuffix: "prescriptionSuffixPerInterval", showLoad: true,  intervalMode: "none" },
  custom_hiit:         { showSets: false, showPrescription: true,  prescriptionSuffix: "prescriptionSuffixPerInterval", showLoad: true,  intervalMode: "none" },
  // showClusters exposes the second prescription dimension: clusters per set
  cluster:             { showSets: true,  showPrescription: true,  showClusters: true, showLoad: true, intervalMode: "none" },
  // HR ceiling/floor are section-level; per-exercise shows effort intensity
  hrr:                 { showSets: false, showPrescription: true,  prescriptionHint: "prescriptionHintUntilHrCeiling", showLoad: true,  intervalMode: "none" },
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

function fmins(i18n: UiTranslate, secs: number | null | undefined): string {
  if (!secs) return "—";
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return s > 0 ? i18n("minutesSecondsShort", {minutes: m, seconds: String(s).padStart(2, "0")}) : i18n("minutesShort", {value: m});
}

function fsecs(i18n: UiTranslate, secs: number | null | undefined): string {
  return secs ? i18n("secondsShort", {value: secs}) : "—";
}

export function getFormatInstruction(i18n: UiTranslate, format: SectionFormat, params: FormatParams): string {
  switch (format) {
    case "untimed":
      return "";
    case "for_time":
      return params.time_cap_seconds
        ? i18n("instructionForTimeWithCap", {cap: fmins(i18n, params.time_cap_seconds)})
        : i18n("instructionForTime");
    case "train_to_exhaustion":
      return params.rest_seconds
        ? i18n("instructionFailureWithRest", {rest: fsecs(i18n, params.rest_seconds)})
        : i18n("instructionFailure");
    case "kcal_target":
      return params.kcal_target
        ? i18n(params.time_cap_seconds ? "instructionCaloriesWithCap" : "instructionCalories", {
            calories: params.kcal_target, cap: fmins(i18n, params.time_cap_seconds),
          })
        : i18n("instructionCaloriesTarget");
    case "emom":
      return i18n("instructionEmom", {duration: fmins(i18n, params.duration_seconds), interval: fsecs(i18n, params.interval_seconds)});
    case "complex_emom": {
      const perMinuteKeys = Object.keys(params)
        .filter((k) => /^interval_seconds_\d+$/.test(k))
        .sort((a, b) => Number(a.replace("interval_seconds_", "")) - Number(b.replace("interval_seconds_", "")));
      if (perMinuteKeys.length === 0) {
        return i18n("instructionComplexEmom", {duration: fmins(i18n, params.duration_seconds), interval: fsecs(i18n, params.interval_seconds)});
      }
      const minuteParts = perMinuteKeys.map((k) => {
        const min = k.replace("interval_seconds_", "");
        return i18n("instructionMinuteInterval", {minute: min, interval: fsecs(i18n, params[k])});
      });
      return i18n("instructionComplexEmomVariable", {duration: fmins(i18n, params.duration_seconds), intervals: minuteParts.join(", ")});
    }
    case "even_odd":
      return i18n("instructionEvenOddEmom", {duration: fmins(i18n, params.duration_seconds)});
    case "billat":
      return i18n("instructionBillat", {cycles: params.cycles ?? 8, work: fsecs(i18n, params.work_seconds), rest: fsecs(i18n, params.rest_seconds)});
    case "amrap":
      return i18n("instructionAmrap", {duration: fmins(i18n, params.duration_seconds)});
    case "edt":
      return i18n("instructionEdt", {duration: fmins(i18n, params.duration_seconds)});
    case "death_by":
      return i18n(params.max_rounds ? "instructionDeathByWithMax" : "instructionDeathBy", {rounds: params.max_rounds ?? 0});
    case "tabata":
      return i18n("instructionTabata", {work: fsecs(i18n, params.work_seconds), rest: fsecs(i18n, params.rest_seconds), rounds: params.rounds ?? 8});
    case "custom_hiit":
      return i18n("instructionCustomHiit", {work: fsecs(i18n, params.work_seconds), rest: fsecs(i18n, params.rest_seconds), rounds: params.rounds ?? 10});
    case "cluster":
      return params.intra_rest_seconds
        ? i18n("instructionClusterWithRest", {rest: fsecs(i18n, params.intra_rest_seconds)})
        : i18n("instructionCluster");
    case "hrr":
      return i18n(params.cycles ? "instructionHrrWithCycles" : "instructionHrr", {floor: params.hr_floor_bpm ?? 130, ceiling: params.hr_ceiling_bpm ?? 175, cycles: params.cycles ?? 0});
    case "ladder_ascending":
      return i18n(params.time_cap_seconds ? "instructionLadderAscendingWithCap" : "instructionLadderAscending", {cap: fmins(i18n, params.time_cap_seconds)});
    case "ladder_descending":
      return i18n(params.time_cap_seconds ? "instructionLadderDescendingWithCap" : "instructionLadderDescending", {cap: fmins(i18n, params.time_cap_seconds)});
    case "pyramid":
      return i18n(params.time_cap_seconds ? "instructionPyramidWithCap" : "instructionPyramid", {cap: fmins(i18n, params.time_cap_seconds)});
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
