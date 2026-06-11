import { create } from "zustand";

import type {
  AdvancedSettings,
  DraftExercise,
  DraftSection,
  DraftVariation,
  DraftWorkoutState,
  EmomScoringMode,
  FormatParams,
  LoadMode,
  LoadProgression,
  MobileView,
  PrescriptionUnit,
  ScoreType,
  SectionFormat,
  WorkoutType,
} from "@/types/workout";
import { AUTO_SCORE_MAP, FORMAT_EXERCISE_CONTEXT, adaptExerciseToDestination, makeDefaultAdvancedSettings, makeDefaultExercise, makeDefaultFormatParams, makeDefaultSection } from "@/types/workout";

type SaveStatus = "idle" | "saving" | "saved" | "error";

type WorkoutCreationStore = DraftWorkoutState & {
  saveStatus: SaveStatus;
  selectedSectionId: string | null;
  sectionConfigOpen: boolean;
  leftCollapsed: boolean;
  rightCollapsed: boolean;
  mobileView: MobileView;
  initDraft: (id: string) => void;
  resetDraft: () => void;
  loadFromDraftData: (data: unknown) => void;
  setTitle: (title: string) => void;
  setType: (type: WorkoutType) => void;
  setSaveStatus: (status: SaveStatus) => void;
  addSection: () => void;
  selectSection: (id: string | null) => void;
  setSectionConfigOpen: (value: boolean) => void;
  updateSection: (id: string, patch: Partial<DraftSection>) => void;
  deleteSection: (id: string) => void;
  reorderSections: (fromId: string, toId: string) => void;
  setFormat: (sectionId: string, format: SectionFormat) => void;
  setFormatParams: (sectionId: string, params: FormatParams) => void;
  addExercise: (sectionId: string) => void;
  updateExercise: (sectionId: string, exerciseId: string, patch: Partial<DraftExercise>) => void;
  deleteExercise: (sectionId: string, exerciseId: string) => void;
  reorderExercises: (sectionId: string, fromId: string, toId: string) => void;
  moveExercise: (exerciseId: string, fromSectionId: string, toSectionId: string) => void;
  toggleVariationsPanel: (sectionId: string, exerciseId: string) => void;
  addVariation: (sectionId: string, exerciseId: string, scaleLevelSlug: string) => void;
  updateVariation: (
    sectionId: string,
    exerciseId: string,
    slug: string,
    patch: Partial<DraftVariation>,
  ) => void;
  excludeVariation: (sectionId: string, exerciseId: string, slug: string) => void;
  restoreVariation: (sectionId: string, exerciseId: string, slug: string) => void;
  toggleAdvancedPanel: (sectionId: string, exerciseId: string) => void;
  toggleAdvancedSetting: (
    sectionId: string,
    exerciseId: string,
    setting: keyof DraftExercise["advanced"],
  ) => void;
  updateAdvancedValue: (
    sectionId: string,
    exerciseId: string,
    setting: keyof DraftExercise["advanced"],
    value: number | string,
  ) => void;
  setMobileView: (view: MobileView) => void;
  setLeftCollapsed: (value: boolean) => void;
  setRightCollapsed: (value: boolean) => void;
  toApiPayload: () => unknown;
};

function parseSectionFormat(value: unknown): SectionFormat {
  const valid: SectionFormat[] = [
    "untimed", "for_time", "train_to_exhaustion", "kcal_target", "emom",
    "complex_emom", "even_odd", "billat", "amrap", "edt", "death_by",
    "tabata", "custom_hiit", "cluster", "hrr", "ladder_ascending",
    "ladder_descending", "pyramid", "rest",
  ];
  return valid.includes(value as SectionFormat) ? (value as SectionFormat) : "untimed";
}

function parseScoreType(value: unknown): ScoreType | null {
  const valid: ScoreType[] = ["time", "reps", "weight", "rounds", "rounds+reps", "kcal", "hr_drop", "load", "accumulated_work_time", "pass_fail", "intervals_survived"];
  return valid.includes(value as ScoreType) ? (value as ScoreType) : null;
}

