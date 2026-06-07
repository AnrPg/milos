# Workout Creation Canvas — Frontend Tasks (8–16)

Part of: [Main plan](./2026-06-07-workout-creation-ux.md)

Prerequisite: [Backend tasks 1–7](./2026-06-07-workout-creation-ux-backend.md) complete.

---

## Task 8: Install Frontend Dependencies

**Files:**
- Modify: `apps/web/package.json`

- [ ] **Step 1: Install packages**

```bash
cd apps/web && npm install zustand @dnd-kit/core @dnd-kit/sortable @dnd-kit/utilities
```

- [ ] **Step 2: Verify installation**

```bash
cd apps/web && npm run build 2>&1 | head -20
```

Expected: build succeeds (no new errors).

- [ ] **Step 3: Commit**

```bash
git add apps/web/package.json apps/web/package-lock.json
git commit -m "deps(web): add zustand and dnd-kit"
```

---

## Task 9: TypeScript Types + API Client Additions

**Files:**
- Create: `apps/web/src/types/workout.ts`
- Modify: `apps/web/src/api/workouts.ts`

- [ ] **Step 1: Write `src/types/workout.ts`**

```typescript
export type PrescriptionUnit = "reps" | "secs" | "kcal";
export type LoadMode = "absolute" | "pct_1rm";
export type WorkoutType =
  | "crossfit" | "strength" | "gymnastics"
  | "aerobics" | "flexibility" | "recovery";

export type SectionFormat =
  | "untimed" | "for_time" | "train_to_exhaustion" | "kcal_target"
  | "emom" | "complex_emom" | "even_odd" | "billat"
  | "amrap" | "edt" | "death_by"
  | "tabata" | "custom_hiit" | "cluster" | "hrr"
  | "ladder_ascending" | "ladder_descending" | "pyramid"
  | "rest";

export type ScoreType =
  | "time" | "reps" | "weight" | "rounds" | "rounds+reps"
  | "kcal" | "hr_drop" | "load";

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

// Formats where score type is unambiguous — auto-applied, not shown to user
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

export const FORMAT_TOOLTIPS: Record<SectionFormat, {
  bestFor: string;
  trains: string;
  how: string;
  score?: string;
}> = {
  untimed: {
    bestFor: "Strength, skill work, warm-ups",
    trains: "Technique, strength",
    how: "No time constraint — quality over speed",
  },
  for_time: {
    bestFor: "High-intensity WODs",
    trains: "Speed, conditioning",
    how: "Complete all reps/rounds as fast as possible",
    score: "Time",
  },
  train_to_exhaustion: {
    bestFor: "Hypertrophy, muscular endurance",
    trains: "Muscular endurance",
    how: "Push each set to technical failure",
    score: "Total reps",
  },
  kcal_target: {
    bestFor: "Cardio machines",
    trains: "Aerobic capacity",
    how: "Reach calorie target as fast as possible",
    score: "Kcal",
  },
  emom: {
    bestFor: "Pacing and power output",
    trains: "Power, pacing",
    how: "Complete prescribed reps every minute on the minute",
  },
  complex_emom: {
    bestFor: "Mixed modality pacing",
    trains: "Varied skills, pacing",
    how: "Alternating exercises each minute",
  },
  even_odd: {
    bestFor: "Paired movement training",
    trains: "Alternating skills",
    how: "Even minutes = exercise A, odd minutes = exercise B",
  },
  billat: {
    bestFor: "VO2max development",
    trains: "Aerobic power",
    how: "Repeated max-effort intervals with equal rest",
  },
  amrap: {
    bestFor: "Benchmark WODs, capacity testing",
    trains: "Conditioning, mental toughness",
    how: "As many rounds/reps as possible in the time window",
    score: "Rounds + reps",
  },
  edt: {
    bestFor: "Volume accumulation",
    trains: "Muscular endurance",
    how: "Accumulate as many reps as possible in the time window",
    score: "Reps",
  },
  death_by: {
    bestFor: "Progressive overload, competition",
    trains: "Endurance, max capacity",
    how: "Add 1 rep each round until you can't complete the round",
    score: "Total reps",
  },
  tabata: {
    bestFor: "HIIT conditioning",
    trains: "Anaerobic capacity",
    how: "20s work / 10s rest for prescribed rounds",
  },
  custom_hiit: {
    bestFor: "Custom interval protocols",
    trains: "Anaerobic/aerobic mix",
    how: "Custom work/rest ratio for prescribed rounds",
  },
  cluster: {
    bestFor: "Heavy strength, cluster sets",
    trains: "Maximal strength",
    how: "Short intra-set rest between each rep cluster",
  },
  hrr: {
    bestFor: "Heart rate-guided recovery",
    trains: "Cardiovascular recovery",
    how: "Effort intervals — rest until HR drops to target zone",
    score: "HR drop rate",
  },
  ladder_ascending: {
    bestFor: "Progressive loading",
    trains: "Strength endurance",
    how: "Start at base reps, add step reps each round",
  },
  ladder_descending: {
    bestFor: "Countdown workouts",
    trains: "Speed, conditioning",
    how: "Start at peak reps, subtract step each round",
    score: "Time",
  },
  pyramid: {
    bestFor: "Volume / intensity balance",
    trains: "Strength, endurance",
    how: "Reps go up to peak then come back down",
    score: "Time",
  },
  rest: {
    bestFor: "Programmed recovery",
    trains: "Recovery",
    how: "Passive rest for the given duration",
  },
};

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

export function makeDefaultExercise(order: number): DraftExercise {
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
```

- [ ] **Step 2: Add new API functions to `src/api/workouts.ts`**

Append to the existing file:

```typescript
export async function createDraftWorkout(token: string): Promise<{ id: string }> {
  const response = await apiRequest<{ workout: { id: string } }>("/admin/workouts", {
    method: "POST",
    token,
  });
  return response.workout;
}

export async function updateDraftWorkout(
  token: string,
  id: string,
  payload: unknown
): Promise<{ id: string }> {
  const response = await apiRequest<{ workout: { id: string } }>(
    `/admin/workouts/${id}/draft`,
    { method: "PATCH", token, body: payload }
  );
  return response.workout;
}

export async function publishWorkout(token: string, id: string): Promise<WorkoutRecord> {
  const response = await apiRequest<{ workout: WorkoutRecord }>(
    `/admin/workouts/${id}/publish`,
    { method: "POST", token }
  );
  return response.workout;
}

export async function fetchAdminWorkout(token: string, id: string): Promise<{
  id: string;
  status: string;
  title?: string;
  type?: string;
  draft_data?: unknown;
}> {
  const response = await apiRequest<{ workout: { id: string; status: string; title?: string; type?: string; draft_data?: unknown } }>(
    `/admin/workouts/${id}`,
    { token }
  );
  return response.workout;
}
```

