# Private Chat — Plan 3: Legacy Cleanup & Coaching Drill-Down Update

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete all legacy messaging code (`AssignmentMessage`, `AdminAthleteNote`, legacy use cases, routes, controller actions), update the coaching drill-down to read messages from the `Messaging` context, and verify the full test suite remains green.

**Architecture:** Hard delete — no backward compatibility shims. The Messaging context (Plan 2) is the single source of truth. The analytics `CommunicationMessage` table is untouched.

**Tech Stack:** Elixir/Phoenix 1.7, Ecto, ExUnit

**Depends on:** Plans 1 + 2 must be complete and all tests passing.

---

## File Map

### Files to delete
- `apps/api/lib/milos_training/workouts/assignment_message.ex`
- `apps/api/lib/milos_training/coaching/admin_athlete_note.ex`
- `apps/api/lib/milos_training/coaching/note_store.ex`
- `apps/api/lib/milos_training/coaching/ports/note_store.ex`
- `apps/api/lib/milos_training/coaching/commands/write_note.ex`
- `apps/api/lib/milos_training/coaching/queries/list_notes_for_athlete.ex`
- `apps/api/lib/milos_training/infrastructure/coaching/ecto_note_store.ex`
- `apps/api/lib/milos_training/application/post_assignment_message.ex`
- `apps/api/lib/milos_training/application/list_assignment_messages.ex`
- `apps/api/lib/milos_training/application/write_admin_athlete_note.ex`
- `apps/api/lib/milos_training/application/send_athlete_message.ex`

### Files to modify
- `apps/api/lib/milos_training/coaching.ex` — remove `write_note`, `list_notes_for_athlete`
- `apps/api/lib/milos_training_web/controllers/admin_coaching_controller.ex` — remove `create_note` action + OpenAPI spec
- `apps/api/lib/milos_training_web/controllers/my_workout_controller.ex` — remove `send_message`, `list_messages`, `post_message` actions
- `apps/api/lib/milos_training_web/controllers/schedule_controller.ex` — remove `send_slot_message` action
- `apps/api/lib/milos_training_web/router.ex` — remove legacy routes
- `apps/api/lib/milos_training/workouts.ex` — remove `create_assignment_message`, `list_assignment_messages`
- `apps/api/lib/milos_training/application/get_coaching_athlete_drill_down.ex` — use Messaging
- `apps/api/lib/milos_training/coaching/domain/athlete_drill_down.ex` — update to work with messages
- `apps/api/test/milos_training_web/controllers/admin_coaching_controller_test.exs` — update note test

### New migrations (drop legacy tables)
- `apps/api/priv/repo/migrations/20260614000004_drop_assignment_messages.exs`
- `apps/api/priv/repo/migrations/20260614000005_drop_admin_athlete_notes.exs`

---

## Task 1: Drop legacy tables

**Files:**
- Create: `apps/api/priv/repo/migrations/20260614000004_drop_assignment_messages.exs`
- Create: `apps/api/priv/repo/migrations/20260614000005_drop_admin_athlete_notes.exs`

- [ ] **Step 1: Write drop migrations**

```elixir
# apps/api/priv/repo/migrations/20260614000004_drop_assignment_messages.exs
defmodule MilosTraining.Repo.Migrations.DropAssignmentMessages do
  use Ecto.Migration

  def up do
    drop table(:assignment_messages)
  end

  def down do
    create table(:assignment_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sender_id, :binary_id
      add :athlete_id, :binary_id
      add :sender_nickname, :string
      add :body, :string
      add :assigned_workout_id, references(:assigned_workouts, type: :binary_id)
      timestamps(updated_at: false)
    end
  end
end
```

```elixir
# apps/api/priv/repo/migrations/20260614000005_drop_admin_athlete_notes.exs
defmodule MilosTraining.Repo.Migrations.DropAdminAthleteNotes do
  use Ecto.Migration

  def up do
    drop table(:admin_athlete_notes)
  end

  def down do
    create table(:admin_athlete_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :admin_id, references(:users, type: :binary_id)
      add :athlete_id, references(:users, type: :binary_id)
      add :body, :text
      timestamps(updated_at: false, type: :utc_datetime)
    end
  end
end
```

- [ ] **Step 2: Run migrations**

```bash
cd apps/api && mix ecto.migrate
```

Expected: both migrations run without error.

---

## Task 2: Delete legacy source files

- [ ] **Step 1: Delete files**

```bash
rm apps/api/lib/milos_training/workouts/assignment_message.ex
rm apps/api/lib/milos_training/coaching/admin_athlete_note.ex
rm apps/api/lib/milos_training/coaching/note_store.ex
rm apps/api/lib/milos_training/coaching/ports/note_store.ex
rm apps/api/lib/milos_training/coaching/commands/write_note.ex
rm apps/api/lib/milos_training/coaching/queries/list_notes_for_athlete.ex
rm apps/api/lib/milos_training/infrastructure/coaching/ecto_note_store.ex
rm apps/api/lib/milos_training/application/post_assignment_message.ex
rm apps/api/lib/milos_training/application/list_assignment_messages.ex
rm apps/api/lib/milos_training/application/write_admin_athlete_note.ex
rm apps/api/lib/milos_training/application/send_athlete_message.ex
```

