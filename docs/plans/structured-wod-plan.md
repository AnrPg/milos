# Structured WOD editor (ADR-270): implementation plan

Status: in progress (2026-10-29). Owner thread: "Enable structured WOD editor with keyboard-only flow".
Approved design: the clickable mockup `docs/product/mockups/structured-wod-editor-mockup.html`
(alternative **A, the per-section wizard**: Ροή → Χρόνος → Ασκήσεις → Σκορ), its parsers
`docs/product/mockups/structured-wod-parsers.js`, and ANR's requirements below. Open the mockup in a
browser and use it: every behaviour described here is in it.

## Product rules (never regress)

- **Free text stays the default** way to write a WOD. A visible toggle in the editor switches a
  workout to **Structured** and back (`WorkoutAuthoringModes.tsx`). Existing workouts open in the
  mode they were written in.
- Three levels never mix: 1 **Flow** (how the clock runs: Σετ, For Time, AMRAP, EMOM, Intervals,
  Ξεκούραση), 2 **Structure** of one set or round per exercise or group (Απλό, Superset, Complex,
  Cluster, Drop set, Rest-pause), 3 **Add-ons** (interrupt every X; rest until heart rate falls).
  **Presets** (Tabata, Billat, HRR, Death by, Εναλλάξ μονά/ζυγά, Complex EMOM, EDT, Chipper,
  21-15-9, Σκάλα/πυραμίδα, Στόχος θερμίδων, Μέχρι αποτυχία, Superset/giant set, Cluster, Drop set,
  Rest-pause, Με διακοπή) are shortcuts that pre-fill a flow; they look different (grey box, grouped
  under their flow) because they are a different IA level.
- Format names never include the instance ("AMRAP", not "AMRAP 12'").
- Values can differ per set (12-10-8-8) and per round in **every** flow (Alt+V). Empty = as before,
  `+x` = change every time, `a→b` = spread to the last column. Ranges (8-12) allowed. Decimal loads
  (22.5 kg). Words allowed for load (βαρύ, με βάρος).
- Load unit (kg or %) is written **once per row**; bare numbers in other columns inherit it. A row of
  numbers with no unit anywhere is red ("Γράψε kg ή % σε ένα σετ της γραμμής"); a kg/% mix is red.
- Optional measures per row (Alt+P, fuzzy): Ρυθμός (/500m), Tempo (4 marks, e.g. 31X1; repeats only,
  never progresses), RPE (/10, max 10), RIR, Ζώνη παλμών, Ύψος/στόχος (cm), Απόσταση (m), Κράτημα
  (δευτ.), Ανά πλευρά (flag, shown as a tag next to the name and in summaries).
- Different exercises per round in every flow: blocks are kinds of round that alternate (1,3,5… /
  2,4,6…); Alt+S adds one. AMRAP has no last round: its per-round table shows the rounds the coach
  wrote plus one empty column that grows as they type; after the last written round the coach's own
  value applies (a number repeats, `+x` keeps going). **Never invent defaults** ANR did not agree.
- Supersets run **set-wise**: set 1 = every exercise of the group, then set 2… Execution and data
  follow this.
- Interruptions: do the main work, but every Y minutes stop for the interrupt rows, then resume.
- Notes: per exercise, per section, per WOD and per scale level; optional and quiet (Alt+N).
- Layout (ANR "cluttered / units far / cropped"): one grid with fixed columns (Άσκηση · Επαναλήψεις ·
  Φορτίο · added measures); the unit sits once in the column header / row label and right next to the
  value when typed; computed values (from +5, 60→80, inherited) show **inside the same field** (e.g.
  `65` with a tiny `+5` badge), never as an extra line under it; row actions live in one ⋯ menu
  (Alt+M); one quiet hint line shows the meaning of the focused value. On phones every exercise is a
  card and sets are rows; no horizontal scroll, no cropped text. Every dropdown closes on a click
  outside it and on Esc.
- Fully keyboard-operable; fuzzy, Meilisearch-like suggestions wherever free text is typed (exercise
  names, flows/presets, measures, menu actions). Shortcuts: Enter new exercise, Alt+M row actions,
  Alt+P measure, Alt+V per round, Alt+T structure, Alt+G superset with row above, Alt+R rest after,
  Alt+S different round, Alt+N note, Alt+←/→ wizard steps, Alt+1..4 jump to step, ? all shortcuts,
  Mod+Z / Mod+Shift+Z undo/redo, Backspace on an empty name deletes the row.
- Theme: only theme CSS vars, never hardcoded colours; native `<select>`/date inputs are banned
  (use `ui/Select`, `ui/DateInput`); overlays via `ui/Dialog`/`ui/Popover` and the `--z-*` scale.
- UI words follow `docs/product/ontology.md` (EN + EL). Greek: «τμήμα» for class, «ενότητα» for
  section, «Ροή», «Δομή σετ», «Παράμετρος», «Διακοπή».
- Every change updates its tests: vitest for logic and components, Playwright specs (and their API
  stubs) for screens, ExUnit for the API. Run dialyzer before API merges.

## Data contract

`apps/web/src/lib/structured-plan/types.ts` is the single contract (read it first). One
`PlanSection` per workout section.

API (ADR-270):
- New authoring mode `structured_plan` (string, alongside `free_text`, `sectioned_text`,
  `structured`, `quick_text`).
