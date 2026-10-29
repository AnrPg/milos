# ADR-270: Structured WOD plan: flow, set structure and add-ons, written as typed
Date: 2026-10-29
Status: Accepted

## Context
ANR writes his programming in a file the way it goes on the box's whiteboard:
`Back Squat 4 × 12-10-8-8 @ 60% +5, tempo 31X1`, supersets of three
exercises with 30″ rest rows between them, an EMOM every 2:30 with a
front squat and a push press «βαρύ», AMRAPs whose rounds change, strength
work that stops every few minutes for something else. He asked (2026-10-29)
that the app's structured editor carry all of it, be fully keyboard-operable,
and never invent values he did not write.

The structured model of ADR-005 / ADR-006 could not. A section had one of 19
**formats** (`SectionFormat`), and every exercise row (`workout_exercises`)
held one prescription:
- `sets`, `prescription_value` and `load_value` are **integers**: no ranges
  (`8-12`, `3-4 sets`), no decimal loads (22.5 kg), no words (`βαρύ`,
  `max`, `με βάρος`);
- values per set existed only as a separate list for the `untimed` format;
  other formats had **no per-round values** (12-10-8 in an AMRAP), and no
  rounds with different exercises (odd / even was a special format);
- the 19 formats mixed three different things: how the clock runs (EMOM,
  AMRAP), what happens inside one set (cluster, EDT's superset) and how reps
  progress (ladders, pyramids, death by, train to exhaustion). Each mix needed
  its own format, form fields and execution code, and combinations (a cluster
  inside an EMOM, a superset inside an AMRAP) were impossible;
- there was no way to **interrupt** the main work every X minutes, no rest
  rows inside a group, and no optional measures (tempo, RPE, RIR, heart-rate
  zone, height, distance, hold, per side).

So coaches wrote these WODs as free text (ADR-224 `free_text` /
`text_sections`), which the execution screen and analytics can only partly
read.

## Decision
A new way of writing a workout, **Structured** («Δομημένο»), authoring mode
`structured_plan`. Free text stays the default; a visible toggle in the editor
switches a workout to Structured and back, and an existing workout opens in
the mode it was written in.

### Three levels, never mixed, and presets as shortcuts
1. **Flow** («Ροή»): how the clock runs for the whole section. Six only:
   Σετ (sets, no clock), For Time, AMRAP, EMOM, Intervals, Ξεκούραση (rest).
2. **Set structure** («Δομή σετ»): what happens inside one set or round, set
   on the exercise or group itself (Alt+T): Απλό (single), Superset, Complex,
   Cluster, Drop set, Rest-pause. Supersets run set-wise (set 1 of every
   exercise, then set 2).
3. **Add-ons** («Προσθήκες»): on top of a flow: interruption every X
   («Διακοπή κάθε…», with its own rows), and rest until heart rate falls
   («Ξεκούραση μέχρι να πέσουν οι παλμοί»).

Values belong to every flow: reps / quantity and load per set (Σετ) or per
round (Alt+V in the other flows); `empty` = as before, `+x` = change every
time, `a→b` = spread to the last column, ranges and decimals allowed; the
load unit (kg or %) written once per row. Optional **parameters**
(«Παράμετρος», Alt+P): Ρυθμός, Tempo, RPE, RIR, Ζώνη παλμών, Ύψος/στόχος,
Απόσταση, Κράτημα, Ανά πλευρά. **Different rounds** («Διαφορετικός γύρος»,
Alt+S) are blocks of exercises that alternate (rounds 1, 3, 5… / 2, 4, 6…).

Ladders, pyramids, death by, calorie targets and «μέχρι αποτυχία» are not
formats: they are written in the reps (`2-4-6…`, `1-2-3…`, `100 cal`,
`max`). Known names stay as **presets** («Έτοιμη μορφή»): shortcuts that
pre-fill the three levels. They are grouped under their flow and look
different in the picker, and a section only remembers which preset it came
from (for display).

### Where the 19 formats went

| Old format (`SectionFormat`) | Flow | Set structure / add-on / how it is written | Preset |
|---|---|---|---|
| `untimed` | Σετ | — | — |
| `for_time` | For Time | — | Chipper (optional) |
| `train_to_exhaustion` | Σετ | reps `max` | Μέχρι αποτυχία |
| `kcal_target` | For Time | reps `100 cal` | Στόχος θερμίδων |
| `emom` | EMOM | — | — |
| `complex_emom` | EMOM | 3 different rounds (slots) | Complex EMOM |
| `even_odd` | EMOM | 2 different rounds (odd / even) | Εναλλάξ (μονά / ζυγά) |
| `billat` | Intervals | 30″ work / 30″ off | Billat |
| `amrap` | AMRAP | — | — |
| `edt` | AMRAP | structure Superset | EDT |
| `death_by` | EMOM | reps `1-2-3…`, until failure | Death by |
| `tabata` | Intervals | 20″ / 10″ × 8 | Tabata |
| `custom_hiit` | Intervals | — | — |
| `cluster` | any (usually Σετ) | structure Cluster on one exercise | Cluster |
| `hrr` | Intervals | add-on: rest until heart rate falls | Ανάκαμψη παλμών (HRR) |
| `ladder_ascending` | For Time / AMRAP | reps `2-4-6…` | Σκάλα / πυραμίδα |
| `ladder_descending` | For Time | reps `10-8-6…` (also 21-15-9) | Σκάλα / πυραμίδα, 21-15-9 |
| `pyramid` | For Time | reps `2-4-6-4-2` | Σκάλα / πυραμίδα |
| `rest` | Ξεκούραση | — | — |
| *new* | Σετ / For Time / AMRAP | add-on: interruption every X | Με διακοπή |
| *new* | Σετ | structure Superset / Drop set / Rest-pause | Superset / giant set, Drop set, Rest-pause |

### Data
- One **`PlanSection`** JSON per section (`apps/web/src/lib/structured-plan/types.ts`,
  `v: 1`, camelCase keys), stored in the new nullable JSONB column
  **`workout_sections.plan`** (migration `20270301000000`). It holds the flow,
  its params, add-ons, the blocks of rows, interrupt rows, structures per
  exercise or group, score, notes and notes per scale level.
- Every value is stored **as the coach typed it** (`"8-12"`, `"22.5kg"`,
  `"+5"`, `"60→80"`, `"βαρύ"`). The web (`parse.ts`, `validate.ts`) and the
  API (`Palee.Workouts.Domain.StructuredPlan`) read it with the **same parse
  rules**; the API refuses what does not read and returns errors with JSON
  paths.
- On save the API **materialises legacy `workout_exercises` rows** from the
  plan (one per exercise row in order, `superset_group_id` for groups,
  first-column reps / load where they are whole numbers, `exercise_ref`,
  `note`), so history, analytics, exercise links and older clients keep
  working. The plan stays the source of truth.
- `WorkoutBody` (ADR-224) gains kind **`plan`**: `sections: [{id, name, plan}]`;
  its summary is `sections: [{name, flow, exercise_count}]`. Workout JSON
  exposes `sections[].plan`.

### Editor
The approved design is alternative **A, a wizard per section**
(Ροή → Χρόνος → Ασκήσεις → Σκορ, Alt+←/→, Alt+1..4): each step shows only what
the chosen flow needs, and a finished section closes into one line. Spec: the
clickable mockup `docs/product/mockups/structured-wod-editor-mockup.html` and
the plan `docs/plans/structured-wod-plan.md`.

## Rationale
- Separating flow, set structure and add-ons turns 19 special cases into
  6 + 6 + 2 parts that combine (a cluster inside an EMOM, a superset inside an
  AMRAP), and execution handles each part once.
- Keeping the names coaches know as presets costs nothing: they only fill the
  levels in.
- Storing text as typed loses nothing the coach wrote (ranges, decimals,
  words, progressions) and needs no schema change when a new notation is
  allowed; one set of parse rules on both sides keeps the editor and the API
  in agreement.
- Materialising legacy rows avoids a big-bang migration of every reader.

## Alternatives Considered
From the mockup's brief (2026-10-29):
- **A · Wizard per section** (chosen): ANR's own idea; each step shows only
  what the format needs, so it guides without hiding power.
- **B · One form that changes shape**: the same layouts without steps; fewer
  clicks but everything on screen at once, which ANR had already called
  cluttered.
- **Γ · Write like a whiteboard** (version 2 of the mockup): type
  `12-10-8-8` and the format is inferred. Fastest for experienced coaches,
  least guiding. Its notation survives inside the cells of step 3.
- Extending the old columns (decimals, ranges, more formats): every new need
  would add columns and formats again, and combinations stay impossible.
- Normalised tables per row and cell: heavy migrations and joins for data that
  is always read and written per section.

## Consequences
- Two structured models live side by side: the old `structured` mode
  (ADR-005 / 006) for existing workouts and `structured_plan` for new ones.
  The old editor is not removed in this change.
- Legacy rows hold only what fits the old integers; analytics that need ranges,
  per-round values or parameters must read the plan.
- Parse rules exist twice (TypeScript and Elixir) and must stay in step; tests
  on both sides cover the same cases.
- New UI terms (Ροή, Δομή σετ, Προσθήκη, Έτοιμη μορφή, Παράμετρος, Διακοπή,
  Διαφορετικός γύρος, Ανά γύρο, Δομημένο / Ελεύθερο κείμενο) are in
  `docs/product/ontology.md`.
- The execution screen runs plans (set-wise supersets, per-round values,
  interruptions, heart-rate rest).

## Implementation Notes
Work split, test ids and owners are in `docs/plans/structured-wod-plan.md`.
UI strings live under the `PlanCore`, `PlanEditor`, `PlanGrid`, `PlanView` and
`PlanRun` namespaces in all twelve locales.