- [ ] **Step 3: Verify TypeScript compiles**

```bash
cd apps/web && npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/types/workout.ts apps/web/src/api/workouts.ts
git commit -m "feat(web/types): add workout creation types and API client functions"
```

---

## Task 10: Zustand Store

**Files:**
- Create: `apps/web/src/stores/workout-creation.ts`

- [ ] **Step 1: Write the store**

```typescript
import { create } from "zustand";
import type {
  DraftExercise,
  DraftSection,
  DraftVariation,
  DraftWorkoutState,
  PrescriptionUnit,
  LoadMode,
  SectionFormat,
  FormatParams,
  ScoreType,
  WorkoutType,
} from "@/types/workout";
import {
  makeDefaultExercise,
  makeDefaultSection,
  AUTO_SCORE_MAP,
} from "@/types/workout";

type SaveStatus = "idle" | "saving" | "saved" | "error";

type WorkoutCreationStore = DraftWorkoutState & {
  saveStatus: SaveStatus;
  selectedSectionId: string | null;
  leftCollapsed: boolean;
  rightCollapsed: boolean;

  // Draft init
  initDraft: (id: string) => void;
  loadFromDraftData: (data: unknown) => void;

  // Header
  setTitle: (title: string) => void;
  setType: (type: WorkoutType) => void;
  setSaveStatus: (status: SaveStatus) => void;

  // Sections
  addSection: () => void;
  selectSection: (id: string | null) => void;
  updateSection: (id: string, patch: Partial<DraftSection>) => void;
  deleteSection: (id: string) => void;
  reorderSections: (fromId: string, toId: string) => void;

  // Format
  setFormat: (sectionId: string, format: SectionFormat) => void;
  setFormatParams: (sectionId: string, params: FormatParams) => void;

  // Exercises
  addExercise: (sectionId: string) => void;
  updateExercise: (sectionId: string, exerciseId: string, patch: Partial<DraftExercise>) => void;
  deleteExercise: (sectionId: string, exerciseId: string) => void;
  reorderExercises: (sectionId: string, fromId: string, toId: string) => void;
  moveExercise: (exerciseId: string, fromSectionId: string, toSectionId: string) => void;

  // Variations
  toggleVariationsPanel: (sectionId: string, exerciseId: string) => void;
  addVariation: (sectionId: string, exerciseId: string, scaleLevelSlug: string) => void;
  updateVariation: (
    sectionId: string,
    exerciseId: string,
    slug: string,
    patch: Partial<DraftVariation>
  ) => void;
  excludeVariation: (sectionId: string, exerciseId: string, slug: string) => void;
  restoreVariation: (sectionId: string, exerciseId: string, slug: string) => void;

  // Advanced
  toggleAdvancedPanel: (sectionId: string, exerciseId: string) => void;
  toggleAdvancedSetting: (
    sectionId: string,
    exerciseId: string,
    setting: keyof DraftExercise["advanced"]
  ) => void;
  updateAdvancedValue: (
    sectionId: string,
    exerciseId: string,
    setting: keyof DraftExercise["advanced"],
    value: number | string
  ) => void;

  // Panel state
  setLeftCollapsed: (v: boolean) => void;
  setRightCollapsed: (v: boolean) => void;

  // Serialization
  toApiPayload: () => unknown;
};

export const useWorkoutCreationStore = create<WorkoutCreationStore>((set, get) => ({
  draftId: null,
  title: "",
  type: null,
  sections: [],
  saveStatus: "idle",
  selectedSectionId: null,
  leftCollapsed: false,
  rightCollapsed: false,

  initDraft: (id) => set({ draftId: id }),

  loadFromDraftData: (data) => {
    if (!data || typeof data !== "object") return;
    const d = data as Record<string, unknown>;
    set({
      title: (d.title as string) ?? "",
      type: (d.type as WorkoutType) ?? null,
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
      sections: state.sections.map((s) => (s.localId === id ? { ...s, ...patch } : s)),
    })),

  deleteSection: (id) =>
    set((state) => ({
      sections: state.sections.filter((s) => s.localId !== id),
      selectedSectionId:
        state.selectedSectionId === id ? null : state.selectedSectionId,
    })),

  reorderSections: (fromId, toId) =>
    set((state) => {
      const sections = [...state.sections];
      const fromIndex = sections.findIndex((s) => s.localId === fromId);
      const toIndex = sections.findIndex((s) => s.localId === toId);
      if (fromIndex === -1 || toIndex === -1) return state;
      const [moved] = sections.splice(fromIndex, 1);
      sections.splice(toIndex, 0, moved);
      return { sections };
    }),

  setFormat: (sectionId, format) =>
    set((state) => ({
      sections: state.sections.map((s) => {
        if (s.localId !== sectionId) return s;
        const autoScore = AUTO_SCORE_MAP[format] ?? null;
        return {
          ...s,
          format,
          formatParams: {},
          scoreType: autoScore,
        };
      }),
    })),

  setFormatParams: (sectionId, params) =>
    set((state) => ({
      sections: state.sections.map((s) =>
        s.localId === sectionId ? { ...s, formatParams: params } : s
      ),
    })),

  addExercise: (sectionId) =>
    set((state) => ({
      sections: state.sections.map((s) => {
        if (s.localId !== sectionId) return s;
        return {
          ...s,
          exercises: [...s.exercises, makeDefaultExercise(s.exercises.length + 1)],
        };
      }),
    })),

  updateExercise: (sectionId, exerciseId, patch) =>
    set((state) => ({
      sections: state.sections.map((s) => {
        if (s.localId !== sectionId) return s;
        return {
          ...s,
          exercises: s.exercises.map((e) =>
            e.localId === exerciseId ? { ...e, ...patch } : e
          ),
        };
      }),
    })),

  deleteExercise: (sectionId, exerciseId) =>
    set((state) => ({
      sections: state.sections.map((s) => {
        if (s.localId !== sectionId) return s;
        return {
          ...s,
          exercises: s.exercises.filter((e) => e.localId !== exerciseId),
        };
      }),
    })),

  reorderExercises: (sectionId, fromId, toId) =>
    set((state) => ({
      sections: state.sections.map((s) => {
        if (s.localId !== sectionId) return s;
        const exercises = [...s.exercises];
        const fromIndex = exercises.findIndex((e) => e.localId === fromId);
        const toIndex = exercises.findIndex((e) => e.localId === toId);
        if (fromIndex === -1 || toIndex === -1) return s;
        const [moved] = exercises.splice(fromIndex, 1);
        exercises.splice(toIndex, 0, moved);
        return { ...s, exercises };
      }),
    })),

  moveExercise: (exerciseId, fromSectionId, toSectionId) =>
    set((state) => {
      const fromSection = state.sections.find((s) => s.localId === fromSectionId);
      const exercise = fromSection?.exercises.find((e) => e.localId === exerciseId);
      if (!exercise) return state;
      return {
        sections: state.sections.map((s) => {
          if (s.localId === fromSectionId) {
            return { ...s, exercises: s.exercises.filter((e) => e.localId !== exerciseId) };
          }
          if (s.localId === toSectionId) {
            return { ...s, exercises: [...s.exercises, exercise] };
          }
          return s;
        }),
      };
    }),

  toggleVariationsPanel: (sectionId, exerciseId) =>
    set((state) => ({
      sections: state.sections.map((s) => {
        if (s.localId !== sectionId) return s;
        return {
          ...s,
          exercises: s.exercises.map((e) =>
            e.localId === exerciseId
              ? { ...e, variationsOpen: !e.variationsOpen }
              : e
          ),
        };
      }),
    })),

  addVariation: (sectionId, exerciseId, scaleLevelSlug) =>
    set((state) => ({
      sections: state.sections.map((s) => {
        if (s.localId !== sectionId) return s;
        return {
          ...s,
          exercises: s.exercises.map((e) => {
            if (e.localId !== exerciseId) return e;
            if (e.variations.some((v) => v.scaleLevelSlug === scaleLevelSlug)) return e;
            return {
              ...e,
              variations: [
                ...e.variations,
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
      sections: state.sections.map((s) => {
        if (s.localId !== sectionId) return s;
        return {
          ...s,
          exercises: s.exercises.map((e) => {
            if (e.localId !== exerciseId) return e;
            return {
              ...e,
              variations: e.variations.map((v) =>
                v.scaleLevelSlug === slug ? { ...v, ...patch } : v
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
      sections: state.sections.map((s) => {
        if (s.localId !== sectionId) return s;
        return {
          ...s,
          exercises: s.exercises.map((e) =>
            e.localId === exerciseId ? { ...e, advancedOpen: !e.advancedOpen } : e
          ),
        };
      }),
    })),

  toggleAdvancedSetting: (sectionId, exerciseId, setting) =>
    set((state) => ({
      sections: state.sections.map((s) => {
        if (s.localId !== sectionId) return s;
        return {
          ...s,
          exercises: s.exercises.map((e) => {
            if (e.localId !== exerciseId) return e;
            return {
              ...e,
              advanced: {
                ...e.advanced,
                [setting]: {
                  ...e.advanced[setting],
                  enabled: !e.advanced[setting].enabled,
                },
              },
            };
          }),
        };
      }),
    })),

  updateAdvancedValue: (sectionId, exerciseId, setting, value) =>
    set((state) => ({
      sections: state.sections.map((s) => {
        if (s.localId !== sectionId) return s;
        return {
          ...s,
          exercises: s.exercises.map((e) => {
            if (e.localId !== exerciseId) return e;
            return {
              ...e,
              advanced: {
                ...e.advanced,
                [setting]: { ...e.advanced[setting], value },
              },
            };
          }),
        };
      }),
    })),

  setLeftCollapsed: (v) => set({ leftCollapsed: v }),
  setRightCollapsed: (v) => set({ rightCollapsed: v }),

  toApiPayload: () => {
    const { title, type, sections } = get();
    return {
      title,
      type,
      sections: sections.map((s) => ({
        name: s.name,
        timer_config: { type: s.format, ...s.formatParams },
        scoreable: s.scoreable,
        score_config: s.scoreType ? { type: s.scoreType } : null,
        exercises: s.exercises.map((e) => ({
          name: e.name,
          sets: e.sets,
          prescription_value: e.prescriptionValue,
          prescription_unit: e.prescriptionUnit,
          load_value: e.loadValue,
          load_mode: e.loadMode,
          superset_group_id: e.supersetGroupId,
          interval_assignment: e.intervalAssignment,
          hr_zone: e.advanced.hrZone.enabled ? e.advanced.hrZone.value : null,
          tempo: e.advanced.tempo.enabled ? e.advanced.tempo.value : null,
          rest_seconds: e.advanced.restSeconds.enabled ? e.advanced.restSeconds.value : null,
          cluster_rest_seconds: e.advanced.clusterRestSeconds.enabled
            ? e.advanced.clusterRestSeconds.value
            : null,
          rest_pause_seconds: e.advanced.restPauseSeconds.enabled
            ? e.advanced.restPauseSeconds.value
            : null,
          pacing: e.advanced.pacing.enabled ? e.advanced.pacing.value : null,
          variations: e.variations.map((v) => ({
            scale_level_slug: v.scaleLevelSlug,
            exercise_name_override: v.exerciseNameOverride,
            sets: v.sets,
            prescription_value: v.prescriptionValue,
            prescription_unit: v.prescriptionUnit,
            load_value: v.loadValue,
            load_mode: v.loadMode,
            excluded: v.excluded,
          })),
        })),
      })),
    };
  },
}));

// Selector: completion status for a section
export function isSectionComplete(section: DraftSection): boolean {
  if (!section.name) return false;
  if (section.exercises.length === 0) return false;
  return section.exercises.every(
    (e) => e.name && e.sets > 0 && e.prescriptionValue > 0
  );
}

// Selector: publish validity
export function isPublishReady(state: DraftWorkoutState): boolean {
  if (!state.title || !state.type) return false;
  if (state.sections.length === 0) return false;
  return state.sections.every(isSectionComplete);
}

// Selector: completion summary text
export function completionSummary(sections: DraftSection[]): string {
  const complete = sections.filter(isSectionComplete).length;
  return `${complete} of ${sections.length} sections complete`;
}
```