- New nullable JSONB column `workout_sections.plan` (migration timestamp `20270301000000`), holding a
  `PlanSection` (camelCase keys exactly as in `types.ts`, `v: 1`).
- `Palee.Workouts.Domain.StructuredPlan` (pure) validates a plan with the same parse rules as
  `parse.ts` (flows, params per flow, structures, measures, unit-once-per-row, tempo, RPE ≤ 10, size
  bounds) and returns errors with JSON paths.
- On save of a `structured_plan` workout the API materialises legacy `workout_exercises` rows from the
  plan (one per exercise row, in order, `superset_group_id` for groups, first-column reps/load where
  they are whole numbers, `exercise_ref`, `note`), so history, analytics and exercise links keep
  working. The plan stays the source of truth.
- `WorkoutBody` (ADR-224) gains kind `plan`: `%{kind: "plan", sections: [%{id, name, plan}]}`;
  summary: `%{kind: "plan", sections: [%{name, flow, exercise_count}]}`.
- Workout JSON exposes `sections[].plan`; OpenAPI + `apps/web/src/api/generated/*` regenerated.

Web modules (new):
- `apps/web/src/lib/structured-plan/` — `types.ts` (contract), `parse.ts` (port of the mockup
  parsers: clock, times, dose, load, nums, tempo; `setLoads`, `progress`, `repeatText`,
  `repeatDose`), `catalog.ts` (FLOWS, STRUCTS, MODS, MEASURES, PRESETS with i18n keys, aliases for
  fuzzy search in EN + EL), `rounds.ts` (`unitsOf`, `structOf`, `totalRounds`, `occurrences`,
  `blockLabel`), `describe.ts` (sentence + timeline segments + summary, used by editor and WOD view),
  `fuzzy.ts` (prefix, inside-word, subsequence, 1-2 typos; Greek accent-insensitive), `validate.ts`
  (same rules as the API), `factory.ts` (empty section, preset application, conversions between
  flows that keep values), `index.ts`. All pure, all vitest-covered.
- `apps/web/src/stores/structured-plan.ts` — zustand store for the editor (sections, open section,
  wizard step, undo/redo with 800 ms typing coalescing, all mutations used by shortcuts).
- `apps/web/src/components/workouts/plan-editor/` — the editor UI.
- `apps/web/src/components/workouts/plan-view/` — read-only WOD rendering (member + staff), also the
  final text where tempo shows nicely (↓3 ·1 ↑X ·1) and "ανά πλευρά" shows.
- `apps/web/src/components/workouts/execution/plan/` — running a plan.

i18n: new strings go under top-level namespaces in `apps/web/messages/*.json`: `PlanCore`,
`PlanEditor`, `PlanGrid`, `PlanView`, `PlanRun`. Write English and Greek; fill the other 10 locales
with real translations (not English copies) or leave them to the i18n pass, but keep
`npm run i18n:check` passing.

## Work split (one agent each, own files only)

| # | Agent | Owns | Depends on |
|---|-------|------|------------|
| 1 | Core logic | `apps/web/src/lib/structured-plan/**` (except `types.ts` changes need the lead) | types |
| 2 | API | `apps/api/**` (migration, schema, StructuredPlan, materialiser, WorkoutBody, JSON, OpenAPI, ExUnit), `apps/web/src/api/generated/*`, `apps/web/src/api/workouts.ts` plan fields | types |
| 3 | Editor shell | `stores/structured-plan.ts`, `plan-editor/` shell: section list cards, wizard header, step Ροή (flow + presets picker), step Χρόνος (params + timeline + add-ons), step Σκορ, notes, keyboard map, shortcuts sheet, undo/redo | 1 |
| 4 | Editor grid | `plan-editor/grid/`: exercise table, set grid, per-round table, value field, row menu, measures, structures, blocks (different rounds), interrupt lane, hint line, phone cards, exercise suggestions | 1, 3 (store API) |
| 5 | Integration + view | `WorkoutAuthoringModes.tsx` toggle (free text default), save/load/draft/publish of `structured_plan`, embedded mode, `plan-view/` and its use in `WorkoutPreviewDetail` and member screens | 1, 2, 3 |
| 6 | Execution | `components/workouts/execution/plan/**` and the hook-in in `ExecutionMode.tsx`: set-wise supersets, blocks/rounds, per-set values, EMOM/intervals/AMRAP clocks, interruptions, HR rest, scoring | 1 |
| 7 | Docs + i18n | `docs/adr/ADR-270-structured-wod-plan.md`, ADR index, `docs/product/ontology.md` terms, vision doc decision, `lib/seo/feature-catalog.ts`, later translations of the Plan* namespaces into all 12 locales | — |
| 8 | E2E | `apps/web/e2e/structured-wod*.spec.ts` + stubs: toggle, wizard keyboard flow, values/progressions, units red, per-round, blocks, phone layout, view, execution | 3-6 (test ids below) |

Shared test ids (`data-testid`): `authoring-toggle`, `plan-editor`, `plan-section-card`,
`plan-step-flow|time|exercises|score`, `plan-flow-input`, `plan-param-<key>`, `plan-row-<rowId>`,
`plan-cell-<rowId>-<col>-<key>`, `plan-row-menu`, `plan-hint`, `plan-add-exercise`, `plan-add-round`,
`plan-view`, `plan-run`, `plan-run-next`.