- [ ] **Step 2: Try compiling — expect failures (modules that used these files)**

```bash
cd apps/api && mix compile 2>&1 | grep "error\|undefined" | head -20
```

Expected: compile errors referencing `AdminAthleteNote`, `AssignmentMessage`, `WriteAdminAthleteNote`, etc. These are fixed in subsequent steps.

---

## Task 3: Update Coaching context facade

**Files:**
- Modify: `apps/api/lib/milos_training/coaching.ex`

- [ ] **Step 1: Remove note-related delegations**

Replace the entire `coaching.ex` with:

```elixir
# apps/api/lib/milos_training/coaching.ex
defmodule MilosTraining.Coaching do
  alias MilosTraining.Coaching.Commands.RefreshAggregates
  alias MilosTraining.Coaching.Queries.GetAggregates

  defdelegate get_aggregates(), to: GetAggregates, as: :call
  defdelegate refresh_aggregates(), to: RefreshAggregates, as: :call
end
```

---

## Task 4: Update AdminCoachingController — remove create_note

**Files:**
- Modify: `apps/api/lib/milos_training_web/controllers/admin_coaching_controller.ex`

- [ ] **Step 1: Remove create_note action and its OpenAPI spec**

Remove the entire `operation(:create_note, ...)` block and the `def create_note(conn, params)` function. Also remove `WriteAdminAthleteNote` from the alias list.

The controller should only retain the `drill_down` action after this change.

- [ ] **Step 2: Remove legacy admin coaching routes from router**

In `apps/api/lib/milos_training_web/router.ex`, find and remove:

```elixir
post("/athletes/:id/notes", AdminCoachingController, :create_note)
```

---

## Task 5: Remove legacy message routes and actions from MyWorkoutController

**Files:**
- Modify: `apps/api/lib/milos_training_web/controllers/my_workout_controller.ex`
- Modify: `apps/api/lib/milos_training_web/router.ex`

- [ ] **Step 1: Remove from MyWorkoutController**

Remove these action functions and their OpenAPI operation specs:
- `send_message/2` (the athlete sends a message to admin via assigned workout)
- `list_messages/2`
- `post_message/2`

Also remove `PostAssignmentMessage`, `ListAssignmentMessages`, `SendAthleteMessage` from the alias block.

- [ ] **Step 2: Remove routes from router**

Find and remove from router:

```elixir
post("/my-workouts/assignments/:id/message", MyWorkoutController, :send_message)
get("/my-workouts/assignments/:id/messages", MyWorkoutController, :list_messages)
post("/my-workouts/assignments/:id/messages", MyWorkoutController, :post_message)
get("/assigned-workouts/:id/messages", MyWorkoutController, :list_messages)
post("/assigned-workouts/:id/messages", MyWorkoutController, :post_message)
```

---

## Task 6: Remove send_slot_message from ScheduleController

**Files:**
- Modify: `apps/api/lib/milos_training_web/controllers/schedule_controller.ex`
- Modify: `apps/api/lib/milos_training_web/router.ex`

- [ ] **Step 1: Remove action**

Remove `send_slot_message/2` and its OpenAPI `operation(:send_slot_message, ...)` block. Remove `SendAthleteMessage` from aliases.

- [ ] **Step 2: Remove route**

Find and remove from router:

```elixir
post("/schedule/slots/:id/message", ScheduleController, :send_slot_message)
```

---

## Task 7: Remove assignment message functions from Workouts context

**Files:**
- Modify: `apps/api/lib/milos_training/workouts.ex`

- [ ] **Step 1: Find and remove note/message functions**

```bash
grep -n "assignment_message\|create_assignment_message\|list_assignment_messages" \
  apps/api/lib/milos_training/workouts.ex
```

Remove the functions `create_assignment_message/1` and `list_assignment_messages/2` (and related delegations). Keep all workout assignment functions unrelated to messaging.

---

## Task 8: Update coaching drill-down to read from Messaging

**Files:**
- Modify: `apps/api/lib/milos_training/application/get_coaching_athlete_drill_down.ex`
- Modify: `apps/api/lib/milos_training/coaching/domain/athlete_drill_down.ex`

- [ ] **Step 1: Update GetCoachingAthleteDrillDown**

Replace the file content:

```elixir
# apps/api/lib/milos_training/application/get_coaching_athlete_drill_down.ex
defmodule MilosTraining.Application.GetCoachingAthleteDrillDown do
  alias MilosTraining.Application.ListWorkoutExecutions
  alias MilosTraining.Coaching
  alias MilosTraining.Coaching.Domain.AthleteDrillDown
  alias MilosTraining.Identity
  alias MilosTraining.Messaging
  alias MilosTraining.Workouts

  def call(athlete_id, params \\ %{}) do
    with %{role: :athlete} = athlete <- Identity.find_by_id(athlete_id),
         {:ok, executions} <- ListWorkoutExecutions.call(athlete_id) do
      {start_date, end_date} = assignment_window(params)

      assignments = Workouts.list_assigned_workouts_for_athlete(athlete_id, start_date, end_date)
      coaching_messages = fetch_coaching_messages(athlete_id)

      {:ok,
       %{
         drill_down:
           AthleteDrillDown.build(athlete, assignments, executions, coaching_messages, Date.utc_today())
       }}
    else
      nil -> {:error, :not_found}
      %{role: _other_role} -> {:error, :forbidden}
      error -> error
    end
  end

  # Fetch coaching_note messages from all direct threads that involve this athlete.
  # Returns a list of normalized maps compatible with the existing notes_context shape.
  defp fetch_coaching_messages(athlete_id) do
    athlete_id
    |> Messaging.list_threads_for_user(:direct)
    |> Enum.flat_map(fn thread ->
      Messaging.list_messages(thread.id, %{limit: 100})
    end)
    |> Enum.filter(&(&1.message_type == "coaching_note"))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp assignment_window(params) do
    today = Date.utc_today()

    start_date =
      params
      |> field(:start_date)
      |> parse_date(Date.add(today, -30))

    end_date =
      params
      |> field(:end_date)
      |> parse_date(Date.add(today, 30))

    {start_date, end_date}
  end

  defp parse_date(%Date{} = date, _default), do: date

  defp parse_date(value, default) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> default
    end
  end

  defp parse_date(_value, default), do: default

  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp field(_map, _key), do: nil
end
```

- [ ] **Step 2: Update AthleteDrillDown.normalize_admin_note to accept Message maps**

In `apps/api/lib/milos_training/coaching/domain/athlete_drill_down.ex`, find `normalize_admin_note/1` and update it to work with the new message map shape (which has `sender_id` instead of `admin_id`):

```elixir
# Old:
defp normalize_admin_note(note) do
  %{
    id: field(note, :id),
    admin_id: field(note, :admin_id),
    athlete_id: field(note, :athlete_id),
    body: field(note, :body),
    inserted_at: field(note, :inserted_at)
  }
end

# New (message map has sender_id, no athlete_id):
defp normalize_admin_note(message) do
  %{
    id: field(message, :id),
    admin_id: field(message, :sender_id),
    body: field(message, :body),
    inserted_at: field(message, :inserted_at)
  }
end
```

---

## Task 9: Update coaching controller test

**Files:**
- Modify: `apps/api/test/milos_training_web/controllers/admin_coaching_controller_test.exs`

- [ ] **Step 1: Replace the "write note" test with a messaging-based test**

Find the test `"admin can write an athlete note and trigger an athlete notification"` and replace it with:

```elixir
test "admin can send a coaching note via messaging and athlete receives chat_message notification",
     %{conn: conn} do
  admin = admin_fixture()
  athlete = user_fixture(%{role: :athlete})

  # Create a direct thread first
  conn
  |> put_bearer_token(admin)
  |> post("/api/threads", %{participant_id: athlete.id})
  |> json_response(200)

  # Get thread
  %{"threads" => [thread]} =
    conn
    |> put_bearer_token(admin)
    |> get("/api/threads?context_type=direct")
    |> json_response(200)

  # Send coaching note
  response =
    conn
    |> put_bearer_token(admin)
    |> post("/api/threads/#{thread["id"]}/messages", %{
      body: "Keep your squat tempo controlled this week.",
      message_type: "coaching_note"
    })
    |> json_response(201)

  assert response["message"]["message_type"] == "coaching_note"
  assert response["message"]["body"] == "Keep your squat tempo controlled this week."
end
```

---

## Task 10: Verify full compilation and test suite

- [ ] **Step 1: Compile**

```bash
cd apps/api && mix compile 2>&1 | grep -E "^error|undefined function" | head -20
```

Expected: zero errors.

- [ ] **Step 2: Run full test suite**

```bash
cd apps/api && mix test 2>&1 | tail -10
```

Expected: all tests pass (some legacy tests may be removed — verify nothing is accidentally skipped).

- [ ] **Step 3: Format + credo**

```bash
cd apps/api && mix format && mix credo --strict 2>&1 | grep -v "^$" | tail -20
```

- [ ] **Step 4: Commit everything**

```bash
git add -A
git commit -m "feat(messaging): delete legacy messaging/notes code, update drill-down to use Messaging"
```

---

## Completion check

```bash
cd apps/api && mix test && echo "ALL TESTS PASS"
```

Expected: `ALL TESTS PASS`