- [ ] **Step 2: Verify TypeScript compiles**

```bash
cd apps/web && npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add apps/web/src/stores/workout-creation.ts
git commit -m "feat(web/store): add workout creation Zustand store"
```

---

## Task 11: WorkoutCreationCanvas — 3-Panel Layout

**Files:**
- Create: `apps/web/src/components/workouts/creation/WorkoutCreationCanvas.tsx`

- [ ] **Step 1: Write the canvas layout component**

```tsx
"use client";

import { useEffect, useRef } from "react";
import { useSession } from "@/components/session-provider";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { createDraftWorkout, updateDraftWorkout } from "@/api/workouts";
import { CanvasHeader } from "./CanvasHeader";
import { LeftPanel } from "./LeftPanel";
import { MiddlePanel } from "./MiddlePanel";
import { RightPanel } from "./RightPanel";

const AUTOSAVE_DELAY_MS = 1500;

export function WorkoutCreationCanvas() {
  const { tokens } = useSession();
  const store = useWorkoutCreationStore();
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const storeRef = useRef(store);
  storeRef.current = store;

  // Create empty draft on mount
  useEffect(() => {
    if (!tokens?.access_token) return;
    createDraftWorkout(tokens.access_token)
      .then((draft) => store.initDraft(draft.id))
      .catch(() => store.setSaveStatus("error"));
  }, [tokens?.access_token]);

  // Debounced autosave on any store state change
  useEffect(() => {
    if (!store.draftId || !tokens?.access_token) return;

    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    store.setSaveStatus("saving");

    saveTimerRef.current = setTimeout(async () => {
      try {
        await updateDraftWorkout(
          tokens.access_token,
          storeRef.current.draftId!,
          storeRef.current.toApiPayload()
        );
        storeRef.current.setSaveStatus("saved");
      } catch {
        storeRef.current.setSaveStatus("error");
      }
    }, AUTOSAVE_DELAY_MS);

    return () => {
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    };
  }, [store.title, store.type, store.sections, store.draftId, tokens?.access_token]);

  return (
    <div
      className="flex flex-col h-screen overflow-hidden"
      style={{ background: "var(--bg, #0A0A0F)", color: "var(--text, #F0EDF8)" }}
    >
      <CanvasHeader />
      <div className="flex flex-1 overflow-hidden">
        <LeftPanel />
        <MiddlePanel />
        <RightPanel />
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Add CSS variables to `apps/web/src/app/globals.css`**

Append:

```css
:root {
  --bg: #0A0A0F;
  --panel: #221F29;
  --card: #1c1926;
  --accent: #9c799c;
  --lime: #C6FF2E;
  --red: #FF4D6D;
  --amber: #FFB547;
  --text: #F0EDF8;
  --muted: #8B82A7;
  --dim: #4A4460;
}
```

- [ ] **Step 3: Commit**

```bash
git add apps/web/src/components/workouts/creation/WorkoutCreationCanvas.tsx \
        apps/web/src/app/globals.css
