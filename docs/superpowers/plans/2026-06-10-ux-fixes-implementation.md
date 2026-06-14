# UX Fixes & Feature Completions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 16 UX fixes and feature completions across schedule, my-workouts, notifications, workout drafts, and UI/roles — organised in 5 domain clusters.

**Architecture:** Hexagonal backend (Elixir/Phoenix) with ports & adapters; Next.js 15 frontend. Each cluster is independently deployable. Backend changes precede frontend changes within a cluster wherever a new endpoint is required.

**Tech Stack:** Elixir 1.16 / Phoenix 1.7, Next.js 15, TypeScript, Tailwind CSS, @dnd-kit/core, React Query, Phoenix Channels.

---

## Pre-flight checks

- [ ] Confirm working directory: `cd /home/rodochrousbisbiki/MyApps/milos`
- [ ] Backend compiles: `cd apps/api && mix compile --warnings-as-errors`
- [ ] Frontend compiles: `cd apps/web && npx tsc --noEmit`

---

## Cluster 1 — Panel & Preview System

### Task 1: Shared workout-type colour utility (Item 6)

**Files:**
- Create: `apps/web/src/lib/workout-colors.ts`
- Modify: `apps/web/src/components/schedule/SlotPopup.tsx`
- Modify: `apps/web/src/components/workouts/AssignedWorkoutPanel.tsx`
- Modify: `apps/web/src/components/workouts/AssignedWorkoutsConsole.tsx`

- [ ] **Step 1: Create shared colour map**

```typescript
// apps/web/src/lib/workout-colors.ts
export const WORKOUT_TYPE_COLORS: Record<string, string> = {
  crossfit:    "#c0392b",
  strength:    "#d95d39",
  gymnastics:  "#c97b4b",
  aerobics:    "#b5651d",
  flexibility: "#8b4513",
  recovery:    "#6b3a2a",
};

export function workoutTypeColor(type: string): string {
  return WORKOUT_TYPE_COLORS[type] ?? "#d95d39";
}
```

- [ ] **Step 2: Update SlotPopup to import from shared utility**

In `apps/web/src/components/schedule/SlotPopup.tsx`, replace the local definition:

```typescript
// Remove these lines:
export const TRAINING_TYPE_COLORS: Record<TrainingType, string> = {
  crossfit: "#b83225",
  strength: "#d94a28",
  gymnastics: "#d95d39",
  aerobics: "#c26645",
  flexibility: "#a05040",
  recovery: "#7a4838",
};

function trainingTypeColor(type: TrainingType | string): string {
  return TRAINING_TYPE_COLORS[type as TrainingType] ?? "#d95d39";
}
```

Replace with:

```typescript
import { workoutTypeColor } from "@/lib/workout-colors";
```

Then replace all `trainingTypeColor(...)` calls with `workoutTypeColor(...)`.

- [ ] **Step 3: Add colour to AssignedWorkoutPanel type label**

In `apps/web/src/components/workouts/AssignedWorkoutPanel.tsx`, add the import and apply the colour to the type label:

```typescript
import { workoutTypeColor } from "@/lib/workout-colors";
```

Find the type label paragraph (currently hardcoded `text-[#d95d39]`) and update:

```tsx
<p
  className="truncate text-xs font-semibold uppercase tracking-[0.2em]"
  style={{ color: workoutTypeColor(assignment.workout.type) }}
>
  {assignment.workout.type}
</p>
```

- [ ] **Step 4: Apply colour in AssignedWorkoutsConsole workout cards**

In `apps/web/src/components/workouts/AssignedWorkoutsConsole.tsx`, add import:

```typescript
import { workoutTypeColor } from "@/lib/workout-colors";
```

In the 3-day view card (the `<p>` showing `assignment.workout.type` with hardcoded `text-[#d95d39]`):

```tsx
<p
  className="text-xs font-semibold uppercase tracking-[0.18em]"
  style={{ color: workoutTypeColor(assignment.workout.type) }}
>
  {assignment.workout.type}
</p>
```

In `DragGhostCard` (currently hardcoded `#d95d39`):

```tsx
<p
  className="text-[10px] font-semibold uppercase tracking-[0.18em]"
  style={{ color: workoutTypeColor(assignment.workout.type) }}
>
  {assignment.workout.type}
</p>
```

In `DraggableMonthChip`, update the chip background/colour to use the type colour with alpha:

```tsx
<p
  ref={setNodeRef}
  className="mt-0.5 truncate rounded px-1 py-0.5 text-[9px] font-semibold"
  style={{
    background: `${workoutTypeColor(assignment.workout.type)}26`,
    color: workoutTypeColor(assignment.workout.type),
    opacity: isDragging ? 0.3 : 1,
    cursor: "grab",
    touchAction: "none",
  }}
  {...listeners}
  {...attributes}
>
  {assignment.workout.title}
</p>
```

- [ ] **Step 5: Verify TypeScript**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | head -30
```

Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add apps/web/src/lib/workout-colors.ts \
        apps/web/src/components/schedule/SlotPopup.tsx \
        apps/web/src/components/workouts/AssignedWorkoutPanel.tsx \
        apps/web/src/components/workouts/AssignedWorkoutsConsole.tsx
git commit -m "feat: extract shared workout-type colour palette and propagate to all cards"
```

---

### Task 2: Fix side panel top offset — Close button no longer obscured (Item 2)

**Files:**
- Modify: `apps/web/src/components/schedule/SlotPopup.tsx`
- Modify: `apps/web/src/components/workouts/AssignedWorkoutPanel.tsx`

TopNav height is `3.25rem` (`52px`). Both panels must start at or below the nav.

- [ ] **Step 1: Fix SlotPopup panel container**

In `apps/web/src/components/schedule/SlotPopup.tsx`, find the outer panel div:

```tsx
<div
  className="h-full w-full max-w-xl overflow-y-auto"
  style={{ background: "#111118", borderLeft: "1px solid #1a1a28" }}
  onClick={(e) => e.stopPropagation()}
>
```

Change to:

```tsx
<div
  className="flex h-full w-full max-w-xl flex-col overflow-hidden"
  style={{ background: "#111118", borderLeft: "1px solid #1a1a28", paddingTop: "3.25rem" }}
  onClick={(e) => e.stopPropagation()}
>
  <div className="flex-1 overflow-y-auto">
```

Close the new inner div before the outer div closing tag:

```tsx
  </div>
</div>
```

The sticky header is now relative to this inner scrollable div, sitting naturally at the top of the visible area below the TopNav.

- [ ] **Step 2: Fix AssignedWorkoutPanel container**

In `apps/web/src/components/workouts/AssignedWorkoutPanel.tsx`, find the panel div:

```tsx
<div
  className="fixed inset-y-0 right-0 z-50 flex w-full flex-col overflow-hidden md:max-w-[480px]"
  style={{ background: "#0A0A0F", borderLeft: "1px solid #1a1a28" }}
>
```

Change to:

```tsx
<div
  className="fixed right-0 bottom-0 z-50 flex w-full flex-col overflow-hidden md:max-w-[480px]"
  style={{
    background: "#0A0A0F",
    borderLeft: "1px solid #1a1a28",
    top: "3.25rem",
  }}
>
```

- [ ] **Step 3: Verify TypeScript**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | head -30
```

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/components/schedule/SlotPopup.tsx \
        apps/web/src/components/workouts/AssignedWorkoutPanel.tsx
git commit -m "fix: side panels start below TopNav so Close button is always accessible"
```

---

### Task 3: Full exercise variations in assigned workout preview (Item 1)

**Root cause:** `normalize_assigned_workout/1` in `ecto_workout_store.ex` calls `normalize_base_exercise/1` which omits `variations`. Fix: use `normalize_exercise/1` instead. Add `variations` to frontend TypeScript type.

**Files:**
- Modify: `apps/api/lib/milos_training/infrastructure/workouts/ecto_workout_store.ex`
- Modify: `apps/web/src/api/assigned-workouts.ts`

- [ ] **Step 1: Write backend test**

In `apps/api/test/milos_training/application/get_assigned_workout_week_test.exs` (create if absent):

```elixir
test "assigned workout exercises include variations", %{admin: admin, athlete: athlete} do
  scale_level = insert(:scale_level, slug: "rx", label: "Rx")
  workout = insert(:published_workout_with_variation, scale_level: scale_level)
  insert(:assigned_workout, master_workout: workout, athletes: [athlete])

  {:ok, payload} = GetAssignedWorkoutWeek.call(admin)

  [assignment] = payload.assignments
  [section] = assignment.workout.sections
  [exercise] = section.exercises
  assert length(exercise.variations) == 1
  assert hd(exercise.variations).scale_level.slug == "rx"
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
cd apps/api && mix test test/milos_training/application/get_assigned_workout_week_test.exs 2>&1 | tail -20
```

Expected: test fails (variations is nil or empty).

- [ ] **Step 3: Fix backend — use normalize_exercise in assigned workout**

In `apps/api/lib/milos_training/infrastructure/workouts/ecto_workout_store.ex`, find `normalize_assigned_workout`:

```elixir
defp normalize_assigned_workout(%MasterWorkout{} = workout) do
  %{
    id: workout.id,
    title: workout.title,
    type: workout.type |> to_string(),
    sections: normalize_sections(workout.sections, exercise_mapper: &normalize_base_exercise/1)
  }
end
```

Change to:

```elixir
defp normalize_assigned_workout(%MasterWorkout{} = workout) do
  %{
    id: workout.id,
    title: workout.title,
    type: workout.type |> to_string(),
    sections: normalize_sections(workout.sections)
  }
end
```

(`normalize_sections/1` without opts defaults to `normalize_exercise/1` which includes variations.)

- [ ] **Step 4: Run test to confirm it passes**

```bash
cd apps/api && mix test test/milos_training/application/get_assigned_workout_week_test.exs 2>&1 | tail -10
```

Expected: 1 test, 0 failures.

- [ ] **Step 5: Add variations to frontend TypeScript type**

In `apps/web/src/api/assigned-workouts.ts`, find the `AssignedWorkoutPreview` exercise type and add variations:

```typescript
export type AssignedWorkoutPreview = {
  id: string;
  title: string;
  type: string;
  sections: Array<{
    id?: string;
    parent_section_id?: string | null;
    name: string;
    order: number;
    scoreable: boolean;
    score_config?: Record<string, unknown> | null;
    timer_config?: Record<string, unknown> | null;
    exercises: Array<{
      id?: string;
      name: string;
      sets?: number | null;
      prescription_value?: number | null;
      prescription_unit?: string | null;
      load_value?: number | null;
      load_mode?: string | null;
      superset_group_id?: string | null;
      hr_zone?: number | null;
      tempo?: string | null;
      rest_seconds?: number | null;
      cluster_rest_seconds?: number | null;
      rest_pause_seconds?: number | null;
      pacing?: number | null;
      interval_assignment?: number | null;
      order: number;
      variations?: Array<{
        id?: string;
        description?: string | null;
        sets?: number | null;
        prescription_value?: number | null;
        prescription_unit?: string | null;
        load_value?: number | null;
        load_mode?: string | null;
        excluded?: boolean;
        scale_level?: { id?: string; slug?: string; label?: string; sort_order?: number } | null;
      }>;
    }>;
  }>;
};
```

- [ ] **Step 6: Run backend tests and TypeScript check**

```bash
cd apps/api && mix test 2>&1 | tail -5
cd apps/web && npx tsc --noEmit 2>&1 | head -20
```

- [ ] **Step 7: Commit**

```bash
git add apps/api/lib/milos_training/infrastructure/workouts/ecto_workout_store.ex \
        apps/api/test/milos_training/application/get_assigned_workout_week_test.exs \
        apps/web/src/api/assigned-workouts.ts
git commit -m "fix: include exercise variations in assigned workout preview (item 1)"
```

---

## Cluster 2 — Athlete Workout Management

### Task 4: Athlete drag-and-drop + reschedule endpoint (Item 10)

**Files:**
- Create: `apps/api/lib/milos_training/application/reschedule_assigned_workout.ex`
- Modify: `apps/api/lib/milos_training_web/controllers/my_workout_controller.ex`
- Modify: `apps/api/lib/milos_training_web/router.ex`
- Modify: `apps/api/lib/milos_training/notifications.ex`
- Modify: `apps/web/src/api/assigned-workouts.ts`
- Modify: `apps/web/src/components/workouts/AssignedWorkoutsConsole.tsx`
- Modify: `apps/web/src/components/workouts/AssignedWorkoutPanel.tsx`

- [ ] **Step 1: Write backend test for reschedule**

Create `apps/api/test/milos_training/application/reschedule_assigned_workout_test.exs`:

```elixir
defmodule MilosTraining.Application.RescheduleAssignedWorkoutTest do
  use MilosTraining.DataCase

  alias MilosTraining.Application.RescheduleAssignedWorkout

  test "athlete can reschedule their own assignment to a future date" do
    athlete = insert(:user, role: :athlete)
    workout = insert(:published_workout)
    assignment = insert(:assigned_workout,
      master_workout: workout,
      athletes: [athlete],
      scheduled_for: Date.utc_today() |> Date.add(1)
    )
    new_date = Date.utc_today() |> Date.add(5) |> Date.to_iso8601()

    assert {:ok, updated} = RescheduleAssignedWorkout.call(assignment.id, athlete.id, new_date)
    assert updated.scheduled_for == Date.from_iso8601!(new_date)
  end

  test "athlete cannot reschedule to a past date" do
    athlete = insert(:user, role: :athlete)
    workout = insert(:published_workout)
    assignment = insert(:assigned_workout,
      master_workout: workout,
      athletes: [athlete],
      scheduled_for: Date.utc_today() |> Date.add(1)
    )
    past_date = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()

    assert {:error, :past_date} = RescheduleAssignedWorkout.call(assignment.id, athlete.id, past_date)
  end

  test "athlete cannot reschedule another athlete's assignment" do
    athlete = insert(:user, role: :athlete)
    other_athlete = insert(:user, role: :athlete)
    workout = insert(:published_workout)
    assignment = insert(:assigned_workout,
      master_workout: workout,
      athletes: [other_athlete],
      scheduled_for: Date.utc_today() |> Date.add(1)
    )
    new_date = Date.utc_today() |> Date.add(3) |> Date.to_iso8601()

    assert {:error, :forbidden} = RescheduleAssignedWorkout.call(assignment.id, athlete.id, new_date)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
cd apps/api && mix test test/milos_training/application/reschedule_assigned_workout_test.exs 2>&1 | tail -10
```

