# Workout Creation Canvas — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing `WorkoutForm.tsx` with a 3-panel canvas UX (left: sections, middle: exercises, right: preview), backed by a draft/publish save flow and an extended exercise prescription schema.

**Architecture:** Backend-first. The backend introduces a `status :draft/:published` field and `draft_data` JSONB autosave column on `master_workouts`, replaces the exercise prescription model (`base_reps/sets` → `prescription_value/unit + load_value/mode`), and adds three new endpoints (PATCH draft, POST publish, GET admin show). The frontend is a full replacement of `WorkoutForm.tsx` with a Zustand-driven, dnd-kit-powered 3-panel canvas.

**Tech Stack:** Elixir/Phoenix (Ecto, OpenApiSpex), Next.js 16 (App Router), TypeScript, Tailwind CSS, Zustand (store), dnd-kit (drag-and-drop)

---

## Sub-plan files

This plan is split into sections to stay within file limits:

- **[Backend tasks 1–7](./2026-06-07-workout-creation-ux-backend.md)** — Migration, schemas, services, routes, tests
- **[Frontend tasks 8–16](./2026-06-07-workout-creation-ux-frontend-a.md)** — Dependencies, types, store, canvas, header, left panel, format dropdown
- **[Frontend tasks 17–24](./2026-06-07-workout-creation-ux-frontend-b.md)** — Exercise card, variations, advanced settings, superset, preview, drag, mobile, save flow, wire-up

---

## File Map

### Backend — `apps/api/`

| Action | Path |
|---|---|
| Create | `priv/repo/migrations/20260607000000_extend_workout_model_for_canvas_ux.exs` |
| Modify | `lib/milos_training/workouts/master_workout.ex` |
| Modify | `lib/milos_training/workouts/workout_exercise.ex` |
| Modify | `lib/milos_training/workouts/exercise_variation.ex` |
| Modify | `lib/milos_training/workouts/domain/timer_config.ex` |
| Modify | `lib/milos_training/workouts/domain/workout_materializer.ex` |
| Modify | `lib/milos_training/workouts/ports/workout_store.ex` |
| Modify | `lib/milos_training/workouts.ex` |
| Modify | `lib/milos_training/infrastructure/workouts/ecto_workout_store.ex` |
| Create | `lib/milos_training/workouts/commands/create_draft_workout.ex` |
| Create | `lib/milos_training/workouts/commands/update_draft_workout.ex` |
| Create | `lib/milos_training/workouts/commands/publish_workout.ex` |
| Create | `lib/milos_training/application/publish_workout.ex` |
| Modify | `lib/milos_training_web/router.ex` |
| Modify | `lib/milos_training_web/controllers/admin_workout_controller.ex` |
| Modify | `test/milos_training_web/controllers/workout_controller_test.exs` |
| Create | `test/milos_training_web/controllers/admin_workout_controller_test.exs` |

### Frontend — `apps/web/src/`

| Action | Path |
|---|---|
| Create | `types/workout.ts` |
| Modify | `api/workouts.ts` |
| Create | `stores/workout-creation.ts` |
| Create | `components/workouts/creation/WorkoutCreationCanvas.tsx` |
| Create | `components/workouts/creation/CanvasHeader.tsx` |
| Create | `components/workouts/creation/LeftPanel.tsx` |
| Create | `components/workouts/creation/SectionChip.tsx` |
| Create | `components/workouts/creation/SectionConfig.tsx` |
| Create | `components/workouts/creation/FormatDropdown.tsx` |
| Create | `components/workouts/creation/FormatContextualFields.tsx` |
| Create | `components/workouts/creation/MiddlePanel.tsx` |
| Create | `components/workouts/creation/ExerciseCard.tsx` |
| Create | `components/workouts/creation/UnitCycler.tsx` |
| Create | `components/workouts/creation/VariationsPanel.tsx` |
| Create | `components/workouts/creation/AdvancedSettingsPanel.tsx` |
| Create | `components/workouts/creation/SupersetWrapper.tsx` |
| Create | `components/workouts/creation/RightPanel.tsx` |
| Create | `components/workouts/creation/PreviewSection.tsx` |
| Modify | `app/admin/workouts/new/page.tsx` |

---

## Key Design Decisions

1. **Draft autosave via `draft_data` JSONB** — `POST /api/admin/workouts` creates an empty draft row and returns `{ id }`. Every canvas change triggers a 1.5 s debounced `PATCH /api/admin/workouts/:id/draft` that stores the full current payload as a JSONB blob. No validation at autosave time. On publish, the blob is validated and materialized into sections/exercises.

2. **New exercise prescription model** — replaces `base_sets / base_reps / base_duration_seconds` with `sets / prescription_value / prescription_unit / load_value / load_mode`. Migration drops old columns; existing test is updated in the same task.

3. **Format renamed from Timer** — `timer_config` JSONB column is kept (name unchanged in DB), but `TimerConfig.normalize/1` is extended to handle all 18 format types from the spec.

4. **Frontend store is Zustand** — a single `useWorkoutCreationStore` manages all draft state. Canvas panels are React components reading from the store via selectors. No prop drilling.

5. **Drag via dnd-kit** — `SortableContext` for sections (left panel) and exercises (middle panel). Cross-section drag handled via `DragOverlay` + `onDragOver` with a 300 ms hover delay. Mobile cross-section moves go via the advanced panel action.

6. **Score type auto-inference is frontend-only** — formats with an unambiguous score type pre-populate `score_config.type` silently. Only ambiguous formats show the score type picker.

7. **Section config hides on click-away** — `selectedSectionId` in the store drives visibility. A global click listener on the canvas detects clicks outside the left panel and clears selection.

8. **Publish is a hard gate** — the Publish button is disabled until a client-side validity function returns true for all sections and exercises. On click: `POST /api/admin/workouts/:id/publish`. Success redirects to `/admin/workouts`.