git commit -m "feat(web/canvas): add WorkoutCreationCanvas layout with autosave"
```

---

## Task 12: CanvasHeader

**Files:**
- Create: `apps/web/src/components/workouts/creation/CanvasHeader.tsx`

- [ ] **Step 1: Write the header component**

```tsx
"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { useSession } from "@/components/session-provider";
import {
  useWorkoutCreationStore,
  isPublishReady,
  completionSummary,
} from "@/stores/workout-creation";
import { publishWorkout } from "@/api/workouts";
import type { WorkoutType } from "@/types/workout";

const WORKOUT_TYPES: WorkoutType[] = [
  "crossfit", "strength", "gymnastics", "aerobics", "flexibility", "recovery",
];

const TYPE_LABELS: Record<WorkoutType, string> = {
  crossfit: "CrossFit",
  strength: "Strength",
  gymnastics: "Gymnastics",
  aerobics: "Aerobics",
  flexibility: "Flexibility",
  recovery: "Recovery",
};

function SaveStatusIndicator() {
  const status = useWorkoutCreationStore((s) => s.saveStatus);
  if (status === "idle") return null;
  const map = {
    saving: { icon: "↻", text: "Saving…", color: "var(--muted)" },
    saved: { icon: "✓", text: "Draft saved", color: "var(--lime)" },
    error: { icon: "⚠", text: "Draft not saved — retrying", color: "var(--amber)" },
  } as const;
  const { icon, text, color } = map[status];
  return (
    <span className="text-sm font-medium" style={{ color }}>
      {icon} {text}
    </span>
  );
}