function parseEmomScoringMode(value: unknown): EmomScoringMode | null {
  return (value === "for_time" || value === "for_quality" || value === "amrap" || value === "to_failure")
    ? value
    : null;
}

function parseEmomAmrapScoringStyle(value: unknown): "grand_total" | "lowest_window" | null {
  return (value === "grand_total" || value === "lowest_window") ? value : null;
}

function parsePrescriptionUnit(value: unknown): PrescriptionUnit {
  return (value === "reps" || value === "secs" || value === "kcal") ? value : "reps";
}

function parseLoadMode(value: unknown): LoadMode {
  return (value === "absolute" || value === "pct_1rm" || value === "bw") ? value : "absolute";
}

function parseLoadProgression(value: unknown): LoadProgression | null {
  if (!value || typeof value !== "object") return null;
  const v = value as Record<string, unknown>;
  const mode = v.mode === "linear" || v.mode === "per_set" ? v.mode : "linear";
  return {
    mode,
    startValue: Number(v.start_value ?? 0),
    startMode: parseLoadMode(v.start_mode),
    stepValue: Number(v.step_value ?? 0),
    perSetValues: Array.isArray(v.per_set_values) ? v.per_set_values.map(Number) : [],
  };
}

function parseAdvancedSettings(src: Record<string, unknown>): AdvancedSettings {
  const defaults = makeDefaultAdvancedSettings();
  return {
    hrZone: src.hr_zone != null ? { enabled: true, value: Number(src.hr_zone) } : defaults.hrZone,
    tempo: src.tempo != null ? { enabled: true, value: String(src.tempo) } : defaults.tempo,
    restSeconds: src.rest_seconds != null ? { enabled: true, value: Number(src.rest_seconds) } : defaults.restSeconds,
    clusterRestSeconds: src.cluster_rest_seconds != null ? { enabled: true, value: Number(src.cluster_rest_seconds) } : defaults.clusterRestSeconds,
    restPauseSeconds: src.rest_pause_seconds != null ? { enabled: true, value: Number(src.rest_pause_seconds) } : defaults.restPauseSeconds,
    pacing: src.pacing != null ? { enabled: true, value: Number(src.pacing) } : defaults.pacing,
  };
}

function parseDraftExercise(src: unknown): DraftExercise {
  const defaults = makeDefaultExercise();
  if (!src || typeof src !== "object") return defaults;
  const e = src as Record<string, unknown>;

  const rawVariations = Array.isArray(e.variations) ? e.variations : [];
  const variations: DraftVariation[] = rawVariations.map((v: unknown) => {
    const vr = (v || {}) as Record<string, unknown>;
    return {
      scaleLevelSlug: String(vr.scale_level_slug ?? ""),
      exerciseNameOverride: vr.exercise_name_override != null ? String(vr.exercise_name_override) : null,
      sets: vr.sets != null ? Number(vr.sets) : null,
      prescriptionValue: vr.prescription_value != null ? Number(vr.prescription_value) : null,
      prescriptionUnit: vr.prescription_unit != null ? parsePrescriptionUnit(vr.prescription_unit) : null,
      loadValue: vr.load_value != null ? Number(vr.load_value) : null,
      loadMode: vr.load_mode != null ? parseLoadMode(vr.load_mode) : null,
      excluded: Boolean(vr.excluded),
    };
  });

  return {
    localId: crypto.randomUUID(),
    name: typeof e.name === "string" ? e.name : "",
    sets: e.sets != null ? Number(e.sets) : defaults.sets,
    prescriptionValue: e.prescription_value != null ? Number(e.prescription_value) : defaults.prescriptionValue,
    prescriptionUnit: parsePrescriptionUnit(e.prescription_unit),
    prescriptionStep: e.prescription_step != null ? Number(e.prescription_step) : null,
    clustersPerSet: null,
    loadValue: e.load_value != null ? Number(e.load_value) : null,
    loadMode: parseLoadMode(e.load_mode),
    loadProgression: parseLoadProgression(e.load_progression),
    isBodyweight: Boolean(e.is_bodyweight),
    supersetGroupId: e.superset_group_id != null ? String(e.superset_group_id) : null,
    intervalAssignment: e.interval_assignment != null ? Number(e.interval_assignment) : null,
    advanced: parseAdvancedSettings(e as Record<string, unknown>),
    variationsOpen: false,
    advancedOpen: false,
    variations,
  };
}

