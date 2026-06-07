import { create } from "zustand";

import type {
  DraftExercise,
  DraftSection,
  DraftVariation,
  DraftWorkoutState,
  FormatParams,
  MobileView,
  SectionFormat,
  WorkoutType,
} from "@/types/workout";
import { AUTO_SCORE_MAP, makeDefaultExercise, makeDefaultFormatParams, makeDefaultSection } from "@/types/workout";

type SaveStatus = "idle" | "saving" | "saved" | "error";

type WorkoutCreationStore = DraftWorkoutState & {
  saveStatus: SaveStatus;
  selectedSectionId: string | null;
  leftCollapsed: boolean;
  rightCollapsed: boolean;
  mobileView: MobileView;
  initDraft: (id: string) => void;
  loadFromDraftData: (data: unknown) => void;
  setTitle: (title: string) => void;
  setType: (type: WorkoutType) => void;
  setSaveStatus: (status: SaveStatus) => void;
  addSection: () => void;
  selectSection: (id: string | null) => void;
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
  leftCollapsed: false,
  rightCollapsed: false,
  mobileView: "sections",

  initDraft: (id) => set({ draftId: id }),

  loadFromDraftData: (data) => {
    if (!data || typeof data !== "object") return;

    const draft = data as Record<string, unknown>;

    set({
      title: typeof draft.title === "string" ? draft.title : "",
      type: parseWorkoutType(draft.type),
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
      };
    }),

  selectSection: (id) => set({ selectedSectionId: id }),

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
              exercises: [...section.exercises, { ...exercise, advancedOpen: false, variationsOpen: false }],
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

    return {
      title,
      type,
      sections: sections.map((section) => ({
        name: section.name,
        timer_config: { type: section.format, ...section.formatParams },
        scoreable: section.scoreable,
        score_config: section.scoreType ? { type: section.scoreType } : null,
        exercises: section.exercises.map((exercise) => ({
          name: exercise.name,
          sets: exercise.sets,
          prescription_value: exercise.prescriptionValue,
          prescription_unit: exercise.prescriptionUnit,
          load_value: exercise.loadValue,
          load_mode: exercise.loadMode,
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
  if (section.exercises.length === 0) return false;

  return section.exercises.every((exercise) => exercise.name && exercise.sets > 0 && exercise.prescriptionValue > 0);
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