Expected: compilation error (module not found).

- [ ] **Step 3: Create RescheduleAssignedWorkout application service**

Create `apps/api/lib/milos_training/application/reschedule_assigned_workout.ex`:

```elixir
defmodule MilosTraining.Application.RescheduleAssignedWorkout do
  require Logger

  alias MilosTraining.{Notifications, Workouts}

  def call(assignment_id, athlete_id, new_date_str) do
    with {:ok, new_date} <- parse_date(new_date_str),
         :ok <- guard_future_date(new_date),
         assignment when not is_nil(assignment) <- Workouts.get_assigned_workout(assignment_id),
         :ok <- verify_athlete_access(assignment, athlete_id),
         {:ok, updated} <- Workouts.update_assignment_date(assignment_id, new_date) do
      notify_admins_workout_moved(assignment, athlete_id, new_date)
      {:ok, updated}
    else
      nil -> {:error, :not_found}
      {:error, :past_date} = e -> e
      {:error, :forbidden} = e -> e
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, :bad_request}
    end
  end

  defp guard_future_date(date) do
    if Date.compare(date, Date.utc_today()) == :lt do
      {:error, :past_date}
    else
      :ok
    end
  end

  defp verify_athlete_access(assignment, athlete_id) do
    athlete_ids = Enum.map(assignment.athlete_links, & &1.athlete_id)
    if athlete_id in athlete_ids, do: :ok, else: {:error, :forbidden}
  end

  defp notify_admins_workout_moved(assignment, athlete_id, new_date) do
    case MilosTraining.Identity.get_user(athlete_id) do
      nil ->
        :ok

      athlete ->
        payload = %{
          athlete_nickname: athlete.nickname,
          workout_title: assignment.master_workout.title,
          from_date: Date.to_iso8601(assignment.scheduled_for),
          to_date: Date.to_iso8601(new_date),
          assignment_id: assignment.id,
          url: "/admin/coaching-assignments?open_assignment=#{assignment.id}"
        }

        Notifications.process_event("workout_moved", payload)
    end
  end
end
```

- [ ] **Step 4: Add `get_assigned_workout` and `update_assignment_date` to Workouts context**

In `apps/api/lib/milos_training/workouts.ex`, add delegations (and implement in the port/store):

```elixir
defdelegate get_assigned_workout(id), to: WorkoutStore
defdelegate update_assignment_date(id, date), to: WorkoutStore
```

In `apps/api/lib/milos_training/workouts/ports/workout_store.ex`, add specs:

```elixir
@callback get_assigned_workout(String.t()) :: map() | nil
@callback update_assignment_date(String.t(), Date.t()) :: {:ok, map()} | {:error, term()}
```

In `apps/api/lib/milos_training/infrastructure/workouts/ecto_workout_store.ex`, implement:

```elixir
@impl true
def get_assigned_workout(id) do
  AssignedWorkout
  |> Repo.get(id)
  |> case do
    nil -> nil
    assignment -> Repo.preload(assignment, [:athlete_links, master_workout: @workout_preloads])
  end
end

@impl true
def update_assignment_date(id, new_date) do
  case Repo.get(AssignedWorkout, id) do
    nil ->
      {:error, :not_found}

    assignment ->
      assignment
      |> Ecto.Changeset.change(scheduled_for: new_date)
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          preloaded = Repo.preload(updated, [:athlete_links, master_workout: @workout_preloads])
          {:ok, normalize_assignment(preloaded)}

        {:error, changeset} ->
          {:error, changeset}
      end
  end
end
```

- [ ] **Step 5: Add `workout_moved` notification support**

In `apps/api/lib/milos_training/notifications.ex`, add after the existing `process_event` clauses:

```elixir
def process_event("workout_moved", payload), do: enqueue_workout_moved(payload)
```

Add the delivery function:

```elixir
def enqueue_workout_moved(%{athlete_nickname: nick, workout_title: title, from_date: from,
                            to_date: to, assignment_id: _aid, url: url} = payload) do
  admins = MilosTraining.Identity.list_admins()

  Enum.each(admins, fn admin ->
    body = "#{nick} moved \"#{title}\" from #{from} to #{to}."

    deliver_notification(admin.id, :workout_moved, Map.merge(payload, %{body: body, url: url}))
  end)

  :ok
end
```

- [ ] **Step 6: Add reschedule route and controller action**

In `apps/api/lib/milos_training_web/router.ex`, inside the authenticated athlete scope, add:

```elixir
patch "/my-workouts/assignments/:id/reschedule", MyWorkoutController, :reschedule
```

In `apps/api/lib/milos_training_web/controllers/my_workout_controller.ex`, add at the top:

```elixir
alias MilosTraining.Application.RescheduleAssignedWorkout
```

Add the action:

```elixir
operation(:reschedule,
  summary: "Athlete reschedules an assigned workout to a new date",
  parameters: [
    %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string, format: :uuid}}
  ],
  request_body: %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: %{scheduled_for: %Schema{type: :string, format: :date}},
          required: [:scheduled_for]
        }
      }
    }
  },
  responses: [
    ok: {"Rescheduled", "application/json", %Schema{type: :object, additionalProperties: true}},
    unprocessable_entity: {"Past date or forbidden", "application/json", %Schema{type: :object}}
  ]
)

def reschedule(conn, %{"id" => assignment_id} = params) do
  user = GuardianPlug.current_resource(conn)
  new_date = get_in(params, ["scheduled_for"]) || get_in(conn.body_params, ["scheduled_for"]) || ""

  case RescheduleAssignedWorkout.call(assignment_id, user.id, new_date) do
    {:ok, assignment} -> json(conn, %{assignment: assignment})
    {:error, :not_found} -> {:error, :not_found}
    {:error, :forbidden} -> {:error, :forbidden}
    {:error, :past_date} -> {:error, :unprocessable_entity}
    {:error, _} -> {:error, :unprocessable_entity}
  end
end
```

- [ ] **Step 7: Run backend tests**

```bash
cd apps/api && mix test test/milos_training/application/reschedule_assigned_workout_test.exs 2>&1 | tail -10
```

Expected: 3 tests, 0 failures.

- [ ] **Step 8: Add `rescheduleAssignment` to frontend API**

In `apps/web/src/api/assigned-workouts.ts`, add:

```typescript
export async function rescheduleAssignment(
  token: string,
  assignmentId: string,
  scheduledFor: string,
): Promise<AssignedWorkoutRecord> {
  const response = await apiRequest<{ assignment: AssignedWorkoutRecord }>(
    `/my-workouts/assignments/${assignmentId}/reschedule`,
    { method: "PATCH", token, body: { scheduled_for: scheduledFor } },
  );
  return response.assignment;
}
```

- [ ] **Step 9: Enable DnD for all users in AssignedWorkoutsConsole**

In `apps/web/src/components/workouts/AssignedWorkoutsConsole.tsx`:

**a)** In `DraggableCard`, change `disabled: !isAdmin` → `disabled: false` and always show the drag handle:

```tsx
const { attributes, listeners, setNodeRef, setActivatorNodeRef, isDragging } = useDraggable({
  id: assignment.id,
  data: { assignment },
  disabled: false,
});

return (
  <div
    ref={setNodeRef}
    className={className}
    style={{ ...style, opacity: isDragging ? 0.3 : 1, position: "relative" }}
  >
    <span
      ref={(el) => setActivatorNodeRef(el)}
      className="absolute right-2 top-2 z-10 select-none rounded p-1 text-base leading-none"
      style={{ color: "#3a3a55", cursor: "grab", touchAction: "none" }}
      {...listeners}
      {...attributes}
      role="button"
      tabIndex={-1}
      aria-label="Drag to reschedule"
    >
      ⠿
    </span>
    {children}
  </div>
);
```

**b)** In `DraggableMonthChip`, change `disabled: !isAdmin` → `disabled: false` and always spread listeners:

```tsx
const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
  id: assignment.id,
  data: { assignment },
  disabled: false,
});

return (
  <p
    ref={setNodeRef}
    className="mt-0.5 truncate rounded px-1 py-0.5 text-[9px] font-semibold"
    style={{
      background: `${workoutTypeColor(assignment.workout.type)}26`,
      color: workoutTypeColor(assignment.workout.type),
      opacity: isDragging ? 0.3 : 1,
      cursor: "grab",
      touchAction: "none",
    }}
    {...listeners}
    {...attributes}
  >
    {assignment.workout.title}
  </p>
);
```

**c)** Update `handleDragEnd` to add past-date guard and route by role:

```tsx
async function handleDragEnd({ active, over }: DragEndEvent) {
  setActiveAssignment(null);
  if (!over || !tokens?.access_token) return;

  const newDate = over.id as string;
  const assignment = allAssignments.find((a) => a.id === active.id);
  if (!assignment || assignment.scheduled_for === newDate) return;

  // Reject past dates for all users
  if (newDate < todayIso) {
    setError("Cannot reschedule to a past date.");
    return;
  }

  const snapshot = allAssignments;
  setAllAssignments((current) =>
    current.map((a) => (a.id === assignment.id ? { ...a, scheduled_for: newDate } : a)),
  );

  void (async () => {
    try {
      if (isAdmin) {
        await updateAssignedWorkout(tokens.access_token!, assignment.id, {
          scheduled_for: newDate,
          athlete_ids: assignment.athlete_ids ?? [],
          admin_notes: assignment.admin_notes ?? undefined,
        });
      } else {
        await rescheduleAssignment(tokens.access_token!, assignment.id, newDate);
      }
    } catch {
      setAllAssignments(snapshot);
      setError("Could not reschedule workout.");
    }
  })();
}
```

Add import at the top of the file:

```typescript
import { ..., rescheduleAssignment } from "@/api/assigned-workouts";
```

- [ ] **Step 10: Add Reschedule form to AssignedWorkoutPanel**

In `apps/web/src/components/workouts/AssignedWorkoutPanel.tsx`, add state for reschedule form and the new `rescheduleAssignment` import:

```typescript
import { rescheduleAssignment, type AssignedWorkoutRecord } from "@/api/assigned-workouts";
```

Add state in the component:

```typescript
const [rescheduling, setRescheduling] = useState(false);
const [rescheduleDate, setRescheduleDate] = useState("");
const [rescheduleError, setRescheduleError] = useState<string | null>(null);
const [rescheduleSaving, setRescheduleSaving] = useState(false);
```

Add a `handleReschedule` function:

```typescript
async function handleReschedule() {
  if (!rescheduleDate) return;
  setRescheduleSaving(true);
  setRescheduleError(null);
  try {
    const updated = isAdmin
      ? await updateAssignedWorkout(accessToken, assignment.id, {
          scheduled_for: rescheduleDate,
          athlete_ids: (assignment as AssignedWorkoutRecord & { athlete_ids?: string[] }).athlete_ids ?? [],
          admin_notes: assignment.admin_notes ?? undefined,
        })
      : await rescheduleAssignment(accessToken, assignment.id, rescheduleDate);
    onRescheduled?.(updated);
    onClose();
  } catch (err) {
    setRescheduleError(err instanceof Error ? err.message : "Could not reschedule.");
  } finally {
    setRescheduleSaving(false);
  }
}
```

Add `onRescheduled` to Props:

```typescript
type Props = {
  assignment: AssignedWorkoutRecord;
  isAdmin: boolean;
  accessToken: string;
  onClose: () => void;
  onStartWorkout: (assignment: AssignedWorkoutRecord) => void;
  onRejected?: (assignmentId: string) => void;
  onRescheduled?: (updated: AssignedWorkoutRecord) => void;
  launching?: boolean;
};
```

Add the reschedule section in the scrollable body, after admin notes and before the message form:

```tsx
{/* Reschedule */}
<section>
  {!rescheduling ? (
    <button
      className="rounded-full px-4 py-2 text-sm font-semibold"
      style={{ background: "#1a1a28", color: "#c0c0d8" }}
      onClick={() => {
        setRescheduleDate(assignment.scheduled_for);
        setRescheduling(true);
      }}
      type="button"
    >
      Reschedule
    </button>
  ) : (
    <div className="space-y-2">
      <input
        className="w-full rounded-[1rem] px-4 py-2 text-sm outline-none"
        style={{ background: "#111118", border: "1px solid #1e1e2e", color: "#F0EDF8" }}
        type="date"
        min={todayIso}
        value={rescheduleDate}
        onChange={(e) => setRescheduleDate(e.target.value)}
      />
      {rescheduleError ? (
        <p className="text-xs" style={{ color: "#e07a5f" }}>{rescheduleError}</p>
      ) : null}
      <div className="flex gap-2">
        <button
          className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
          style={{ background: "#F0EDF8", color: "#0A0A0F" }}
          disabled={rescheduleSaving || !rescheduleDate}
          onClick={() => void handleReschedule()}
          type="button"
        >
          {rescheduleSaving ? "Saving…" : "Confirm"}
        </button>
        <button
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "#1a1a28", color: "#8888aa" }}
          onClick={() => setRescheduling(false)}
          type="button"
        >
          Cancel
        </button>
      </div>
    </div>
  )}
</section>
```

Add `todayIso` constant at the top of the file:

```typescript
const todayIso = new Date().toISOString().split("T")[0];
```

Update the `AssignedWorkoutsConsole` call site to pass `onRescheduled` that updates `allAssignments`:

```tsx
<AssignedWorkoutPanel
  ...
  onRescheduled={(updated) => {
    setAllAssignments((current) =>
      current.map((a) => (a.id === updated.id ? updated : a)),
    );
  }}
/>
```

(Also need to import `updateAssignedWorkout` in `AssignedWorkoutPanel` for the admin reschedule path, or better — pass a reschedule callback from the parent. Simplest: import `updateAssignedWorkout` in `AssignedWorkoutPanel` directly since it already imports from `assigned-workouts`.)

- [ ] **Step 11: Add workout_moved to NotificationBell**

In `apps/web/src/components/notifications/NotificationBell.tsx`, in `notificationTitle`:

```typescript
case "workout_moved":
  return "Workout rescheduled";
```

In `notificationBody`, add a case for `workout_moved`:

```typescript
if (notification.type === "workout_moved") {
  return typeof notification.payload.body === "string"
    ? notification.payload.body
    : "An athlete rescheduled their workout.";
}
```

- [ ] **Step 12: TypeScript and backend tests**

```bash
cd apps/api && mix test 2>&1 | tail -5
cd apps/web && npx tsc --noEmit 2>&1 | head -20
```

- [ ] **Step 13: Commit**

```bash
git add apps/api/lib/milos_training/application/reschedule_assigned_workout.ex \
        apps/api/lib/milos_training_web/controllers/my_workout_controller.ex \
        apps/api/lib/milos_training_web/router.ex \
        apps/api/lib/milos_training/notifications.ex \
        apps/api/lib/milos_training/workouts.ex \
        apps/api/lib/milos_training/workouts/ports/workout_store.ex \
        apps/api/lib/milos_training/infrastructure/workouts/ecto_workout_store.ex \
        apps/web/src/api/assigned-workouts.ts \
        apps/web/src/components/workouts/AssignedWorkoutsConsole.tsx \
        apps/web/src/components/workouts/AssignedWorkoutPanel.tsx \
        apps/web/src/components/notifications/NotificationBell.tsx
git commit -m "feat: enable DnD and reschedule for athletes + workout_moved notification (item 10)"
```

---

## Cluster 3 — Notification System

### Task 5: Notification URLs with deep-link panel params (Item 9)

**Files:**
- Modify: `apps/api/lib/milos_training/application/publish_workout.ex`
- Modify: `apps/api/lib/milos_training/application/delete_workout.ex`
- Modify: `apps/api/lib/milos_training/application/reject_assigned_workout.ex`
- Modify: `apps/web/src/app/schedule/page.tsx`
- Modify: `apps/web/src/components/schedule/ScheduleConsole.tsx`
- Modify: `apps/web/src/app/my-workouts/page.tsx`
- Modify: `apps/web/src/components/workouts/AssignedWorkoutsConsole.tsx`

- [ ] **Step 1: Add assignment ID to workout_changed assignment notifications URL**

In `apps/api/lib/milos_training/application/publish_workout.ex`, in `notify_assignment_targets`:

```elixir
payload = %{
  kind: "assigned_workout",
  assigned_workout_id: target.assigned_workout_id,
  scheduled_for: Date.to_iso8601(target.scheduled_for),
  body:
    "Your coach updated the workout for #{format_date(target.scheduled_for)}: #{workout.title}.",
  url: "/my-workouts?open_assignment=#{target.assigned_workout_id}"
}
```

In `notify_booking_targets`:

```elixir
payload = %{
  kind: "scheduled_class",
  scheduled_class_id: Map.get(target, :scheduled_class_id),
  training_type: to_string(training_type || ""),
  body:
    "The workout for your #{format_training_type(training_type)} class has been updated: #{workout.title}.",
  url: "/schedule?open_slot=#{Map.get(target, :scheduled_class_id)}"
}
```

- [ ] **Step 2: Add IDs to workout_deleted notifications URL**

In `apps/api/lib/milos_training/application/delete_workout.ex`:

In `notify_assignment_targets`:
```elixir
url: "/my-workouts?open_assignment=#{target.assigned_workout_id}"
```

In `notify_booking_targets`:
```elixir
url: "/schedule?open_slot=#{target.scheduled_class_id}"
```

- [ ] **Step 3: Add schedule/page.tsx to read open_slot param and pass to console**

In `apps/web/src/app/schedule/page.tsx`:

```tsx
import { AuthGuard } from "@/components/auth-guard";
import { ScheduleConsole } from "@/components/schedule/ScheduleConsole";

export const dynamic = "force-dynamic";

export default async function SchedulePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string>>;
}) {
  const params = await searchParams;
  const initialOpenSlotId = params.open_slot ?? null;
  return (
    <AuthGuard roles={["member", "admin"]}>
      <ScheduleConsole initialOpenSlotId={initialOpenSlotId} />
    </AuthGuard>
  );
}
```

- [ ] **Step 4: Update ScheduleConsole to accept and handle initialOpenSlotId**

In `apps/web/src/components/schedule/ScheduleConsole.tsx`, update the component signature:

```typescript
export function ScheduleConsole({ initialOpenSlotId = null }: { initialOpenSlotId?: string | null }) {
```

After the schedule is loaded (`setSchedule(data.slots)`), add an effect that auto-opens the panel:

```typescript
const initialOpenHandledRef = useRef(false);

useEffect(() => {
  if (!initialOpenSlotId || initialOpenHandledRef.current || schedule.length === 0) return;
  const slot = schedule.find((s) => s.id === initialOpenSlotId);
  if (slot) {
    setSelectedSlot(slot);
    initialOpenHandledRef.current = true;
  }
}, [initialOpenSlotId, schedule]);
```

Add the import: `import { useRef } from "react";` (if not already present).

- [ ] **Step 5: Update my-workouts/page.tsx to read open_assignment param**

In `apps/web/src/app/my-workouts/page.tsx`:

```tsx
import { AuthGuard } from "@/components/auth-guard";
import { AssignedWorkoutsConsole } from "@/components/workouts/AssignedWorkoutsConsole";

export const dynamic = "force-dynamic";

export default async function MyWorkoutsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string>>;
}) {
  const params = await searchParams;
  const initialOpenAssignmentId = params.open_assignment ?? null;
  return (
    <AuthGuard roles={["athlete", "admin"]}>
      <AssignedWorkoutsConsole initialOpenAssignmentId={initialOpenAssignmentId} />
    </AuthGuard>
  );
}
```

- [ ] **Step 6: Update AssignedWorkoutsConsole to auto-open panel**

Add prop to `AssignedWorkoutsConsole`:

```typescript
export function AssignedWorkoutsConsole({
  initialOpenAssignmentId = null,
}: {
  initialOpenAssignmentId?: string | null;
}) {
```

After assignments are loaded, auto-open the panel:

```typescript
const initialOpenHandledRef = useRef(false);

useEffect(() => {
  if (!initialOpenAssignmentId || initialOpenHandledRef.current || allAssignments.length === 0) return;
  const assignment = allAssignments.find((a) => a.id === initialOpenAssignmentId);
  if (assignment) {
    setPanelAssignment(assignment);
    initialOpenHandledRef.current = true;
  }
}, [initialOpenAssignmentId, allAssignments]);
```

- [ ] **Step 7: TypeScript check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | head -20
```

- [ ] **Step 8: Commit**

```bash
git add apps/api/lib/milos_training/application/publish_workout.ex \
        apps/api/lib/milos_training/application/delete_workout.ex \
        apps/web/src/app/schedule/page.tsx \
        apps/web/src/components/schedule/ScheduleConsole.tsx \
        apps/web/src/app/my-workouts/page.tsx \
        apps/web/src/components/workouts/AssignedWorkoutsConsole.tsx
git commit -m "feat: notification deep-links open the relevant panel on navigation (item 9)"
```

---

### Task 6: Differentiated workout_changed vs workout_deleted notifications (Item 12)

**Files:**
- Modify: `apps/api/lib/milos_training/application/publish_workout.ex`
- Modify: `apps/api/lib/milos_training/application/delete_workout.ex`
- Modify: `apps/web/src/components/notifications/NotificationBell.tsx`

- [ ] **Step 1: Add change_type to workout_changed payload**

In `apps/api/lib/milos_training/application/publish_workout.ex`:

In `notify_assignment_targets`, add `change_type: "sections_updated"` to the payload:

```elixir
payload = %{
  kind: "assigned_workout",
  assigned_workout_id: target.assigned_workout_id,
  scheduled_for: Date.to_iso8601(target.scheduled_for),
  change_type: "sections_updated",
  body:
    "Your coach updated the exercises for your workout on #{format_date(target.scheduled_for)}: #{workout.title}.",
  url: "/my-workouts?open_assignment=#{target.assigned_workout_id}"
}
```

In `notify_booking_targets`, add `change_type: "sections_updated"`:

```elixir
payload = %{
  kind: "scheduled_class",
  scheduled_class_id: Map.get(target, :scheduled_class_id),
  training_type: to_string(training_type || ""),
  change_type: "sections_updated",
  body:
    "Your coach updated the exercises for your #{format_training_type(training_type)} class: #{workout.title}.",
  url: "/schedule?open_slot=#{Map.get(target, :scheduled_class_id)}"
}
```

- [ ] **Step 2: Improve workout_deleted message clarity**

In `apps/api/lib/milos_training/application/delete_workout.ex`:

In `notify_assignment_targets`:
```elixir
body: "Your coach removed the workout scheduled for #{format_date(target.scheduled_for)}. This workout no longer exists.",
```

In `notify_booking_targets`:
```elixir
body: "Your coach removed the workout for your #{format_training_type(target.training_type)} class on #{format_datetime(target.scheduled_at)}. This class may be rescheduled.",
```

- [ ] **Step 3: Update NotificationBell to show specific messages**

In `apps/web/src/components/notifications/NotificationBell.tsx`:

Update the `workout_deleted` title:
```typescript
case "workout_deleted":
  return "Workout deleted by coach";
```

Update `notificationBody` for `workout_changed` to use `change_type`:

```typescript
if (notification.type === "workout_changed") {
  if (typeof notification.payload.body === "string") return notification.payload.body;
  const changeType = notification.payload.change_type;
  if (changeType === "datetime_changed") return "The scheduled time for this workout was changed.";
  if (changeType === "sections_updated") return "Your coach updated the exercises in this workout.";
  return "Your coach changed a scheduled workout.";
}
```

- [ ] **Step 4: Commit**

```bash
git add apps/api/lib/milos_training/application/publish_workout.ex \
        apps/api/lib/milos_training/application/delete_workout.ex \
        apps/web/src/components/notifications/NotificationBell.tsx
git commit -m "feat: differentiate workout_changed vs workout_deleted notification content (item 12)"
```

---

### Task 7: Push notifications auto-mark-read (Item 15)

**Files:**
- Modify: `apps/web/public/sw-push-notifications.js`

The service worker receives a push, shows a browser notification, and must mark the in-app notification as read. The backend push payload must include `notification_id` and the API token. Since the token can't be stored securely in the SW, we use a background fetch to the mark-read endpoint using the token stored in IndexedDB by the app.

- [ ] **Step 1: Store access token in IndexedDB from the app**

In `apps/web/src/hooks/usePushNotifications.ts` (or wherever the token is sent to the SW), add a helper that writes the access token to IndexedDB so the service worker can read it:

```typescript
async function storeTokenForSW(token: string) {
  const db = await openSwDb();
  const tx = db.transaction("config", "readwrite");
  tx.objectStore("config").put({ key: "access_token", value: token });
  await tx.done;
}

function openSwDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open("milos-sw", 1);
    req.onupgradeneeded = () => req.result.createObjectStore("config", { keyPath: "key" });
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}
```

Call `storeTokenForSW(token)` whenever the access token changes in `usePushNotifications`.

- [ ] **Step 2: Read token in service worker and mark notification read on push**

In `apps/web/public/sw-push-notifications.js`, update the `push` event handler:

```javascript
self.addEventListener("push", (event) => {
  const data = event.data?.json() ?? {};

  const notificationId = data.notification_id ?? null;
  const apiBase = self.location.origin;

  event.waitUntil(
    (async () => {
      await self.registration.showNotification(data.title ?? "Milos Training", {
        body: data.body ?? "",
        icon: "/globe.svg",
        badge: "/globe.svg",
        data: { url: data.url, notification_id: notificationId },
      });

      if (notificationId) {
        const token = await readTokenFromDb();
        if (token) {
          await fetch(`${apiBase}/api/notifications/${notificationId}/read`, {
            method: "PATCH",
            headers: { Authorization: `Bearer ${token}` },
          }).catch(() => {});
        }
      }
    })(),
  );
});

async function readTokenFromDb() {
  return new Promise((resolve) => {
    const req = indexedDB.open("milos-sw", 1);
    req.onupgradeneeded = () => req.result.createObjectStore("config", { keyPath: "key" });
    req.onsuccess = () => {
      const tx = req.result.transaction("config", "readonly");
      const get = tx.objectStore("config").get("access_token");
      get.onsuccess = () => resolve(get.result?.value ?? null);
      get.onerror = () => resolve(null);
    };
    req.onerror = () => resolve(null);
  });
}
```

- [ ] **Step 3: Ensure notification_id is in the push payload from backend**

In `apps/api/lib/milos_training/notifications.ex`, find the push delivery function (likely `deliver_push_notification` or similar). Add `notification_id` to the push payload map sent to the push service.

Grep for the function:
```bash
grep -n "deliver_push\|push_payload\|web_push\|Pigeon\|WebPush" apps/api/lib/milos_training/notifications.ex | head -10
```

Add `notification_id: notification.id` to whatever map is sent as the push body.

- [ ] **Step 4: Commit**

```bash
git add apps/web/public/sw-push-notifications.js \
        apps/web/src/hooks/usePushNotifications.ts \
        apps/api/lib/milos_training/notifications.ex