function parseDraftSections(raw: unknown): DraftSection[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((s: unknown) => {
    if (!s || typeof s !== "object") return makeDefaultSection();
    const sec = s as Record<string, unknown>;
    const timerConfig = (sec.timer_config && typeof sec.timer_config === "object")
      ? sec.timer_config as Record<string, unknown>
      : {};
    const format = parseSectionFormat(timerConfig.type);
    const formatParamRaw = { ...timerConfig };
    delete formatParamRaw.type;
    const formatParams: FormatParams = {};
    for (const [k, v] of Object.entries(formatParamRaw)) {
      formatParams[k] = v != null ? Number(v) : null;
    }
    const scoreConfig = (sec.score_config && typeof sec.score_config === "object")
      ? sec.score_config as Record<string, unknown>
      : null;
    const scoreType = scoreConfig ? parseScoreType(scoreConfig.type) : null;
    const emomScoringMode = scoreConfig ? parseEmomScoringMode(scoreConfig.scoring_mode) : null;
    const emomAmrapScoringStyle = scoreConfig ? parseEmomAmrapScoringStyle(scoreConfig.amrap_scoring_style) : null;
    const exercises = Array.isArray(sec.exercises)
      ? sec.exercises.map(parseDraftExercise)
      : [];
    return {
      localId: crypto.randomUUID(),
      name: typeof sec.name === "string" ? sec.name : "",
      format,
      formatParams: Object.keys(formatParams).length > 0 ? formatParams : makeDefaultFormatParams(format),
      scoreable: Boolean(sec.scoreable),
      scoreType,
      emomScoringMode,
      emomAmrapScoringStyle,
      restAfterSeconds: sec.rest_after_seconds != null ? Number(sec.rest_after_seconds) : null,
      exercises,
    };
  });
}

function parseWorkoutType(value: unknown): WorkoutType | null {
  if (
    value === "crossfit" ||
    value === "strength" ||
    value === "gymnastics" ||
    value === "aerobics" ||
    value === "flexibility" ||
    value === "recovery"
  ) {
    return value;
  }

  return null;
}