export function CanvasHeader() {
  const router = useRouter();
  const { tokens } = useSession();
  const { draftId, title, type, sections, setTitle, setType, setSaveStatus } =
    useWorkoutCreationStore();
  const [publishing, setPublishing] = useState(false);
  const [publishError, setPublishError] = useState<string | null>(null);

  const ready = isPublishReady({ draftId, title, type, sections });
  const summary = completionSummary(sections);

  async function handlePublish() {
    if (!draftId || !tokens?.access_token || !ready) return;
    setPublishing(true);
    setPublishError(null);
    try {
      await publishWorkout(tokens.access_token, draftId);
      router.push("/admin/workouts");
    } catch (err: unknown) {
      setPublishError(
        err instanceof Error ? err.message : "Publish failed"
      );
      setPublishing(false);
    }
  }

  return (
    <header
      className="flex items-center gap-4 px-6 py-3 border-b shrink-0"
      style={{
        background: "var(--panel)",
        borderColor: "var(--dim)",
      }}
    >
      {/* Logo mark */}
      <span className="text-xl font-black" style={{ color: "var(--accent)" }}>✦</span>

      {/* Title input */}
      <input
        type="text"
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="Workout title"
        className="bg-transparent text-lg font-extrabold outline-none border-b border-transparent focus:border-current transition-colors min-w-0 flex-1"
        style={{ color: "var(--text)", maxWidth: 320 }}
      />

      {/* Type selector */}
      <select
        value={type ?? ""}
        onChange={(e) => setType(e.target.value as WorkoutType)}
        className="text-sm font-semibold rounded-2xl px-4 py-2 outline-none cursor-pointer"
        style={{
          background: "var(--card)",
          color: type ? "var(--text)" : "var(--muted)",
          border: "1px solid var(--dim)",
        }}
      >
        <option value="" disabled>Type ▾</option>
        {WORKOUT_TYPES.map((t) => (
          <option key={t} value={t}>{TYPE_LABELS[t]}</option>
        ))}
      </select>

      <div className="flex-1" />

      {/* Completion summary */}
      {sections.length > 0 && (
        <span className="text-sm" style={{ color: "var(--muted)" }}>
          {summary}
        </span>
      )}

      {/* Save status */}
      <SaveStatusIndicator />

      {/* Publish button */}
      <div className="relative group">
        <button
          onClick={handlePublish}
          disabled={!ready || publishing}
          className="px-6 py-2 rounded-3xl font-bold text-sm transition-opacity"
          style={{
            background: ready ? "var(--lime)" : "var(--dim)",
            color: ready ? "#0A0A0F" : "var(--muted)",
            cursor: ready ? "pointer" : "not-allowed",
          }}
        >
          {publishing ? "Publishing…" : "Publish ↗"}
        </button>

        {/* Tooltip when disabled */}
        {!ready && (
          <div
            className="absolute right-0 top-full mt-2 p-3 rounded-xl text-xs z-50 whitespace-nowrap pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity"
            style={{ background: "var(--card)", border: "1px solid var(--dim)", color: "var(--muted)" }}
          >
            {!title && <div>• Missing: workout title</div>}
            {!type && <div>• Missing: workout type</div>}
            {sections.length === 0 && <div>• Add at least one section</div>}
            {sections.some((s) => !s.name) && <div>• Some sections have no name</div>}
            {sections.some((s) => s.exercises.length === 0) && (
              <div>• Some sections have no exercises</div>
            )}
          </div>
        )}
      </div>

      {/* Inline publish error */}
      {publishError && (
        <span className="text-xs" style={{ color: "var(--red)" }}>{publishError}</span>
      )}
    </header>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/web/src/components/workouts/creation/CanvasHeader.tsx
git commit -m "feat(web/canvas): add CanvasHeader with title, type, completion, save status, publish"
```

---

## Task 13: Left Panel — Section List

**Files:**
- Create: `apps/web/src/components/workouts/creation/LeftPanel.tsx`
- Create: `apps/web/src/components/workouts/creation/SectionChip.tsx`

- [ ] **Step 1: Write `SectionChip.tsx`**

```tsx
"use client";

import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import type { DraftSection } from "@/types/workout";
import { isSectionComplete } from "@/stores/workout-creation";

type SectionChipProps = {
  section: DraftSection;
  isSelected: boolean;
  onSelect: () => void;
};

export function SectionChip({ section, isSelected, onSelect }: SectionChipProps) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: section.localId });

  const complete = isSectionComplete(section);
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : 1,
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      onClick={onSelect}
      className="flex items-center gap-2 rounded-2xl px-3 py-2 cursor-pointer select-none transition-colors"
      style={{
        ...style,
        background: isSelected ? "var(--accent)" : "var(--card)",
        border: `1px solid ${isSelected ? "var(--accent)" : "var(--dim)"}`,
        color: isSelected ? "#0A0A0F" : "var(--text)",
      }}
    >
      {/* Drag handle */}
      <span
        {...attributes}
        {...listeners}
        className="cursor-grab text-sm"
        style={{ color: isSelected ? "#0A0A0F" : "var(--dim)" }}
        onClick={(e) => e.stopPropagation()}
      >
        ⠿
      </span>

      <span className="flex-1 text-sm font-semibold truncate min-w-0">
        {section.name || "Unnamed section"}
      </span>

      {/* Completion badge */}
      <span
        className="text-xs font-bold shrink-0"
        style={{ color: complete ? "var(--lime)" : "var(--amber)" }}
      >
        {complete ? "✓" : "!"}
      </span>
    </div>
  );
}
```

- [ ] **Step 2: Write `LeftPanel.tsx`**

```tsx
"use client";