git commit -m "feat: auto-mark notification as read when delivered via browser push (item 15)"
```

---

## Cluster 4 — Workout Edit & Drafts

### Task 8: Orphan draft cleanup on publish (Item 14)

**Root cause:** When admin reopens a published workout, `reopenWorkout` creates a new draft with a new ID. The original published record stays published. If admin publishes the new draft, both records exist. The new draft's publish changes its own status to `published`, but the original record also remains. We clean up by deleting any draft records that were created as a reopen of this workout.

**Files:**
- Modify: `apps/api/lib/milos_training/application/publish_workout.ex`
- Modify: `apps/api/lib/milos_training/workouts.ex`
- Modify: `apps/api/lib/milos_training/workouts/ports/workout_store.ex`
- Modify: `apps/api/lib/milos_training/infrastructure/workouts/ecto_workout_store.ex`

- [ ] **Step 1: Check reopen_workout to understand draft lineage**

```bash
cat apps/api/lib/milos_training/application/reopen_workout.ex
```

Identify the field that links a draft back to its source (e.g. `reopened_from_id` or similar). If no such field exists, we track by `inserted_by` + `status = 'draft'` — clean all OTHER drafts for the same admin after publish.

- [ ] **Step 2: Add cleanup to publish_workout.ex**

In `apps/api/lib/milos_training/application/publish_workout.ex`, after the `with` block succeeds:

```elixir
with {:ok, workout} <- Workouts.publish_workout(id, params),
     :ok <- apply_substitution(substitute_for, workout.id) do
  Workouts.delete_superseded_drafts(id, workout.inserted_by_id)
  maybe_notify(is_republish, substitute_for, assignment_targets, booking_targets, workout)
  {:ok, workout}
end
```

- [ ] **Step 3: Add delete_superseded_drafts to Workouts context**

In `apps/api/lib/milos_training/workouts.ex`:

```elixir
defdelegate delete_superseded_drafts(published_id, admin_id), to: WorkoutStore
```

In `apps/api/lib/milos_training/workouts/ports/workout_store.ex`:

```elixir
@callback delete_superseded_drafts(String.t(), String.t()) :: :ok
```

In `apps/api/lib/milos_training/infrastructure/workouts/ecto_workout_store.ex`:

```elixir
@impl true
def delete_superseded_drafts(published_id, admin_id) do
  MasterWorkout
  |> where([w], w.status == :draft and w.inserted_by_id == ^admin_id and w.id != ^published_id)
  |> Repo.delete_all()

  :ok
end
```

- [ ] **Step 4: Run backend tests**

```bash
cd apps/api && mix test 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add apps/api/lib/milos_training/application/publish_workout.ex \
        apps/api/lib/milos_training/workouts.ex \
        apps/api/lib/milos_training/workouts/ports/workout_store.ex \
        apps/api/lib/milos_training/infrastructure/workouts/ecto_workout_store.ex
git commit -m "fix: hard-delete orphan drafts when a workout is published (item 14)"
```

---

## Cluster 5 — UI & Roles

### Task 9: New admin routes + TopNav role-aware links (Item 16)

**Files:**
- Create: `apps/web/src/app/admin/class-schedule/page.tsx`
- Create: `apps/web/src/app/admin/coaching-assignments/page.tsx`
- Modify: `apps/web/src/components/TopNav.tsx`
- Modify: `apps/web/src/components/schedule/ScheduleConsole.tsx` (page title prop)
- Modify: `apps/web/src/components/workouts/AssignedWorkoutsConsole.tsx` (page title prop)

- [ ] **Step 1: Create admin/class-schedule page**

```tsx
// apps/web/src/app/admin/class-schedule/page.tsx
import { AuthGuard } from "@/components/auth-guard";
import { ScheduleConsole } from "@/components/schedule/ScheduleConsole";

export const dynamic = "force-dynamic";

export default async function AdminClassSchedulePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string>>;
}) {
  const params = await searchParams;
  const initialOpenSlotId = params.open_slot ?? null;
  return (
    <AuthGuard roles={["admin"]}>
      <ScheduleConsole pageTitle="Class Schedule" initialOpenSlotId={initialOpenSlotId} />
    </AuthGuard>
  );
}
```

- [ ] **Step 2: Create admin/coaching-assignments page**

```tsx
// apps/web/src/app/admin/coaching-assignments/page.tsx
import { AuthGuard } from "@/components/auth-guard";
import { AssignedWorkoutsConsole } from "@/components/workouts/AssignedWorkoutsConsole";

export const dynamic = "force-dynamic";

export default async function AdminCoachingAssignmentsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string>>;
}) {
  const params = await searchParams;
  const initialOpenAssignmentId = params.open_assignment ?? null;
  return (
    <AuthGuard roles={["admin"]}>
      <AssignedWorkoutsConsole
        pageTitle="Coaching Assignments"
        initialOpenAssignmentId={initialOpenAssignmentId}
      />
    </AuthGuard>
  );
}
```

- [ ] **Step 3: Update TopNav links**

In `apps/web/src/components/TopNav.tsx`, update `NAV_LINKS`:

```typescript
const NAV_LINKS: Array<{ href: string; label: string; roles: UserRole[] }> = [
  { href: "/schedule",                    label: "Schedule",              roles: ["member"] },
  { href: "/admin/class-schedule",        label: "Class Schedule",        roles: ["admin"] },
  { href: "/my-workouts",                 label: "My Workouts",           roles: ["athlete"] },
  { href: "/admin/coaching-assignments",  label: "Coaching Assignments",  roles: ["admin"] },
  { href: "/admin/workouts",              label: "Admin",                 roles: ["admin"] },
];
```

Update `pathActive` to handle the new admin paths:

```typescript
function pathActive(pathname: string, href: string) {
  if (href === "/admin/workouts") {
    return pathname.startsWith("/admin/workouts");
  }
  return pathname.startsWith(href);
}
```

- [ ] **Step 4: Add pageTitle prop to ScheduleConsole and AssignedWorkoutsConsole**

In `ScheduleConsole`, update signature:

```typescript
export function ScheduleConsole({
  pageTitle = "Schedule",
  initialOpenSlotId = null,
}: {
  pageTitle?: string;
  initialOpenSlotId?: string | null;
}) {
```

Find the heading render (look for `<h1>` or main title) and replace with `{pageTitle}`.

In `AssignedWorkoutsConsole`, update signature:

```typescript
export function AssignedWorkoutsConsole({
  pageTitle = "My Workouts",
  initialOpenAssignmentId = null,
}: {
  pageTitle?: string;
  initialOpenAssignmentId?: string | null;
}) {
```

Find the heading render and replace with `{pageTitle}`.

- [ ] **Step 5: TypeScript check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | head -20
```

- [ ] **Step 6: Commit**

```bash
git add apps/web/src/app/admin/class-schedule/page.tsx \
        apps/web/src/app/admin/coaching-assignments/page.tsx \
        apps/web/src/components/TopNav.tsx \
        apps/web/src/components/schedule/ScheduleConsole.tsx \
        apps/web/src/components/workouts/AssignedWorkoutsConsole.tsx
git commit -m "feat: add admin-specific routes with role-aware TopNav labels (item 16)"
```

---

### Task 10: Login default tab fix (Item 17)

**Files:**
- Modify: `apps/web/src/components/auth-console.tsx`

- [ ] **Step 1: Change default mode to login**

In `apps/web/src/components/auth-console.tsx`, find:

```typescript
const [mode, setMode] = useState<Mode>("register");
```

Change to:

```typescript
const [mode, setMode] = useState<Mode>("login");
```

- [ ] **Step 2: Commit**

```bash
git add apps/web/src/components/auth-console.tsx
git commit -m "fix: default login page to Login tab instead of Register (item 17)"
```

---

### Task 11: InfoModal component + gamification help icons (Item 17)

**Files:**
- Create: `apps/web/src/components/InfoModal.tsx`
- Modify: `apps/web/src/components/landing-page.tsx`

- [ ] **Step 1: Create InfoModal component**

```tsx
// apps/web/src/components/InfoModal.tsx
"use client";

import { useEffect, useRef } from "react";

type InfoModalProps = {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
};

export function InfoModal({ title, onClose, children }: InfoModalProps) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    ref.current?.focus();
  }, []);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: "rgba(0,0,0,0.65)" }}
      onClick={onClose}
      role="presentation"
    >
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        className="w-full max-w-md rounded-[2rem] p-6 outline-none"
        style={{ background: "#111118", border: "1px solid #1a1a28" }}
        tabIndex={-1}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-4">
          <h2 className="text-lg font-bold" style={{ color: "#F0EDF8" }}>{title}</h2>
          <button
            className="shrink-0 rounded-full px-3 py-1 text-xs font-semibold"
            style={{ background: "#1a1a28", color: "#8888aa" }}
            onClick={onClose}
            type="button"
          >
            Close ✕
          </button>
        </div>
        <div className="mt-4 space-y-3 text-sm leading-6" style={{ color: "#8888aa" }}>
          {children}
        </div>
      </div>
    </div>
  );
}

type HelpIconProps = {
  tooltip: string;
  onClick: () => void;
};

export function HelpIcon({ tooltip, onClick }: HelpIconProps) {
  return (
    <button
      className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[10px] font-bold transition-colors hover:opacity-80"
      style={{ background: "#1a1a28", color: "#55556a", border: "1px solid #2a2a3a" }}
      title={tooltip}
      onClick={onClick}
      type="button"
      aria-label={`Info: ${tooltip}`}
    >
      ?
    </button>
  );
}
```

- [ ] **Step 2: Add help icons to gamification cards in landing-page.tsx**

In `apps/web/src/components/landing-page.tsx`, add imports:

```typescript
import { HelpIcon, InfoModal } from "@/components/InfoModal";
```

Add state for which modal is open:

```typescript
const [activeInfoModal, setActiveInfoModal] = useState<string | null>(null);
```

For each gamification card (streaks, leaderboard entry, volume, challenges), add a `HelpIcon` in the card header and an `InfoModal` that renders when `activeInfoModal === "streak"` (etc).

Example for a streak card:

```tsx
{/* Streak card header */}
<div className="flex items-center justify-between gap-2">
  <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "#55556a" }}>
    Current Streak
  </p>
  <HelpIcon
    tooltip="What is a streak?"
    onClick={() => setActiveInfoModal("streak")}
  />
</div>

{/* Modal */}
{activeInfoModal === "streak" ? (
  <InfoModal title="Current Streak" onClose={() => setActiveInfoModal(null)}>
    <p><strong style={{ color: "#F0EDF8" }}>What it measures:</strong> The number of consecutive days you completed at least one workout.</p>
    <p><strong style={{ color: "#F0EDF8" }}>How to improve:</strong> Complete a workout every day. Missing a day resets the streak to zero.</p>
    <p><strong style={{ color: "#F0EDF8" }}>Why it matters:</strong> Streaks build the habit of daily movement — even a short recovery session counts.</p>
  </InfoModal>
) : null}
```

Repeat for each gamification element, with tailored info content.

- [ ] **Step 3: Make gamification colours more vibrant**

In `landing-page.tsx`, for streak/challenge/volume elements that currently use muted colours, update to:
- Streak: `#d9ab4e` (gold)
- Challenges/badges: `#d95d39` (accent orange) or `#9c799c` (purple)
- Volume/progress bars: `#4db89c` (teal-green)

Find the existing colour values and update them to these more vibrant alternatives.

- [ ] **Step 4: TypeScript check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | head -20
```

- [ ] **Step 5: Commit**

```bash
git add apps/web/src/components/InfoModal.tsx \
        apps/web/src/components/landing-page.tsx
git commit -m "feat: gamification help icons with InfoModal + vibrant colours (item 17)"
```

---

### Task 12: UI style audit — landing page and auth console (Item 17)

**Files:**
- Modify: `apps/web/src/components/landing-page.tsx`
- Modify: `apps/web/src/components/auth-console.tsx`

- [ ] **Step 1: Audit auth-console against design system**

In `apps/web/src/components/auth-console.tsx`:
- Background: change any white/light backgrounds to `#0A0A0F`
- Card surfaces: `#111118` with `border: "1px solid #1a1a28"`
- Primary text: `#F0EDF8`
- Secondary text: `#8888aa`
- Accent / active tab: `#d95d39`
- Input fields: `background: "#111118", border: "1px solid #1e1e2e", color: "#F0EDF8"`

Check the tab toggle (Register/Login) and apply:
- Active tab: `background: "#d95d39", color: "#fff"`
- Inactive tab: `background: "transparent", color: "#55556a"`

- [ ] **Step 2: Audit landing-page top-level containers**

In `apps/web/src/components/landing-page.tsx`:
- Ensure the outermost container has `background: "#0A0A0F"` or inherits from layout
- All card wrappers: `background: "#111118"` or `#0d0d18`, `border: "1px solid #1a1a28"`

- [ ] **Step 3: Commit**

```bash
git add apps/web/src/components/auth-console.tsx \
        apps/web/src/components/landing-page.tsx
git commit -m "fix: align landing page and auth console with dark design system (item 17)"
```

---

## Post-implementation verification

- [ ] **Backend full test run**

```bash
cd apps/api && mix test 2>&1 | tail -10
```

Expected: 0 failures.

- [ ] **Backend static analysis**

```bash
cd apps/api && mix credo --strict 2>&1 | tail -20
```

Fix any issues introduced by the changes.

- [ ] **Backend format**

```bash
cd apps/api && mix format
```

Commit any formatting changes.

- [ ] **Frontend TypeScript**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | head -30
```

Expected: 0 errors.

- [ ] **Final commit if format-only changes remain**

```bash
git add -p && git commit -m "chore: mix format and tsc cleanup"
```