export const useWorkoutCreationStore = create<WorkoutCreationStore>((set, get) => ({
  draftId: null,
  title: "",
  type: null,
  sections: [],
  saveStatus: "idle",
  selectedSectionId: null,
  sectionConfigOpen: false,
  leftCollapsed: false,
  rightCollapsed: false,
  mobileView: "sections",

  initDraft: (id) => set({ draftId: id }),

  resetDraft: () =>
    set({ draftId: null, title: "", type: null, sections: [], selectedSectionId: null, sectionConfigOpen: false }),

  loadFromDraftData: (data) => {
    if (!data || typeof data !== "object") return;
    const record = data as Record<string, unknown>;
    // Prefer draft_data (has full state including load_progression) over materialized sections.
    const source =
      record.draft_data && typeof record.draft_data === "object"
        ? (record.draft_data as Record<string, unknown>)
        : record;
    set({
      title: typeof source.title === "string" ? source.title : (typeof record.title === "string" ? record.title : ""),
      type: parseWorkoutType(source.type ?? record.type),
      sections: parseDraftSections(source.sections),
    });
  },

  setTitle: (title) => set({ title }),
  setType: (type) => set({ type }),
  setSaveStatus: (saveStatus) => set({ saveStatus }),

  addSection: () =>
    set((state) => {
      const section = makeDefaultSection();
      return {
        sections: [...state.sections, section],
        selectedSectionId: section.localId,
        sectionConfigOpen: true,
      };
    }),

  selectSection: (id) => set({ selectedSectionId: id, sectionConfigOpen: id !== null }),
  setSectionConfigOpen: (sectionConfigOpen) => set({ sectionConfigOpen }),

  updateSection: (id, patch) =>
    set((state) => ({
      sections: state.sections.map((section) =>
        section.localId === id ? { ...section, ...patch } : section,
      ),
    })),

  deleteSection: (id) =>
    set((state) => ({
      sections: state.sections.filter((section) => section.localId !== id),
      selectedSectionId: state.selectedSectionId === id ? null : state.selectedSectionId,
    })),

  reorderSections: (fromId, toId) =>
    set((state) => {
      const sections = [...state.sections];
      const fromIndex = sections.findIndex((section) => section.localId === fromId);
      const toIndex = sections.findIndex((section) => section.localId === toId);

      if (fromIndex === -1 || toIndex === -1) return state;

      const [moved] = sections.splice(fromIndex, 1);
      sections.splice(toIndex, 0, moved);

      return { sections };
    }),

  setFormat: (sectionId, format) =>
    set((state) => ({
      sections: state.sections.map((section) => {
        if (section.localId !== sectionId) return section;

        const autoScore = AUTO_SCORE_MAP[format] ?? null;

        return {
          ...section,
          format,
          formatParams: makeDefaultFormatParams(format),
          scoreable: format === "rest" ? false : section.scoreable,
          scoreType: autoScore,
        };
      }),
    })),

  setFormatParams: (sectionId, params) =>
    set((state) => ({
      sections: state.sections.map((section) =>
        section.localId === sectionId ? { ...section, formatParams: params } : section,
      ),
    })),

  addExercise: (sectionId) =>
    set((state) => ({
      sections: state.sections.map((section) => {
        if (section.localId !== sectionId) return section;
        return {
          ...section,
          exercises: [...section.exercises, makeDefaultExercise()],
        };
      }),
    })),

  updateExercise: (sectionId, exerciseId, patch) =>
    set((state) => ({
      sections: state.sections.map((section) => {
        if (section.localId !== sectionId) return section;
        return {
          ...section,
          exercises: section.exercises.map((exercise) =>
            exercise.localId === exerciseId ? { ...exercise, ...patch } : exercise,
          ),
        };
      }),
    })),

  deleteExercise: (sectionId, exerciseId) =>
    set((state) => ({
      sections: state.sections.map((section) => {
        if (section.localId !== sectionId) return section;
        return {
          ...section,
          exercises: section.exercises.filter((exercise) => exercise.localId !== exerciseId),
        };
      }),
    })),

  reorderExercises: (sectionId, fromId, toId) =>
    set((state) => ({
      sections: state.sections.map((section) => {
        if (section.localId !== sectionId) return section;

        const exercises = [...section.exercises];
        const fromIndex = exercises.findIndex((exercise) => exercise.localId === fromId);
        const toIndex = exercises.findIndex((exercise) => exercise.localId === toId);

        if (fromIndex === -1 || toIndex === -1) return section;

        const [moved] = exercises.splice(fromIndex, 1);
        exercises.splice(toIndex, 0, moved);

        return { ...section, exercises };
      }),
    })),

  moveExercise: (exerciseId, fromSectionId, toSectionId) =>
    set((state) => {
      const fromSection = state.sections.find((section) => section.localId === fromSectionId);
      const exercise = fromSection?.exercises.find((item) => item.localId === exerciseId);
      const toSection = state.sections.find((section) => section.localId === toSectionId);

      if (!exercise || !toSection || fromSectionId === toSectionId) return state;

      return {
        sections: state.sections.map((section) => {
          if (section.localId === fromSectionId) {
            return {
              ...section,
              exercises: section.exercises.filter((item) => item.localId !== exerciseId),
            };
          }

          if (section.localId === toSectionId) {
            return {
              ...section,
              exercises: [...section.exercises, adaptExerciseToDestination(exercise, toSection.format)],
            };
          }

          return section;
        }),
      };
    }),

  toggleVariationsPanel: (sectionId, exerciseId) =>
    set((state) => ({
      sections: state.sections.map((section) => {
        if (section.localId !== sectionId) return section;
        return {
          ...section,
          exercises: section.exercises.map((exercise) =>
            exercise.localId === exerciseId
              ? { ...exercise, variationsOpen: !exercise.variationsOpen }
              : exercise,
          ),
        };
      }),
    })),

  addVariation: (sectionId, exerciseId, scaleLevelSlug) =>
    set((state) => ({
      sections: state.sections.map((section) => {
        if (section.localId !== sectionId) return section;

        return {
          ...section,
          exercises: section.exercises.map((exercise) => {
            if (exercise.localId !== exerciseId) return exercise;
            if (exercise.variations.some((variation) => variation.scaleLevelSlug === scaleLevelSlug)) {
              return exercise;
            }

            return {
              ...exercise,
              variations: [
                ...exercise.variations,
                {
                  scaleLevelSlug,
                  exerciseNameOverride: null,
                  sets: null,
                  prescriptionValue: null,
                  prescriptionUnit: null,
                  loadValue: null,
                  loadMode: null,
                  excluded: false,
                },
              ],
            };
          }),
        };
      }),
    })),

  updateVariation: (sectionId, exerciseId, slug, patch) =>
    set((state) => ({
      sections: state.sections.map((section) => {
        if (section.localId !== sectionId) return section;

        return {
          ...section,
          exercises: section.exercises.map((exercise) => {
            if (exercise.localId !== exerciseId) return exercise;

            return {
              ...exercise,
              variations: exercise.variations.map((variation) =>
                variation.scaleLevelSlug === slug ? { ...variation, ...patch } : variation,
              ),
            };
          }),
        };
      }),
    })),

  excludeVariation: (sectionId, exerciseId, slug) =>
    get().updateVariation(sectionId, exerciseId, slug, { excluded: true }),

  restoreVariation: (sectionId, exerciseId, slug) =>
    get().updateVariation(sectionId, exerciseId, slug, { excluded: false }),

  toggleAdvancedPanel: (sectionId, exerciseId) =>
    set((state) => ({
      sections: state.sections.map((section) => {
        if (section.localId !== sectionId) return section;
        return {
          ...section,
          exercises: section.exercises.map((exercise) =>
            exercise.localId === exerciseId
              ? { ...exercise, advancedOpen: !exercise.advancedOpen }
              : exercise,
          ),
        };
      }),
    })),

  toggleAdvancedSetting: (sectionId, exerciseId, setting) =>
    set((state) => ({
      sections: state.sections.map((section) => {
        if (section.localId !== sectionId) return section;
        return {
          ...section,
          exercises: section.exercises.map((exercise) => {
            if (exercise.localId !== exerciseId) return exercise;
            return {
              ...exercise,
              advanced: {
                ...exercise.advanced,
                [setting]: {
                  ...exercise.advanced[setting],
                  enabled: !exercise.advanced[setting].enabled,
                },
              },
            };
          }),
        };
      }),
    })),

  updateAdvancedValue: (sectionId, exerciseId, setting, value) =>
    set((state) => ({
      sections: state.sections.map((section) => {
        if (section.localId !== sectionId) return section;
        return {
          ...section,
          exercises: section.exercises.map((exercise) => {
            if (exercise.localId !== exerciseId) return exercise;
            return {
              ...exercise,
              advanced: {
                ...exercise.advanced,
                [setting]: {
                  ...exercise.advanced[setting],
                  value,
                },
              },
            };
          }),
        };
      }),
    })),

  setMobileView: (mobileView) => set({ mobileView }),
  setLeftCollapsed: (leftCollapsed) => set({ leftCollapsed }),
  setRightCollapsed: (rightCollapsed) => set({ rightCollapsed }),

  toApiPayload: () => {
    const { title, type, sections } = get();

    function deriveLadderTimerParams(section: DraftSection): Record<string, number> {
      const first = section.exercises[0];
      if (!first) return {};
      const startReps = first.prescriptionValue;
      const stepReps = first.prescriptionStep ?? 1;

      if (section.format === "ladder_ascending") {
        return { start_reps: startReps, step_reps: stepReps };
      }
      if (section.format === "ladder_descending") {
        return { start_reps: startReps, step_reps: stepReps };
      }
      if (section.format === "pyramid") {
        return { peak_reps: startReps, step_reps: stepReps };
      }
      // death_by: derive from first exercise (backend compat); per-exercise values in exercise payload
      if (section.format === "death_by") {
        return { start_reps: startReps, step_reps: stepReps };
      }
      return {};
    }

    return {
      title,
      type,
      sections: sections.map((section) => ({
        name: section.name,
        timer_config: {
          type: section.format,
          ...section.formatParams,
          ...deriveLadderTimerParams(section),
        },
        scoreable: section.scoreable,
        score_config: section.scoreType ? { type: section.scoreType } : null,
        rest_after_seconds: section.restAfterSeconds ?? null,
        exercises: section.exercises.map((exercise) => ({
          name: exercise.name,
          sets: exercise.sets,
          prescription_value: exercise.prescriptionValue,
          prescription_unit: exercise.prescriptionUnit,
          prescription_step: exercise.prescriptionStep,
          is_bodyweight: exercise.loadMode === "bw",
          load_value: exercise.loadMode === "bw" ? null : exercise.loadProgression ? exercise.loadProgression.startValue : exercise.loadValue,
          load_mode: exercise.loadMode === "bw" ? "bw" : exercise.loadProgression ? exercise.loadProgression.startMode : exercise.loadMode,
          load_progression: exercise.loadProgression
            ? {
                mode: exercise.loadProgression.mode,
                start_value: exercise.loadProgression.startValue,
                start_mode: exercise.loadProgression.startMode,
                step_value: exercise.loadProgression.stepValue,
                per_set_values: exercise.loadProgression.perSetValues,
              }
            : null,
          superset_group_id: exercise.supersetGroupId,
          interval_assignment: exercise.intervalAssignment,
          hr_zone: exercise.advanced.hrZone.enabled ? exercise.advanced.hrZone.value : null,
          tempo: exercise.advanced.tempo.enabled ? exercise.advanced.tempo.value : null,
          rest_seconds: exercise.advanced.restSeconds.enabled
            ? exercise.advanced.restSeconds.value
            : null,
          cluster_rest_seconds: exercise.advanced.clusterRestSeconds.enabled
            ? exercise.advanced.clusterRestSeconds.value
            : null,
          rest_pause_seconds: exercise.advanced.restPauseSeconds.enabled
            ? exercise.advanced.restPauseSeconds.value
            : null,
          pacing: exercise.advanced.pacing.enabled ? exercise.advanced.pacing.value : null,
          variations: exercise.variations.map((variation) => ({
            scale_level_slug: variation.scaleLevelSlug,
            exercise_name_override: variation.exerciseNameOverride,
            sets: variation.sets,
            prescription_value: variation.prescriptionValue,
            prescription_unit: variation.prescriptionUnit,
            load_value: variation.loadValue,
            load_mode: variation.loadMode,
            excluded: variation.excluded,
          })),
        })),
      })),
    };
  },
}));

export function isSectionComplete(section: DraftSection): boolean {
  if (!section.name) return false;

  const ctx = FORMAT_EXERCISE_CONTEXT[section.format];
  const needsExercises = section.format !== "rest" && section.format !== "kcal_target";

  if (needsExercises && section.exercises.length === 0) return false;

  return section.exercises.every((exercise) => {
    if (!exercise.name) return false;
    if (ctx.showSets && exercise.sets <= 0) return false;
    if (ctx.showPrescription && !ctx.prescriptionHint && !ctx.ladderPrescription && exercise.prescriptionValue <= 0) return false;
    return true;
  });
}

export function isPublishReady(state: Pick<DraftWorkoutState, "title" | "type" | "sections">): boolean {
  if (!state.title || !state.type) return false;
  if (state.sections.length === 0) return false;
  return state.sections.every(isSectionComplete);
}

export function completionSummary(sections: DraftSection[]): string {
  const complete = sections.filter(isSectionComplete).length;
  return `${complete} of ${sections.length} sections complete`;
}