import {
  DndContext,
  closestCenter,
  PointerSensor,
  TouchSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import { SortableContext, verticalListSortingStrategy } from "@dnd-kit/sortable";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { SectionChip } from "./SectionChip";
import { SectionConfig } from "./SectionConfig";

export function LeftPanel() {
  const {
    sections,
    selectedSectionId,
    leftCollapsed,
    addSection,
    selectSection,
    reorderSections,
    setLeftCollapsed,
  } = useWorkoutCreationStore();

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 300, tolerance: 5 } })
  );

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (over && active.id !== over.id) {
      reorderSections(active.id as string, over.id as string);
    }
  }

  const selectedSection = sections.find((s) => s.localId === selectedSectionId) ?? null;

  if (leftCollapsed) {
    return (
      <div
        className="flex flex-col items-center justify-center w-10 shrink-0 cursor-pointer"
        style={{ background: "var(--panel)", borderRight: "1px solid var(--dim)" }}
        onClick={() => setLeftCollapsed(false)}
      >
        <span
          className="text-xs font-bold tracking-widest uppercase"
          style={{
            writingMode: "vertical-rl",
            transform: "rotate(180deg)",
            color: "var(--muted)",
          }}
        >
          Sections
        </span>
        <span className="mt-2 text-xs" style={{ color: "var(--muted)" }}>›</span>
      </div>
    );
  }

  return (
    <div
      className="flex flex-col w-64 shrink-0 overflow-hidden"
      style={{ background: "var(--panel)", borderRight: "1px solid var(--dim)" }}
    >
      {/* Panel header */}
      <div className="flex items-center justify-between px-4 py-3 shrink-0">
        <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          Sections
        </span>
        <button
          onClick={() => setLeftCollapsed(true)}
          className="text-xs"
          style={{ color: "var(--dim)" }}
        >
          ‹
        </button>
      </div>

      {/* Section chips — scrollable */}
      <div className="flex-1 overflow-y-auto px-3 pb-3 flex flex-col gap-2">
        <DndContext
          sensors={sensors}
          collisionDetection={closestCenter}
          onDragEnd={handleDragEnd}
        >
          <SortableContext
            items={sections.map((s) => s.localId)}
            strategy={verticalListSortingStrategy}
          >
            {sections.map((section) => (
              <SectionChip
                key={section.localId}
                section={section}
                isSelected={section.localId === selectedSectionId}
                onSelect={() =>
                  selectSection(
                    section.localId === selectedSectionId ? null : section.localId
                  )
                }
              />
            ))}
          </SortableContext>
        </DndContext>

        <button
          onClick={addSection}
          className="rounded-2xl px-3 py-2 text-sm font-semibold transition-colors text-center"
          style={{
            border: "1px dashed var(--dim)",
            color: "var(--muted)",
          }}
        >
          + Add section
        </button>
      </div>

      {/* Section config — shown when section is selected */}
      {selectedSection && (
        <div
          className="shrink-0 border-t overflow-y-auto"
          style={{ borderColor: "var(--dim)", maxHeight: "60%" }}
        >
          <SectionConfig section={selectedSection} />
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add apps/web/src/components/workouts/creation/LeftPanel.tsx \
        apps/web/src/components/workouts/creation/SectionChip.tsx
git commit -m "feat(web/canvas): add LeftPanel with sortable section chips"
```

---

## Task 14: Format Dropdown Component

**Files:**
- Create: `apps/web/src/components/workouts/creation/FormatDropdown.tsx`

- [ ] **Step 1: Write `FormatDropdown.tsx`**

```tsx
"use client";

import { useRef, useState, useCallback } from "react";
import {
  FORMAT_GROUPS,
  FORMAT_LABELS,
  FORMAT_TOOLTIPS,
  AUTO_SCORE_MAP,
  type SectionFormat,
} from "@/types/workout";

type FormatDropdownProps = {
  value: SectionFormat;
  onChange: (format: SectionFormat) => void;
};

export function FormatDropdown({ value, onChange }: FormatDropdownProps) {
  const [open, setOpen] = useState(false);
  const [hoveredFormat, setHoveredFormat] = useState<SectionFormat | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  const close = useCallback(() => {
    setOpen(false);
    setHoveredFormat(null);
  }, []);

  function handleSelect(format: SectionFormat) {
    onChange(format);
    close();
  }

  const tooltip = hoveredFormat ? FORMAT_TOOLTIPS[hoveredFormat] : null;
  const autoScore = hoveredFormat ? AUTO_SCORE_MAP[hoveredFormat] : null;

  return (
    <div ref={containerRef} className="relative w-full">
      {/* Trigger */}
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="w-full flex items-center justify-between rounded-xl px-3 py-2 text-sm font-semibold transition-colors"
        style={{
          background: "var(--card)",
          border: `1px solid ${open ? "var(--accent)" : "var(--dim)"}`,
          color: "var(--text)",
        }}
      >
        <span>{FORMAT_LABELS[value]}</span>
        <span style={{ color: "var(--muted)" }}>{open ? "▴" : "▾"}</span>
      </button>

      {/* Dropdown */}
      {open && (
        <>
          {/* Backdrop */}
          <div className="fixed inset-0 z-40" onClick={close} />

          <div
            className="absolute left-0 top-full mt-1 z-50 rounded-xl py-2 overflow-y-auto"
            style={{
              background: "var(--card)",
              border: "1px solid var(--dim)",
              minWidth: 220,
              maxHeight: 360,
              boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
            }}
          >
            {/* Tooltip panel — shown to right when hovering */}
            {tooltip && (
              <div
                className="fixed z-50 p-4 rounded-xl text-xs pointer-events-none"
                style={{
                  left: (containerRef.current?.getBoundingClientRect().right ?? 0) + 8,
                  top: containerRef.current?.getBoundingClientRect().top ?? 0,
                  background: "var(--panel)",
                  border: "1px solid var(--dim)",
                  width: 240,
                  color: "var(--text)",
                }}
              >
                <div className="font-bold mb-2">{FORMAT_LABELS[hoveredFormat!]}</div>
                <div className="mb-1">
                  <span style={{ color: "var(--muted)" }}>📌 Best for </span>
                  {tooltip.bestFor}
                </div>
                <div className="mb-1">
                  <span style={{ color: "var(--muted)" }}>💪 Trains </span>
                  {tooltip.trains}
                </div>
                <div className="mb-1">
                  <span style={{ color: "var(--muted)" }}>⚙️ How </span>
                  {tooltip.how}
                </div>
                {tooltip.score && (
                  <div>
                    <span style={{ color: "var(--muted)" }}>🏆 Score </span>
                    {tooltip.score}
                  </div>
                )}
              </div>
            )}

            {FORMAT_GROUPS.map((group) => (
              <div key={group.label}>
                <div
                  className="px-3 py-1 text-xs font-bold uppercase tracking-widest"
                  style={{ color: "var(--dim)" }}
                >
                  {group.label}
                </div>
                {group.formats.map((format) => (
                  <button
                    key={format}
                    type="button"
                    onClick={() => handleSelect(format)}
                    onMouseEnter={() => setHoveredFormat(format)}
                    onMouseLeave={() => setHoveredFormat(null)}
                    className="w-full flex items-center justify-between px-3 py-2 text-sm transition-colors text-left"
                    style={{
                      background:
                        format === value
                          ? "var(--accent)22"
                          : hoveredFormat === format
                          ? "var(--card)88"
                          : "transparent",
                      color: format === value ? "var(--accent)" : "var(--text)",
                    }}
                  >
                    <span>{FORMAT_LABELS[format]}</span>
                    {AUTO_SCORE_MAP[format] && (
                      <span className="text-xs ml-2" style={{ color: "var(--muted)" }}>
                        {AUTO_SCORE_MAP[format]}
                      </span>
                    )}
                  </button>
                ))}
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/web/src/components/workouts/creation/FormatDropdown.tsx
git commit -m "feat(web/canvas): add FormatDropdown with grouped options and hover tooltips"
```

---

## Task 15: Section Config + Contextual Format Fields

**Files:**
- Create: `apps/web/src/components/workouts/creation/SectionConfig.tsx`
- Create: `apps/web/src/components/workouts/creation/FormatContextualFields.tsx`

- [ ] **Step 1: Write `FormatContextualFields.tsx`**

```tsx
"use client";

import type { SectionFormat, FormatParams } from "@/types/workout";

type FieldDef = {
  key: string;
  label: string;
  unit: string;
  defaultValue: number;
  optional?: boolean;
};

const FORMAT_FIELDS: Partial<Record<SectionFormat, FieldDef[]>> = {
  for_time: [
    { key: "time_cap_seconds", label: "Time Cap", unit: "secs", defaultValue: 900, optional: true },
  ],
  train_to_exhaustion: [
    { key: "rest_seconds", label: "Rest between sets", unit: "secs", defaultValue: 90, optional: true },
  ],
  kcal_target: [
    { key: "kcal_target", label: "Target", unit: "kcal", defaultValue: 100 },
    { key: "time_cap_seconds", label: "Time Cap", unit: "secs", defaultValue: 900, optional: true },
  ],
  emom: [
    { key: "duration_seconds", label: "Total Duration", unit: "secs", defaultValue: 600 },
    { key: "interval_seconds", label: "Interval", unit: "secs", defaultValue: 60 },
  ],
  complex_emom: [
    { key: "duration_seconds", label: "Total Duration", unit: "secs", defaultValue: 600 },
    { key: "interval_seconds", label: "Interval", unit: "secs", defaultValue: 60 },
  ],
  even_odd: [
    { key: "duration_seconds", label: "Total Duration", unit: "secs", defaultValue: 600 },
  ],
  billat: [
    { key: "work_seconds", label: "Work", unit: "secs", defaultValue: 30 },
    { key: "rest_seconds", label: "Rest", unit: "secs", defaultValue: 30 },
    { key: "cycles", label: "Cycles", unit: "", defaultValue: 8 },
  ],
  amrap: [
    { key: "duration_seconds", label: "Duration", unit: "secs", defaultValue: 720 },
  ],
  edt: [
    { key: "duration_seconds", label: "Duration", unit: "secs", defaultValue: 900 },
    { key: "pr_zone_rounds", label: "PR Zone Rounds", unit: "", defaultValue: 5, optional: true },
  ],
  death_by: [
    { key: "start_reps", label: "Starting Reps", unit: "", defaultValue: 1 },
    { key: "step_reps", label: "Added per Round", unit: "", defaultValue: 1 },
    { key: "ladder_cap", label: "Cap", unit: "", defaultValue: 20, optional: true },
  ],
  tabata: [
    { key: "work_seconds", label: "Work", unit: "secs", defaultValue: 20 },
    { key: "rest_seconds", label: "Rest", unit: "secs", defaultValue: 10 },
    { key: "rounds", label: "Rounds", unit: "", defaultValue: 8 },
  ],
  custom_hiit: [
    { key: "work_seconds", label: "Work", unit: "secs", defaultValue: 40 },
    { key: "rest_seconds", label: "Rest", unit: "secs", defaultValue: 20 },
    { key: "rounds", label: "Rounds", unit: "", defaultValue: 10 },
  ],
  cluster: [
    { key: "intra_rest_seconds", label: "Intra-set Rest", unit: "secs", defaultValue: 15 },
    { key: "sets", label: "Sets", unit: "", defaultValue: 5 },
  ],
  hrr: [
    { key: "effort_seconds", label: "Effort Duration", unit: "secs", defaultValue: 30 },
    { key: "hr_zone", label: "Target HR Zone", unit: "Zone", defaultValue: 3, optional: true },
  ],
  ladder_ascending: [
    { key: "start_reps", label: "Start Reps", unit: "", defaultValue: 1 },
    { key: "step_reps", label: "Step", unit: "", defaultValue: 1 },
    { key: "ladder_cap", label: "Cap", unit: "", defaultValue: 10, optional: true },
  ],
  ladder_descending: [
    { key: "start_reps", label: "Start Reps", unit: "", defaultValue: 10 },
    { key: "step_reps", label: "Step", unit: "", defaultValue: 1 },
    { key: "min_reps", label: "Min Reps", unit: "", defaultValue: 1 },
  ],
  pyramid: [
    { key: "peak_reps", label: "Peak Reps", unit: "", defaultValue: 10 },
    { key: "step_reps", label: "Step", unit: "", defaultValue: 2 },
  ],
  rest: [
    { key: "duration_seconds", label: "Duration", unit: "secs", defaultValue: 60 },
  ],
};

type Props = {
  format: SectionFormat;
  params: FormatParams;
  onChange: (params: FormatParams) => void;
};

export function FormatContextualFields({ format, params, onChange }: Props) {
  const fields = FORMAT_FIELDS[format];
  if (!fields || fields.length === 0) return null;

  function handleChange(key: string, raw: string) {
    const value = parseInt(raw, 10);
    onChange({ ...params, [key]: isNaN(value) ? null : value });
  }

  return (
    <div className="flex flex-col gap-3 mt-2">
      {fields.map((field) => {
        const value = params[field.key] ?? field.defaultValue;
        return (
          <div key={field.key} className="flex items-center justify-between gap-2">
            <label className="text-xs font-bold uppercase tracking-widest shrink-0" style={{ color: "var(--muted)" }}>
              {field.label}
              {field.optional && (
                <span className="ml-1 normal-case font-normal italic" style={{ color: "var(--dim)" }}>
                  — optional
                </span>
              )}
            </label>
            <div className="flex items-center gap-2">
              <input
                type="number"
                value={value ?? ""}
                onChange={(e) => handleChange(field.key, e.target.value)}
                className="w-20 text-right rounded-lg px-2 py-1 text-sm outline-none"
                style={{
                  background: "var(--bg)",
                  border: "1px solid var(--dim)",
                  color: "var(--text)",
                }}
              />
              {field.unit && (
                <span className="text-sm shrink-0" style={{ color: "var(--muted)" }}>
                  {field.unit}
                </span>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}
```

- [ ] **Step 2: Write `SectionConfig.tsx`**

```tsx
"use client";

import type { DraftSection, ScoreType } from "@/types/workout";
import { AUTO_SCORE_MAP } from "@/types/workout";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { FormatDropdown } from "./FormatDropdown";
import { FormatContextualFields } from "./FormatContextualFields";

const SCORE_TYPES: ScoreType[] = [
  "time", "reps", "weight", "rounds", "rounds+reps", "kcal", "hr_drop", "load",
];

type Props = { section: DraftSection };

export function SectionConfig({ section }: Props) {
  const { updateSection, setFormat, setFormatParams, deleteSection } =
    useWorkoutCreationStore();

  const autoScore = AUTO_SCORE_MAP[section.format];
  const showScorePicker = section.scoreable && !autoScore;

  return (
    <div className="p-4 flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          Section Config
        </span>
        <button
          onClick={() => deleteSection(section.localId)}
          className="text-xs"
          style={{ color: "var(--red)" }}
        >
          Delete
        </button>
      </div>

      {/* Name */}
      <div>
        <label className="block text-xs font-bold uppercase tracking-widest mb-1" style={{ color: "var(--muted)" }}>
          Name
        </label>
        <input
          type="text"
          value={section.name}
          onChange={(e) => updateSection(section.localId, { name: e.target.value })}
          placeholder="e.g. Main Set"
          className="w-full rounded-xl px-3 py-2 text-sm outline-none"
          style={{ background: "var(--bg)", border: "1px solid var(--dim)", color: "var(--text)" }}
        />
      </div>

      {/* Format */}
      <div>
        <label className="block text-xs font-bold uppercase tracking-widest mb-1" style={{ color: "var(--muted)" }}>
          Format
        </label>
        <FormatDropdown
          value={section.format}
          onChange={(format) => setFormat(section.localId, format)}
        />
        <FormatContextualFields
          format={section.format}
          params={section.formatParams}
          onChange={(params) => setFormatParams(section.localId, params)}
        />
      </div>

      {/* Scoreable */}
      {section.format !== "rest" && (
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => updateSection(section.localId, { scoreable: !section.scoreable })}
            className="relative w-10 h-5 rounded-full transition-colors"
            style={{ background: section.scoreable ? "var(--accent)" : "var(--dim)" }}
          >
            <span
              className="absolute top-0.5 w-4 h-4 rounded-full bg-white transition-transform"
              style={{ transform: section.scoreable ? "translateX(22px)" : "translateX(2px)" }}
            />
          </button>
          <span className="text-sm" style={{ color: "var(--text)" }}>Scoreable</span>
        </div>
      )}

      {/* Score type — only when scoreable AND no auto inference */}
      {showScorePicker && (
        <div>
          <label className="block text-xs font-bold uppercase tracking-widest mb-1" style={{ color: "var(--muted)" }}>
            Score Type
          </label>
          <select
            value={section.scoreType ?? ""}
            onChange={(e) =>
              updateSection(section.localId, { scoreType: e.target.value as ScoreType })
            }
            className="w-full rounded-xl px-3 py-2 text-sm outline-none"
            style={{ background: "var(--bg)", border: "1px solid var(--dim)", color: "var(--text)" }}
          >
            <option value="">Select score type</option>
            {SCORE_TYPES.map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </select>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add apps/web/src/components/workouts/creation/SectionConfig.tsx \
        apps/web/src/components/workouts/creation/FormatContextualFields.tsx
git commit -m "feat(web/canvas): add SectionConfig with FormatDropdown and contextual fields"
```

---

## Task 16: Middle Panel

**Files:**
- Create: `apps/web/src/components/workouts/creation/MiddlePanel.tsx`

- [ ] **Step 1: Write `MiddlePanel.tsx`**

```tsx
"use client";

import {
  DndContext,
  closestCenter,
  DragOverlay,
  PointerSensor,
  TouchSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
  type DragStartEvent,
} from "@dnd-kit/core";
import { SortableContext, verticalListSortingStrategy } from "@dnd-kit/sortable";
import { useState } from "react";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { ExerciseCard } from "./ExerciseCard";

export function MiddlePanel() {
  const { sections, selectedSectionId, addExercise, reorderExercises } =
    useWorkoutCreationStore();
  const [activeId, setActiveId] = useState<string | null>(null);

  const selectedSection = sections.find((s) => s.localId === selectedSectionId);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 300, tolerance: 5 } })
  );

  function handleDragStart({ active }: DragStartEvent) {
    setActiveId(active.id as string);
  }

  function handleDragEnd({ active, over }: DragEndEvent) {
    setActiveId(null);
    if (!selectedSection || !over || active.id === over.id) return;
    reorderExercises(selectedSection.localId, active.id as string, over.id as string);
  }

  return (
    <div
      className="flex flex-col flex-1 overflow-hidden"
      style={{ background: "var(--bg)" }}
    >
      {/* Section header */}
      {selectedSection ? (
        <div
          className="flex items-center gap-3 px-6 py-3 shrink-0 border-b"
          style={{ borderColor: "var(--dim)" }}
        >
          <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>
            {selectedSection.name || "Unnamed section"}
          </h2>
          <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
            {selectedSection.format.replace(/_/g, " ")}
          </span>
        </div>
      ) : (
        <div
          className="flex items-center gap-3 px-6 py-3 shrink-0 border-b"
          style={{ borderColor: "var(--dim)" }}
        >
          <h2 className="text-lg font-bold" style={{ color: "var(--muted)" }}>
            Select a section to add exercises
          </h2>
        </div>
      )}

      {/* Exercise list */}
      <div className="flex-1 overflow-y-auto px-6 py-4 flex flex-col gap-3">
        {!selectedSection ? (
          <div className="flex-1 flex items-center justify-center">
            <p className="text-sm" style={{ color: "var(--dim)" }}>
              ← Select or add a section
            </p>
          </div>
        ) : selectedSection.exercises.length === 0 ? (
          <div className="flex-1 flex flex-col items-center justify-center gap-3">
            <p className="text-sm" style={{ color: "var(--dim)" }}>
              No exercises yet
            </p>
            <button
              onClick={() => addExercise(selectedSection.localId)}
              className="px-5 py-2 rounded-2xl text-sm font-semibold"
              style={{ background: "var(--accent)", color: "#0A0A0F" }}
            >
              + Add exercise
            </button>
          </div>
        ) : (
          <>
            <DndContext
              sensors={sensors}
              collisionDetection={closestCenter}
              onDragStart={handleDragStart}
              onDragEnd={handleDragEnd}
            >
              <SortableContext
                items={selectedSection.exercises.map((e) => e.localId)}
                strategy={verticalListSortingStrategy}
              >
                {selectedSection.exercises.map((exercise) => (
                  <ExerciseCard
                    key={exercise.localId}
                    exercise={exercise}
                    section={selectedSection}
                  />
                ))}
              </SortableContext>
              <DragOverlay>
                {activeId ? (
                  <div
                    className="rounded-2xl px-4 py-3 opacity-90"
                    style={{ background: "var(--card)", border: "1px solid var(--accent)" }}
                  >
                    {selectedSection.exercises.find((e) => e.localId === activeId)?.name ?? "Exercise"}
                  </div>
                ) : null}
              </DragOverlay>
            </DndContext>

            <button
              onClick={() => addExercise(selectedSection.localId)}
              className="rounded-2xl px-4 py-2 text-sm font-semibold self-start"
              style={{
                border: "1px dashed var(--dim)",
                color: "var(--muted)",
              }}
            >
              + Add exercise
            </button>
          </>
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/web/src/components/workouts/creation/MiddlePanel.tsx
git commit -m "feat(web/canvas): add MiddlePanel with sortable exercise list"
```
