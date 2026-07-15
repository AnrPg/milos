# Gamification & Workout Improvements — Backend Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the backend (migrations, domain, infrastructure, application, API) for gamification metrics redesign, Pantheon PR system, workout modification tracking, coach notes on workouts, and off-days preferences.

**Architecture:** Hexagonal (ports & adapters) with 4 layers: Interface → Application → Domain → Infrastructure. All domain logic is pure functions. Cross-context communication via application services only. New Pantheon bounded context follows the identical pattern as Gamification.

**Tech Stack:** Elixir / Phoenix 1.7+, Ecto, PostgreSQL 16, Meilisearch (via Req), Oban (background jobs), ExUnit for tests.

---

## File Map

**New files:**
- `priv/repo/migrations/20260616000001_add_gamification_preferences_and_user_stats_fields.exs`
- `priv/repo/migrations/20260616000002_create_user_pr_records_and_history.exs`
- `priv/repo/migrations/20260616000003_add_exercise_modifications_and_notes.exs`
- `lib/milos_training/gamification/user_gamification_preferences.ex`
- `lib/milos_training/gamification/domain/day_streak_calculator.ex`
- `lib/milos_training/gamification/domain/motivation_calculator.ex`
- `lib/milos_training/gamification/domain/perseverance_calculator.ex`
- `lib/milos_training/pantheon/pr_record.ex`
- `lib/milos_training/pantheon/pr_history.ex`
- `lib/milos_training/pantheon/ports/pr_store.ex`
- `lib/milos_training/pantheon/pr_store.ex`
- `lib/milos_training/pantheon.ex`
- `lib/milos_training/infrastructure/pantheon/ecto_pr_store.ex`
- `lib/milos_training/infrastructure/search/meilisearch_pr_index.ex`
- `lib/milos_training/application/get_gamification_preferences.ex`
- `lib/milos_training/application/update_gamification_preferences.ex`
- `lib/milos_training/application/create_pr.ex`
- `lib/milos_training/application/update_pr.ex`
- `lib/milos_training/application/delete_pr.ex`
- `lib/milos_training/application/list_user_prs.ex`
- `lib/milos_training/application/get_pr_history.ex`
- `lib/milos_training/application/share_pr.ex`
- `lib/milos_training/application/add_execution_modifications.ex`
- `lib/milos_training_web/controllers/gamification_preferences_controller.ex`
- `lib/milos_training_web/controllers/pr_controller.ex`
- `lib/milos_training_web/controllers/execution_modifications_controller.ex`
- `test/milos_training/gamification/domain/day_streak_calculator_test.exs`
- `test/milos_training/gamification/domain/motivation_calculator_test.exs`
- `test/milos_training/gamification/domain/perseverance_calculator_test.exs`

**Modified files:**
- `lib/milos_training/gamification/user_stat.ex` — add new fields
- `lib/milos_training/gamification/ports/gamification_store.ex` — add preferences callbacks
- `lib/milos_training/gamification/gamification_store.ex` — delegate new callbacks
- `lib/milos_training/infrastructure/gamification/ecto_gamification_store.ex` — implement preferences
- `lib/milos_training/gamification/commands/record_workout_completion.ex` — use new calculators
- `lib/milos_training/gamification.ex` — add preferences + visibility delegates
- `lib/milos_training/application/get_landing_page.ex` — include preferences + new stats
- `lib/milos_training/workouts/workout_section.ex` — add note field
- `lib/milos_training/workouts/workout_exercise.ex` — add note field
- `lib/milos_training/execution/workout_execution.ex` — add exercise_modifications field
- `lib/milos_training_web/router.ex` — new routes

---

## Task 1: Migrations

**Files:**
- Create: `apps/api/priv/repo/migrations/20260616000001_add_gamification_preferences_and_user_stats_fields.exs`
- Create: `apps/api/priv/repo/migrations/20260616000002_create_user_pr_records_and_history.exs`
- Create: `apps/api/priv/repo/migrations/20260616000003_add_exercise_modifications_and_notes.exs`

- [ ] **Step 1: Create migration 1 — gamification preferences + user_stats new fields**

```elixir
# apps/api/priv/repo/migrations/20260616000001_add_gamification_preferences_and_user_stats_fields.exs
defmodule MilosTraining.Repo.Migrations.AddGamificationPreferencesAndUserStatsFields do
  use Ecto.Migration

  def change do
    create table(:user_gamification_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :off_days, {:array, :integer}, default: [], null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_gamification_preferences, [:user_id])

    alter table(:user_stats) do
      add :motivation_score, :float, default: 0.0, null: false
      add :perseverance_score, :float, default: 0.0, null: false
      add :advancement_count, :integer, default: 0, null: false
    end

    # current_streak and longest_streak change meaning from weeks to days.
    # Zero out existing values since the semantic has changed.
    execute "UPDATE user_stats SET current_streak = 0, longest_streak = 0"
  end
end
```

- [ ] **Step 2: Create migration 2 — Pantheon tables**

```elixir
# apps/api/priv/repo/migrations/20260616000002_create_user_pr_records_and_history.exs
defmodule MilosTraining.Repo.Migrations.CreateUserPrRecordsAndHistory do
  use Ecto.Migration

  def change do
    create table(:user_pr_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :current_score, :float, null: false
      add :unit, :string, null: false
      add :higher_is_better, :boolean, default: true, null: false
      add :beaten_on, :date, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:user_pr_records, [:user_id])
    create index(:user_pr_records, [:user_id, :beaten_on])

    create table(:user_pr_history, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :pr_record_id,
          references(:user_pr_records, type: :binary_id, on_delete: :delete_all),
          null: false

      add :score, :float, null: false
      add :beaten_on, :date, null: false

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:user_pr_history, [:pr_record_id])
    create index(:user_pr_history, [:pr_record_id, :beaten_on])
  end
end
```

- [ ] **Step 3: Create migration 3 — exercise_modifications + workout notes**

```elixir
# apps/api/priv/repo/migrations/20260616000003_add_exercise_modifications_and_notes.exs
defmodule MilosTraining.Repo.Migrations.AddExerciseModificationsAndNotes do
  use Ecto.Migration

  def change do
    alter table(:workout_executions) do
      add :exercise_modifications, {:array, :map}, default: [], null: false
    end

    alter table(:master_workout_sections) do
      add :note, :text
    end

    alter table(:workout_exercises) do
      add :note, :text
    end
  end
end
```

- [ ] **Step 4: Run migrations and verify**

```bash
cd apps/api && mix ecto.migrate
```

Expected: 3 migrations run successfully. No errors.

```bash
mix ecto.reset && mix ecto.migrate
```

Expected: Clean reset also succeeds.

- [ ] **Step 5: Commit**

```bash
git add apps/api/priv/repo/migrations/
git commit -m "feat(db): add gamification preferences, pantheon tables, exercise modifications, workout notes"
```

---

## Task 2: Update Schemas

**Files:**
- Modify: `apps/api/lib/milos_training/gamification/user_stat.ex`
- Modify: `apps/api/lib/milos_training/workouts/workout_section.ex`
- Modify: `apps/api/lib/milos_training/workouts/workout_exercise.ex`
- Modify: `apps/api/lib/milos_training/execution/workout_execution.ex`
- Create: `apps/api/lib/milos_training/gamification/user_gamification_preferences.ex`

- [ ] **Step 1: Update `UserStat` schema — add new fields**

In `apps/api/lib/milos_training/gamification/user_stat.ex`, add to `schema "user_stats"` block:

```elixir
field :motivation_score, :float, default: 0.0
field :perseverance_score, :float, default: 0.0
field :advancement_count, :integer, default: 0
```

And add to `cast/2` and `validate_required/2` lists:
- Cast: `:motivation_score`, `:perseverance_score`, `:advancement_count`
- Validate required: `:motivation_score`, `:perseverance_score`, `:advancement_count`
- Add: `|> validate_number(:motivation_score, greater_than_or_equal_to: 0.0)`
- Add: `|> validate_number(:perseverance_score, greater_than_or_equal_to: 0.0)`
- Add: `|> validate_number(:advancement_count, greater_than_or_equal_to: 0)`

- [ ] **Step 2: Create `UserGamificationPreferences` schema**

```elixir
# apps/api/lib/milos_training/gamification/user_gamification_preferences.ex
defmodule MilosTraining.Gamification.UserGamificationPreferences do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_days Enum.to_list(0..6)

  schema "user_gamification_preferences" do
    field :user_id, :binary_id
    field :off_days, {:array, :integer}, default: []

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(prefs \\ %__MODULE__{}, params) do
    prefs
    |> cast(params, [:user_id, :off_days])
    |> validate_required([:user_id, :off_days])
    |> validate_off_days()
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_off_days(changeset) do
    changeset
    |> validate_change(:off_days, fn :off_days, days ->
      cond do
        length(days) > 3 ->
          [off_days: "maximum 3 days allowed"]

        not Enum.all?(days, &(&1 in @valid_days)) ->
          [off_days: "each day must be between 0 (Sunday) and 6 (Saturday)"]

        length(days) != length(Enum.uniq(days)) ->
          [off_days: "days must be unique"]

        true ->
          []
      end
    end)
  end
end
```

- [ ] **Step 3: Update `WorkoutSection` schema — add note field**

In `apps/api/lib/milos_training/workouts/workout_section.ex`, add to schema:
```elixir
field :note, :string
```
Add `:note` to `cast/2` list in the changeset function.

- [ ] **Step 4: Update `WorkoutExercise` schema — add note field**

In `apps/api/lib/milos_training/workouts/workout_exercise.ex`, add to schema:
```elixir
field :note, :string
```
Add `:note` to `cast/2` list.

- [ ] **Step 5: Update `WorkoutExecution` schema — add exercise_modifications field**

In `apps/api/lib/milos_training/execution/workout_execution.ex`, add to schema:
```elixir
field :exercise_modifications, {:array, :map}, default: []
```
Add `:exercise_modifications` to `cast/2` in both `complete_changeset/2` and `progress_changeset/2`.

- [ ] **Step 6: Verify schemas compile**

```bash
cd apps/api && mix compile --warnings-as-errors
```

Expected: Compiles with no errors or warnings.

- [ ] **Step 7: Commit**

```bash
git add apps/api/lib/milos_training/gamification/user_stat.ex \
        apps/api/lib/milos_training/gamification/user_gamification_preferences.ex \
        apps/api/lib/milos_training/workouts/workout_section.ex \
        apps/api/lib/milos_training/workouts/workout_exercise.ex \
        apps/api/lib/milos_training/execution/workout_execution.ex
git commit -m "feat(schema): add gamification preferences schema, new user_stats fields, notes and modifications"
```

---

## Task 3: Domain — `DayStreakCalculator`

**Files:**
- Create: `apps/api/lib/milos_training/gamification/domain/day_streak_calculator.ex`
- Create: `apps/api/test/milos_training/gamification/domain/day_streak_calculator_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# apps/api/test/milos_training/gamification/domain/day_streak_calculator_test.exs
defmodule MilosTraining.Gamification.Domain.DayStreakCalculatorTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Gamification.Domain.DayStreakCalculator

  test "streak counts consecutive training days" do
    dates = [~D[2026-06-10], ~D[2026-06-11], ~D[2026-06-12]]

    result = DayStreakCalculator.calculate(dates, current_date: ~D[2026-06-12], off_days: [])

    assert result.current_streak == 3
    assert result.longest_streak == 3
  end

  test "off-days do not break the streak" do
    # Sunday=0, Saturday=6 are off days. User didn't train Sat/Sun but trained Mon-Fri.
    dates = [~D[2026-06-08], ~D[2026-06-09], ~D[2026-06-10], ~D[2026-06-11], ~D[2026-06-12]]
    # 2026-06-13 is Saturday (off day), 2026-06-14 is Sunday (off day)
    result =
      DayStreakCalculator.calculate(dates,
        current_date: ~D[2026-06-14],
        off_days: [0, 6]
      )

    assert result.current_streak == 5
  end

  test "missing a non-off-day breaks the streak" do
    # Trained Mon+Tue, skipped Wed (not an off day), trained Thu
    dates = [~D[2026-06-08], ~D[2026-06-09], ~D[2026-06-12]]

    result =
      DayStreakCalculator.calculate(dates,
        current_date: ~D[2026-06-12],
        off_days: [0, 6]
      )

    assert result.current_streak == 1
  end

  test "empty dates returns zero streak" do
    result = DayStreakCalculator.calculate([], current_date: ~D[2026-06-12], off_days: [])

    assert result.current_streak == 0
    assert result.longest_streak == 0
  end

  test "longest streak is tracked across breaks" do
    # 3-day streak, break, 1-day streak
    dates = [~D[2026-06-01], ~D[2026-06-02], ~D[2026-06-03], ~D[2026-06-10]]

    result = DayStreakCalculator.calculate(dates, current_date: ~D[2026-06-10], off_days: [])

    assert result.longest_streak == 3
    assert result.current_streak == 1
  end

  test "multiple off-days in a row within a week don't break streak" do
    # Off days: Sat(6), Sun(0). Trained Fri, off Sat+Sun, trained Mon.
    dates = [~D[2026-06-12], ~D[2026-06-15]]  # Fri, then Mon

    result =
      DayStreakCalculator.calculate(dates,
        current_date: ~D[2026-06-15],
        off_days: [0, 6]
      )

    assert result.current_streak == 2
  end
end
```

- [ ] **Step 2: Run to verify tests fail**

```bash
cd apps/api && mix test test/milos_training/gamification/domain/day_streak_calculator_test.exs
```

Expected: `(UndefinedFunctionError) function MilosTraining.Gamification.Domain.DayStreakCalculator.calculate/2 is undefined`

- [ ] **Step 3: Implement `DayStreakCalculator`**

```elixir
# apps/api/lib/milos_training/gamification/domain/day_streak_calculator.ex
defmodule MilosTraining.Gamification.Domain.DayStreakCalculator do
  @moduledoc """
  Calculates daily training streaks, treating configured off-days as neutral
  (they neither count as training days nor break the streak).
  """

  def calculate([], _opts), do: %{current_streak: 0, longest_streak: 0}

  def calculate(completed_dates, opts) do
    current_date = Keyword.get(opts, :current_date, Date.utc_today())
    off_days = Keyword.get(opts, :off_days, [])

    date_set = MapSet.new(completed_dates)

    # Walk backward from current_date, skipping off-days, counting training days
    {current_streak, longest_streak} =
      walk_backward(current_date, date_set, off_days, 0, 0, 0)

    %{current_streak: current_streak, longest_streak: longest_streak}
  end

  # Walk backward day by day from `date` to find current and longest streaks.
  # off_days: list of day-of-week integers (0=Sun … 6=Sat)
  defp walk_backward(date, date_set, off_days, current, longest, gap_days) do
    dow = Date.day_of_week(date, :sunday)  # 1=Mon … 7=Sun, convert to 0-based
    day_index = rem(dow, 7)               # 0=Sun, 1=Mon … 6=Sat

    cond do
      day_index in off_days ->
        # Off day: skip without breaking or counting streak
        # But only allow gaps up to the number of consecutive off-days in a week (max 3)
        if gap_days >= 3 do
          # Too many consecutive skipped days — stop
          {current, max(longest, current)}
        else
          walk_backward(Date.add(date, -1), date_set, off_days, current, longest, gap_days + 1)
        end

      MapSet.member?(date_set, date) ->
        # Training day: increment streak, reset gap counter
        new_current = current + 1
        walk_backward(
          Date.add(date, -1),
          date_set,
          off_days,
          new_current,
          max(longest, new_current),
          0
        )

      true ->
        # Non-off training day with no workout: streak breaks
        {current, max(longest, current)}
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd apps/api && mix test test/milos_training/gamification/domain/day_streak_calculator_test.exs
```

Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/api/lib/milos_training/gamification/domain/day_streak_calculator.ex \
        apps/api/test/milos_training/gamification/domain/day_streak_calculator_test.exs
git commit -m "feat(gamification/domain): add DayStreakCalculator with off-days support"
```

---

## Task 4: Domain — `MotivationCalculator`

**Files:**
- Create: `apps/api/lib/milos_training/gamification/domain/motivation_calculator.ex`
- Create: `apps/api/test/milos_training/gamification/domain/motivation_calculator_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# apps/api/test/milos_training/gamification/domain/motivation_calculator_test.exs
defmodule MilosTraining.Gamification.Domain.MotivationCalculatorTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Gamification.Domain.MotivationCalculator

  test "returns 100.0 when all 10 weeks meet the target" do
    # 2 workouts per week for 10 weeks
    dates =
      for w <- 0..9, d <- [0, 2] do
        Date.add(~D[2026-06-15], -(w * 7 + d))
      end

    result = MotivationCalculator.calculate(dates, target: 2, current_date: ~D[2026-06-15])

    assert result == 100.0
  end

  test "returns 0.0 when no weeks meet the target" do
    # Only 1 workout per week (target is 2)
    dates = for w <- 0..9, do: Date.add(~D[2026-06-15], -(w * 7))

    result = MotivationCalculator.calculate(dates, target: 2, current_date: ~D[2026-06-15])

    assert result == 0.0
  end

  test "returns proportional percentage for partial weeks on target" do
    # 5 weeks with 2+ workouts, 5 weeks with 1 workout
    on_target =
      for w <- [0, 2, 4, 6, 8], d <- [0, 2] do
        Date.add(~D[2026-06-15], -(w * 7 + d))
      end

    off_target = for w <- [1, 3, 5, 7, 9], do: Date.add(~D[2026-06-15], -(w * 7))

    result =
      MotivationCalculator.calculate(on_target ++ off_target,
        target: 2,
        current_date: ~D[2026-06-15]
      )

    assert result == 50.0
  end

  test "returns 0.0 for empty date list" do
    result = MotivationCalculator.calculate([], target: 2, current_date: ~D[2026-06-15])

    assert result == 0.0
  end

  test "looks back exactly 10 weeks" do
    # 11 weeks ago: 2 workouts. But it's outside the 10-week window.
    eleven_weeks_ago = Date.add(~D[2026-06-15], -(11 * 7))
    eleven_weeks_ago_plus_one = Date.add(eleven_weeks_ago, 1)

    result =
      MotivationCalculator.calculate([eleven_weeks_ago, eleven_weeks_ago_plus_one],
        target: 2,
        current_date: ~D[2026-06-15]
      )

    assert result == 0.0
  end
end
```

- [ ] **Step 2: Run to verify tests fail**

```bash
cd apps/api && mix test test/milos_training/gamification/domain/motivation_calculator_test.exs
```

Expected: `(UndefinedFunctionError) function ... is undefined`

- [ ] **Step 3: Implement `MotivationCalculator`**

```elixir
# apps/api/lib/milos_training/gamification/domain/motivation_calculator.ex
defmodule MilosTraining.Gamification.Domain.MotivationCalculator do
  @lookback_weeks 10

  def calculate([], _opts), do: 0.0

  def calculate(completed_dates, opts) do
    current_date = Keyword.get(opts, :current_date, Date.utc_today())
    target = Keyword.get(opts, :target, 2)

    cutoff = Date.add(current_date, -(@lookback_weeks * 7))

    recent_dates = Enum.filter(completed_dates, &(Date.compare(&1, cutoff) == :gt))

    if recent_dates == [] do
      0.0
    else
      weeks_on_target =
        recent_dates
        |> Enum.group_by(&week_bucket(&1, current_date))
        |> Enum.count(fn {_week, dates} -> length(dates) >= target end)

      Float.round(weeks_on_target / @lookback_weeks * 100.0, 2)
    end
  end

  # Bucket date into week index (0 = current week, 1 = last week, etc.)
  defp week_bucket(date, current_date) do
    days_ago = Date.diff(current_date, date)
    div(days_ago, 7)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd apps/api && mix test test/milos_training/gamification/domain/motivation_calculator_test.exs
```

Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/api/lib/milos_training/gamification/domain/motivation_calculator.ex \
        apps/api/test/milos_training/gamification/domain/motivation_calculator_test.exs
git commit -m "feat(gamification/domain): add MotivationCalculator (% of last 10 weeks on target)"
```

---

## Task 5: Domain — `PerseveranceCalculator`

**Files:**
- Create: `apps/api/lib/milos_training/gamification/domain/perseverance_calculator.ex`
- Create: `apps/api/test/milos_training/gamification/domain/perseverance_calculator_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# apps/api/test/milos_training/gamification/domain/perseverance_calculator_test.exs
defmodule MilosTraining.Gamification.Domain.PerseveranceCalculatorTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Gamification.Domain.PerseveranceCalculator

  test "returns 100.0 when no modifications in last 7 training days" do
    training_dates = for i <- 1..7, do: Date.add(~D[2026-06-15], -i)
    result = PerseveranceCalculator.calculate([], training_dates, off_days: [])
    assert result == 100.0
  end

  test "returns 0.0 when all exercises skipped on all days" do
    training_dates = [~D[2026-06-14], ~D[2026-06-13]]

    modifications = [
      %{"training_date" => ~D[2026-06-14], "skipped" => true,
        "prescribed_value" => 10.0, "actual_value" => nil, "field" => "reps"},
      %{"training_date" => ~D[2026-06-13], "skipped" => true,
        "prescribed_value" => 10.0, "actual_value" => nil, "field" => "reps"}
    ]

    result = PerseveranceCalculator.calculate(modifications, training_dates, off_days: [])
    assert result == 0.0
  end

  test "proportional deviation for reduced reps" do
    # Prescribed 10 reps, did 8 = 20% deviation = 80% perseverance
    training_dates = [~D[2026-06-14]]

    modifications = [
      %{"training_date" => ~D[2026-06-14], "skipped" => false,
        "prescribed_value" => 10.0, "actual_value" => 8.0, "field" => "reps"}
    ]

    result = PerseveranceCalculator.calculate(modifications, training_dates, off_days: [])
    assert result == 80.0
  end

  test "skipped exercise deviation equals prescribed reps (sets × reps)" do
    # Skipped: 3 sets × 10 reps = 30 total reps deviation
    training_dates = [~D[2026-06-14]]

    modifications = [
      %{"training_date" => ~D[2026-06-14], "skipped" => true,
        "prescribed_value" => 30.0, "actual_value" => nil, "field" => "reps"}
    ]

    result = PerseveranceCalculator.calculate(modifications, training_dates, off_days: [])
    assert result == 0.0
  end

  test "off-days excluded from 7-day training window" do
    # All 7 calendar days in range, but 2 are off-days; 5 training days, no modifications
    # Result should still be 100.0 (no modifications = perfect)
    # off_days: [0, 6] = Sun+Sat
    training_dates = [~D[2026-06-09], ~D[2026-06-10], ~D[2026-06-11], ~D[2026-06-12], ~D[2026-06-13]]
    result = PerseveranceCalculator.calculate([], training_dates, off_days: [0, 6])
    assert result == 100.0
  end

  test "time field deviation measured in minutes" do
    # Prescribed 10 mins, did 12 mins = 20% deviation = 80% perseverance
    training_dates = [~D[2026-06-14]]

    modifications = [
      %{"training_date" => ~D[2026-06-14], "skipped" => false,
        "prescribed_value" => 10.0, "actual_value" => 12.0, "field" => "time_mins"}
    ]

    result = PerseveranceCalculator.calculate(modifications, training_dates, off_days: [])
    assert result == 80.0
  end
end
```

- [ ] **Step 2: Run to verify tests fail**

```bash
cd apps/api && mix test test/milos_training/gamification/domain/perseverance_calculator_test.exs
```

Expected: `(UndefinedFunctionError) function ... is undefined`

- [ ] **Step 3: Implement `PerseveranceCalculator`**

```elixir
# apps/api/lib/milos_training/gamification/domain/perseverance_calculator.ex
defmodule MilosTraining.Gamification.Domain.PerseveranceCalculator do
  @lookback_days 7

  @doc """
  Calculates perseverance score (0.0–100.0) based on modification deviations
  over the last 7 training days (off-days excluded from window).

  `modifications` — list of maps with keys:
    training_date, field, prescribed_value, actual_value, skipped

  `training_dates` — list of Date structs when user actually trained

  `opts` — [off_days: [integer]] where 0=Sun … 6=Sat
  """
  def calculate(modifications, training_dates, opts \\ []) do
    off_days = Keyword.get(opts, :off_days, [])
    current_date = Keyword.get(opts, :current_date, Date.utc_today())

    recent_training_days =
      training_dates
      |> Enum.filter(fn d ->
        days_ago = Date.diff(current_date, d)
        days_ago >= 0 and days_ago <= @lookback_days * 2 and not off_day?(d, off_days)
      end)
      |> Enum.sort(:desc)
      |> Enum.take(@lookback_days)
      |> MapSet.new()

    if MapSet.size(recent_training_days) == 0 do
      100.0
    else
      mods_in_window =
        Enum.filter(modifications, fn m ->
          date = m["training_date"] || m[:training_date]
          MapSet.member?(recent_training_days, date)
        end)

      if mods_in_window == [] do
        100.0
      else
        total_deviation =
          mods_in_window
          |> Enum.map(&deviation/1)
          |> Enum.sum()

        avg_deviation = total_deviation / length(mods_in_window)
        score = max(0.0, (1.0 - avg_deviation) * 100.0)
        Float.round(score, 2)
      end
    end
  end

  defp deviation(%{"skipped" => true} = mod) do
    prescribed = mod["prescribed_value"] || mod[:prescribed_value] || 0.0
    if prescribed > 0, do: 1.0, else: 0.0
  end

  defp deviation(mod) do
    prescribed = mod["prescribed_value"] || mod[:prescribed_value] || 0.0
    actual = mod["actual_value"] || mod[:actual_value] || 0.0

    if prescribed == 0.0 do
      0.0
    else
      min(1.0, abs(prescribed - actual) / prescribed)
    end
  end

  defp off_day?(date, off_days) do
    dow = Date.day_of_week(date, :sunday)
    day_index = rem(dow, 7)
    day_index in off_days
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd apps/api && mix test test/milos_training/gamification/domain/perseverance_calculator_test.exs
```

Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/api/lib/milos_training/gamification/domain/perseverance_calculator.ex \
        apps/api/test/milos_training/gamification/domain/perseverance_calculator_test.exs
git commit -m "feat(gamification/domain): add PerseveranceCalculator with deviation rules"
```

---

## Task 6: Gamification Port + Store — Off-Days Preferences

**Files:**
- Modify: `apps/api/lib/milos_training/gamification/ports/gamification_store.ex`
- Modify: `apps/api/lib/milos_training/gamification/gamification_store.ex`
- Modify: `apps/api/lib/milos_training/infrastructure/gamification/ecto_gamification_store.ex`

- [ ] **Step 1: Add callbacks to port**

In `apps/api/lib/milos_training/gamification/ports/gamification_store.ex`, add:

```elixir
@callback get_user_preferences(user_id :: Ecto.UUID.t()) :: map() | nil
@callback upsert_user_preferences(user_id :: Ecto.UUID.t(), params :: map()) ::
            {:ok, map()} | {:error, Ecto.Changeset.t()}
```

- [ ] **Step 2: Add delegates to `GamificationStore` facade**

In `apps/api/lib/milos_training/gamification/gamification_store.ex`, add:

```elixir
@impl true
def get_user_preferences(user_id), do: adapter().get_user_preferences(user_id)

@impl true
def upsert_user_preferences(user_id, params),
  do: adapter().upsert_user_preferences(user_id, params)
```

- [ ] **Step 3: Implement in `EctoGamificationStore`**

In `apps/api/lib/milos_training/infrastructure/gamification/ecto_gamification_store.ex`, add alias for `UserGamificationPreferences` and implement:

```elixir
alias MilosTraining.Gamification.UserGamificationPreferences

@impl true
def get_user_preferences(user_id) do
  case Repo.get_by(UserGamificationPreferences, user_id: user_id) do
    nil -> nil
    prefs -> %{off_days: prefs.off_days}
  end
end

@impl true
def upsert_user_preferences(user_id, params) do
  case Repo.get_by(UserGamificationPreferences, user_id: user_id) do
    nil ->
      %UserGamificationPreferences{}
      |> UserGamificationPreferences.changeset(Map.put(params, :user_id, user_id))
      |> Repo.insert()
      |> normalize_preferences_result()

    %UserGamificationPreferences{} = prefs ->
      prefs
      |> UserGamificationPreferences.changeset(params)
      |> Repo.update()
      |> normalize_preferences_result()
  end
end

defp normalize_preferences_result({:ok, prefs}), do: {:ok, %{off_days: prefs.off_days}}
defp normalize_preferences_result({:error, _} = err), do: err
```

- [ ] **Step 4: Compile to verify**

```bash
cd apps/api && mix compile --warnings-as-errors
```

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add apps/api/lib/milos_training/gamification/ports/gamification_store.ex \
        apps/api/lib/milos_training/gamification/gamification_store.ex \
        apps/api/lib/milos_training/infrastructure/gamification/ecto_gamification_store.ex
git commit -m "feat(gamification): add off-days preferences to port, store facade, and ecto adapter"
```

---

## Task 7: Pantheon — Schemas + Port + Store + Infrastructure

**Files:**
- Create: `apps/api/lib/milos_training/pantheon/pr_record.ex`
- Create: `apps/api/lib/milos_training/pantheon/pr_history.ex`
- Create: `apps/api/lib/milos_training/pantheon/ports/pr_store.ex`
- Create: `apps/api/lib/milos_training/pantheon/pr_store.ex`
- Create: `apps/api/lib/milos_training/infrastructure/pantheon/ecto_pr_store.ex`

- [ ] **Step 1: Create `PRRecord` schema**

```elixir
# apps/api/lib/milos_training/pantheon/pr_record.ex
defmodule MilosTraining.Pantheon.PRRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_units ~w(mins_secs reps sets kcals m kg)

  schema "user_pr_records" do
    field :user_id, :binary_id
    field :name, :string
    field :current_score, :float
    field :unit, :string
    field :higher_is_better, :boolean, default: true
    field :beaten_on, :date

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record \\ %__MODULE__{}, params) do
    record
    |> cast(params, [:user_id, :name, :current_score, :unit, :higher_is_better, :beaten_on])
    |> validate_required([:user_id, :name, :current_score, :unit, :higher_is_better, :beaten_on])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:unit, @valid_units)
    |> foreign_key_constraint(:user_id)
  end

  def update_changeset(record, params) do
    record
    |> cast(params, [:name, :current_score, :unit, :higher_is_better, :beaten_on])
    |> validate_required([:name, :current_score, :unit, :higher_is_better, :beaten_on])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:unit, @valid_units)
  end
end
```

- [ ] **Step 2: Create `PRHistory` schema**

```elixir
# apps/api/lib/milos_training/pantheon/pr_history.ex
defmodule MilosTraining.Pantheon.PRHistory do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_pr_history" do
    field :pr_record_id, :binary_id
    field :score, :float
    field :beaten_on, :date

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(history \\ %__MODULE__{}, params) do
    history
    |> cast(params, [:pr_record_id, :score, :beaten_on])
    |> validate_required([:pr_record_id, :score, :beaten_on])
    |> foreign_key_constraint(:pr_record_id)
  end
end
```

- [ ] **Step 3: Create `PRStore` port**

```elixir
# apps/api/lib/milos_training/pantheon/ports/pr_store.ex
defmodule MilosTraining.Pantheon.Ports.PRStore do
  @callback list_user_prs(user_id :: Ecto.UUID.t()) :: [map()]
  @callback get_pr(id :: Ecto.UUID.t()) :: map() | nil
  @callback get_pr_for_user(id :: Ecto.UUID.t(), user_id :: Ecto.UUID.t()) :: map() | nil
  @callback create_pr(params :: map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_pr(id :: Ecto.UUID.t(), params :: map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback delete_pr(id :: Ecto.UUID.t(), user_id :: Ecto.UUID.t()) ::
              :ok | {:error, :not_found}
  @callback list_pr_history(pr_record_id :: Ecto.UUID.t()) :: [map()]
  @callback count_user_prs(user_id :: Ecto.UUID.t()) :: non_neg_integer()
end
```

- [ ] **Step 4: Create `PRStore` facade**

```elixir
# apps/api/lib/milos_training/pantheon/pr_store.ex
defmodule MilosTraining.Pantheon.PRStore do
  @behaviour MilosTraining.Pantheon.Ports.PRStore

  defp adapter do
    Application.get_env(
      :milos_training,
      :pr_store,
      MilosTraining.Infrastructure.Pantheon.EctoPRStore
    )
  end

  @impl true
  def list_user_prs(user_id), do: adapter().list_user_prs(user_id)

  @impl true
  def get_pr(id), do: adapter().get_pr(id)

  @impl true
  def get_pr_for_user(id, user_id), do: adapter().get_pr_for_user(id, user_id)

  @impl true
  def create_pr(params), do: adapter().create_pr(params)

  @impl true
  def update_pr(id, params), do: adapter().update_pr(id, params)

  @impl true
  def delete_pr(id, user_id), do: adapter().delete_pr(id, user_id)

  @impl true
  def list_pr_history(pr_record_id), do: adapter().list_pr_history(pr_record_id)

  @impl true
  def count_user_prs(user_id), do: adapter().count_user_prs(user_id)
end
```

- [ ] **Step 5: Implement `EctoPRStore`**

```elixir
# apps/api/lib/milos_training/infrastructure/pantheon/ecto_pr_store.ex
defmodule MilosTraining.Infrastructure.Pantheon.EctoPRStore do
  @behaviour MilosTraining.Pantheon.Ports.PRStore

  import Ecto.Query

  alias MilosTraining.Pantheon.{PRHistory, PRRecord}
  alias MilosTraining.Repo

  @impl true
  def list_user_prs(user_id) do
    PRRecord
    |> where([r], r.user_id == ^user_id)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_record/1)
  end

  @impl true
  def get_pr(id) do
    case Repo.get(PRRecord, id) do
      nil -> nil
      record -> normalize_record(record)
    end
  end

  @impl true
  def get_pr_for_user(id, user_id) do
    case Repo.get_by(PRRecord, id: id, user_id: user_id) do
      nil -> nil
      record -> normalize_record(record)
    end
  end

  @impl true
  def create_pr(params) do
    %PRRecord{}
    |> PRRecord.changeset(params)
    |> Repo.insert()
    |> normalize_result(&normalize_record/1)
  end

  @impl true
  def update_pr(id, params) do
    case Repo.get(PRRecord, id) do
      nil ->
        {:error, :not_found}

      %PRRecord{} = record ->
        Repo.transaction(fn ->
          # Log current score to history before updating
          {:ok, _history} =
            %PRHistory{}
            |> PRHistory.changeset(%{
              pr_record_id: record.id,
              score: record.current_score,
              beaten_on: record.beaten_on
            })
            |> Repo.insert()

          record
          |> PRRecord.update_changeset(params)
          |> Repo.update()
          |> case do
            {:ok, updated} -> normalize_record(updated)
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)
        |> case do
          {:ok, result} -> {:ok, result}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl true
  def delete_pr(id, user_id) do
    case Repo.get_by(PRRecord, id: id, user_id: user_id) do
      nil -> {:error, :not_found}
      record -> Repo.delete(record) |> then(fn _ -> :ok end)
    end
  end

  @impl true
  def list_pr_history(pr_record_id) do
    PRHistory
    |> where([h], h.pr_record_id == ^pr_record_id)
    |> order_by([h], desc: h.beaten_on)
    |> Repo.all()
    |> Enum.map(&normalize_history/1)
  end

  @impl true
  def count_user_prs(user_id) do
    Repo.aggregate(from(r in PRRecord, where: r.user_id == ^user_id), :count)
  end

  defp normalize_record(%PRRecord{} = r) do
    %{
      id: r.id,
      user_id: r.user_id,
      name: r.name,
      current_score: r.current_score,
      unit: r.unit,
      higher_is_better: r.higher_is_better,
      beaten_on: r.beaten_on,
      inserted_at: r.inserted_at,
      updated_at: r.updated_at
    }
  end

  defp normalize_history(%PRHistory{} = h) do
    %{id: h.id, pr_record_id: h.pr_record_id, score: h.score, beaten_on: h.beaten_on}
  end

  defp normalize_result({:ok, record}, normalizer), do: {:ok, normalizer.(record)}
  defp normalize_result({:error, _} = err, _normalizer), do: err
end
```

- [ ] **Step 6: Compile to verify**

```bash
cd apps/api && mix compile --warnings-as-errors
```

Expected: No errors.

- [ ] **Step 7: Commit**

```bash
git add apps/api/lib/milos_training/pantheon/ \
        apps/api/lib/milos_training/infrastructure/pantheon/
git commit -m "feat(pantheon): add PR schemas, port, store facade, and Ecto adapter"
```

---

## Task 8: Pantheon — Application Services + Context Facade

**Files:**
- Create: `apps/api/lib/milos_training/application/create_pr.ex`
- Create: `apps/api/lib/milos_training/application/update_pr.ex`
- Create: `apps/api/lib/milos_training/application/delete_pr.ex`
- Create: `apps/api/lib/milos_training/application/list_user_prs.ex`
- Create: `apps/api/lib/milos_training/application/get_pr_history.ex`
- Create: `apps/api/lib/milos_training/application/share_pr.ex`
- Create: `apps/api/lib/milos_training/pantheon.ex`

- [ ] **Step 1: Create application services**

```elixir
# apps/api/lib/milos_training/application/list_user_prs.ex
defmodule MilosTraining.Application.ListUserPRs do
  alias MilosTraining.Pantheon.PRStore

  def call(user_id, opts \\ []) do
    query = Keyword.get(opts, :query)
    prs = PRStore.list_user_prs(user_id)

    if query && String.trim(query) != "" do
      search_prs(prs, String.downcase(query))
    else
      {:ok, prs}
    end
  end

  # Client-side fuzzy filter as fallback; Meilisearch search is in the controller
  defp search_prs(prs, query) do
    filtered = Enum.filter(prs, fn pr ->
      String.contains?(String.downcase(pr.name), query)
    end)
    {:ok, filtered}
  end
end
```

```elixir
# apps/api/lib/milos_training/application/create_pr.ex
defmodule MilosTraining.Application.CreatePR do
  alias MilosTraining.Gamification
  alias MilosTraining.Pantheon.PRStore

  def call(user_id, params) do
    pr_params = Map.merge(params, %{user_id: user_id})

    with {:ok, pr} <- PRStore.create_pr(pr_params) do
      # Increment advancement_count in user_stats
      Gamification.increment_advancement(user_id)
      {:ok, pr}
    end
  end
end
```

```elixir
# apps/api/lib/milos_training/application/update_pr.ex
defmodule MilosTraining.Application.UpdatePR do
  alias MilosTraining.Gamification
  alias MilosTraining.Pantheon.PRStore

  def call(pr_id, user_id, params) do
    with pr when not is_nil(pr) <- PRStore.get_pr_for_user(pr_id, user_id),
         {:ok, updated} <- PRStore.update_pr(pr_id, params) do
      # Increment advancement_count if new score is better
      if is_improvement?(pr, updated) do
        Gamification.increment_advancement(user_id)
      end
      {:ok, updated}
    else
      nil -> {:error, :not_found}
      err -> err
    end
  end

  defp is_improvement?(old_pr, new_pr) do
    if old_pr.higher_is_better do
      new_pr.current_score > old_pr.current_score
    else
      new_pr.current_score < old_pr.current_score
    end
  end
end
```

```elixir
# apps/api/lib/milos_training/application/delete_pr.ex
defmodule MilosTraining.Application.DeletePR do
  alias MilosTraining.Pantheon.PRStore

  def call(pr_id, user_id) do
    PRStore.delete_pr(pr_id, user_id)
  end
end
```

```elixir
# apps/api/lib/milos_training/application/get_pr_history.ex
defmodule MilosTraining.Application.GetPRHistory do
  alias MilosTraining.Pantheon.PRStore

  def call(pr_id, user_id) do
    with pr when not is_nil(pr) <- PRStore.get_pr_for_user(pr_id, user_id) do
      {:ok, PRStore.list_pr_history(pr_id)}
    else
      nil -> {:error, :not_found}
    end
  end
end
```

```elixir
# apps/api/lib/milos_training/application/share_pr.ex
defmodule MilosTraining.Application.SharePR do
  alias MilosTraining.Pantheon.PRStore

  def call(pr_id, user_id) do
    with pr when not is_nil(pr) <- PRStore.get_pr_for_user(pr_id, user_id) do
      {:ok, format_share_message(pr)}
    else
      nil -> {:error, :not_found}
    end
  end

  defp format_share_message(pr) do
    date_str = Calendar.strftime(pr.beaten_on, "%b %d, %Y")
    score_str = format_score(pr.current_score, pr.unit)
    "🏆 New PR — #{pr.name}: #{score_str} (beaten on #{date_str})"
  end

  defp format_score(score, "mins_secs") do
    total_secs = round(score)
    mins = div(total_secs, 60)
    secs = rem(total_secs, 60)
    "#{mins}:#{String.pad_leading(to_string(secs), 2, "0")}"
  end

  defp format_score(score, unit) do
    value = if score == trunc(score), do: trunc(score), else: score
    "#{value} #{unit}"
  end
end
```

- [ ] **Step 2: Create `Pantheon` context facade**

```elixir
# apps/api/lib/milos_training/pantheon.ex
defmodule MilosTraining.Pantheon do
  alias MilosTraining.Application.{
    CreatePR,
    DeletePR,
    GetPRHistory,
    ListUserPRs,
    SharePR,
    UpdatePR
  }

  alias MilosTraining.Pantheon.PRStore

  defdelegate list_user_prs(user_id, opts \\ []), to: ListUserPRs, as: :call
  defdelegate create_pr(user_id, params), to: CreatePR, as: :call
  defdelegate update_pr(pr_id, user_id, params), to: UpdatePR, as: :call
  defdelegate delete_pr(pr_id, user_id), to: DeletePR, as: :call
  defdelegate get_pr_history(pr_id, user_id), to: GetPRHistory, as: :call
  defdelegate share_pr(pr_id, user_id), to: SharePR, as: :call

  def count_user_prs(user_id), do: PRStore.count_user_prs(user_id)
end
```

- [ ] **Step 3: Add `increment_advancement/1` to `Gamification` context**

In `apps/api/lib/milos_training/gamification.ex`, add:

```elixir
def increment_advancement(user_id) do
  stats = GamificationStore.get_user_stats(user_id) || %{advancement_count: 0}
  new_count = (stats[:advancement_count] || 0) + 1

  GamificationStore.upsert_user_stats(%{
    user_id: user_id,
    advancement_count: new_count,
    updated_at: DateTime.utc_now()
  })
end
```

- [ ] **Step 4: Compile to verify**

```bash
cd apps/api && mix compile --warnings-as-errors
```

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add apps/api/lib/milos_training/application/create_pr.ex \
        apps/api/lib/milos_training/application/update_pr.ex \
        apps/api/lib/milos_training/application/delete_pr.ex \
        apps/api/lib/milos_training/application/list_user_prs.ex \
        apps/api/lib/milos_training/application/get_pr_history.ex \
        apps/api/lib/milos_training/application/share_pr.ex \
        apps/api/lib/milos_training/pantheon.ex \
        apps/api/lib/milos_training/gamification.ex
git commit -m "feat(pantheon): add application services, context facade, and advancement increment"
```

---

## Task 9: Gamification Application Services — Preferences + Updated Metrics

**Files:**
- Create: `apps/api/lib/milos_training/application/get_gamification_preferences.ex`
- Create: `apps/api/lib/milos_training/application/update_gamification_preferences.ex`
- Modify: `apps/api/lib/milos_training/gamification/commands/record_workout_completion.ex`
- Modify: `apps/api/lib/milos_training/application/get_landing_page.ex`
- Modify: `apps/api/lib/milos_training/gamification.ex`

- [ ] **Step 1: Create `GetGamificationPreferences`**

```elixir
# apps/api/lib/milos_training/application/get_gamification_preferences.ex
defmodule MilosTraining.Application.GetGamificationPreferences do
  alias MilosTraining.Gamification.GamificationStore

  def call(user_id) do
    {:ok, GamificationStore.get_user_preferences(user_id)}
  end
end
```

- [ ] **Step 2: Create `UpdateGamificationPreferences`**

```elixir
# apps/api/lib/milos_training/application/update_gamification_preferences.ex
defmodule MilosTraining.Application.UpdateGamificationPreferences do
  alias MilosTraining.Gamification.GamificationStore

  def call(user_id, params) do
    GamificationStore.upsert_user_preferences(user_id, params)
  end
end
```

- [ ] **Step 3: Add delegates to `Gamification` facade**

In `apps/api/lib/milos_training/gamification.ex`, add:

```elixir
alias MilosTraining.Application.{GetGamificationPreferences, UpdateGamificationPreferences}

defdelegate get_gamification_preferences(user_id), to: GetGamificationPreferences, as: :call
defdelegate update_gamification_preferences(user_id, params),
  to: UpdateGamificationPreferences,
  as: :call
```

- [ ] **Step 4: Update `RecordWorkoutCompletion` to use new calculators**

In `apps/api/lib/milos_training/gamification/commands/record_workout_completion.ex`, update the `call/1` function. Replace the `StreakCalculator.update/2` call with the new calculators:

```elixir
# Add aliases at top of module:
alias MilosTraining.Gamification.Domain.{
  AchievementRules,
  ChallengeProgress,
  DayStreakCalculator,
  MotivationCalculator,
  PRDetector,
  PerseveranceCalculator
}

# In call/1, after fetching settings and completed_dates, also fetch:
preferences = GamificationStore.get_user_preferences(user_id) || %{off_days: []}
off_days = preferences[:off_days] || []

# Replace streaks = StreakCalculator.update(...) with:
day_streak = DayStreakCalculator.calculate(completed_dates,
  current_date: Date.utc_today(),
  off_days: off_days
)

motivation_score = MotivationCalculator.calculate(completed_dates,
  target: settings.weekly_workout_target,
  current_date: Date.utc_today()
)

modifications = current_execution.exercise_modifications || []
perseverance_score = PerseveranceCalculator.calculate(
  modifications,
  completed_dates,
  off_days: off_days
)
```

- [ ] **Step 5: Update `build_stats/5` in `RecordWorkoutCompletion`**

Replace the `build_stats` function to include new fields:

```elixir
defp build_stats(user_id, day_streak, motivation_score, perseverance_score, completed_executions, total_prs, current_execution) do
  existing = GamificationStore.get_user_stats(user_id) || %{advancement_count: 0}

  %{
    user_id: user_id,
    current_streak: day_streak.current_streak,
    longest_streak: max(existing[:longest_streak] || 0, day_streak.longest_streak),
    total_workouts: length(completed_executions),
    total_prs: total_prs,
    current_streak_shields: 1,
    motivation_score: motivation_score,
    perseverance_score: perseverance_score,
    advancement_count: existing[:advancement_count] || 0,
    last_workout_at: List.last(completed_executions, current_execution).completed_at_utc,
    consistency_score: motivation_score,
    updated_at: DateTime.utc_now()
  }
end
```

Update the `call/1` function to pass new args to `build_stats`.

- [ ] **Step 6: Update `GetLandingPage` to include preferences**

In `apps/api/lib/milos_training/application/get_landing_page.ex`, in `build_cached_payload/1` for non-admin:

```elixir
preferences = Gamification.get_gamification_preferences(user.id) |> elem(1)

# Include in returned map under gamification:
"gamification" => %{
  ...existing fields...,
  "preferences" => preferences
}
```

- [ ] **Step 7: Run all gamification tests**

```bash
cd apps/api && mix test test/milos_training/gamification/
```

Expected: All tests pass (some may need updating for new `build_stats` signature — fix failures as found).

- [ ] **Step 8: Commit**

```bash
git add apps/api/lib/milos_training/application/get_gamification_preferences.ex \
        apps/api/lib/milos_training/application/update_gamification_preferences.ex \
        apps/api/lib/milos_training/gamification/commands/record_workout_completion.ex \
        apps/api/lib/milos_training/application/get_landing_page.ex \
        apps/api/lib/milos_training/gamification.ex
git commit -m "feat(gamification): wire new calculators into RecordWorkoutCompletion, add preferences services"
```

---

## Task 10: Execution Modifications — Application Service

**Files:**
- Create: `apps/api/lib/milos_training/application/add_execution_modifications.ex`

- [ ] **Step 1: Create `AddExecutionModifications`**

```elixir
# apps/api/lib/milos_training/application/add_execution_modifications.ex
defmodule MilosTraining.Application.AddExecutionModifications do
  alias MilosTraining.Execution.ExecutionStore

  def call(execution_id, modifications, %{role: role})
      when role in [:admin, :coach] do
    with execution when not is_nil(execution) <-
           ExecutionStore.get_execution(execution_id),
         validated <- validate_modifications(modifications),
         merged <- merge_modifications(execution.exercise_modifications || [], validated),
         {:ok, updated} <-
           ExecutionStore.update_execution(execution_id, %{exercise_modifications: merged}) do
      {:ok, updated}
    else
      nil -> {:error, :not_found}
      {:error, _} = err -> err
    end
  end

  def call(_execution_id, _modifications, _user), do: {:error, :unauthorized}

  defp validate_modifications(mods) when is_list(mods) do
    Enum.map(mods, fn mod ->
      %{
        "exercise_id" => mod["exercise_id"] || mod[:exercise_id],
        "step_label" => mod["step_label"] || mod[:step_label] || "",
        "field" => mod["field"] || mod[:field],
        "prescribed_value" => mod["prescribed_value"] || mod[:prescribed_value],
        "actual_value" => mod["actual_value"] || mod[:actual_value],
        "skipped" => mod["skipped"] || mod[:skipped] || false,
        "logged_at" => DateTime.utc_now()
      }
    end)
  end

  defp merge_modifications(existing, new_mods) do
    existing ++ new_mods
  end
end
```

- [ ] **Step 2: Compile to verify**

```bash
cd apps/api && mix compile --warnings-as-errors
```

- [ ] **Step 3: Commit**

```bash
git add apps/api/lib/milos_training/application/add_execution_modifications.ex
git commit -m "feat(execution): add AddExecutionModifications service for coach/admin modifications"
```

---

## Task 11: Meilisearch — Pantheon PR Index

**Files:**
- Create: `apps/api/lib/milos_training/infrastructure/search/meilisearch_pr_index.ex`

- [ ] **Step 1: Create `MeilisearchPRIndex`**

```elixir
# apps/api/lib/milos_training/infrastructure/search/meilisearch_pr_index.ex
defmodule MilosTraining.Infrastructure.Search.MeilisearchPRIndex do
  require Logger

  @index_name "user_pr_records"
  @filterable_attributes ["user_id"]
  @searchable_attributes ["name"]
  @task_timeout_ms 1_500

  def search(user_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    body = %{
      q: query || "",
      limit: limit,
      filter: "user_id = #{user_id}"
    }

    case request(:post, "/indexes/#{@index_name}/search", json: body) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        hits = Map.get(body, "hits", [])
        {:ok, Enum.map(hits, &normalize_hit/1)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:meilisearch_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def upsert_document(pr) do
    doc = %{
      id: pr.id,
      user_id: pr.user_id,
      name: pr.name,
      current_score: pr.current_score,
      unit: pr.unit,
      beaten_on: to_string(pr.beaten_on)
    }

    case request(:post, "/indexes/#{@index_name}/documents", json: [doc]) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:meilisearch_status, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_document(id) do
    case request(:delete, "/indexes/#{@index_name}/documents/#{id}") do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:meilisearch_status, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  def ensure_settings do
    body = %{
      filterableAttributes: @filterable_attributes,
      searchableAttributes: @searchable_attributes
    }

    case request(:patch, "/indexes/#{@index_name}/settings", json: body) do
      {:ok, %Req.Response{status: status, body: %{"taskUid" => task_uid}}}
      when status in 200..299 ->
        wait_for_task(task_uid)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:meilisearch_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_hit(hit) do
    %{
      id: hit["id"],
      user_id: hit["user_id"],
      name: hit["name"],
      current_score: hit["current_score"],
      unit: hit["unit"]
    }
  end

  defp request(method, path, opts \\ []) do
    base_url = Application.get_env(:milos_training, :meilisearch_url, "http://localhost:7700")
    api_key = Application.get_env(:milos_training, :meilisearch_api_key)

    headers = if api_key, do: [{"Authorization", "Bearer #{api_key}"}], else: []

    Req.request(
      [{:method, method}, {:url, base_url <> path}, {:headers, headers}] ++ opts
    )
  end

  defp wait_for_task(task_uid) do
    Process.sleep(200)
    case request(:get, "/tasks/#{task_uid}") do
      {:ok, %Req.Response{body: %{"status" => "succeeded"}}} -> :ok
      {:ok, %Req.Response{body: %{"status" => "failed", "error" => err}}} -> {:error, err}
      _ ->
        Process.sleep(@task_timeout_ms)
        wait_for_task(task_uid)
    end
  end
end
```

- [ ] **Step 2: Compile to verify**

```bash
cd apps/api && mix compile --warnings-as-errors
```

- [ ] **Step 3: Commit**

```bash
git add apps/api/lib/milos_training/infrastructure/search/meilisearch_pr_index.ex
git commit -m "feat(search): add MeilisearchPRIndex for Pantheon PR search"
```

---

## Task 12: API Controllers + Routes

**Files:**
- Create: `apps/api/lib/milos_training_web/controllers/gamification_preferences_controller.ex`
- Create: `apps/api/lib/milos_training_web/controllers/pr_controller.ex`
- Create: `apps/api/lib/milos_training_web/controllers/execution_modifications_controller.ex`
- Modify: `apps/api/lib/milos_training_web/router.ex`

- [ ] **Step 1: Create `GamificationPreferencesController`**

```elixir
# apps/api/lib/milos_training_web/controllers/gamification_preferences_controller.ex
defmodule MilosTrainingWeb.GamificationPreferencesController do
  use MilosTrainingWeb, :controller

  alias MilosTraining.Gamification

  def show(conn, _params) do
    user = conn.assigns.current_user
    {:ok, prefs} = Gamification.get_gamification_preferences(user.id)
    json(conn, %{off_days: (prefs && prefs.off_days) || nil})
  end

  def update(conn, %{"off_days" => off_days}) when is_list(off_days) do
    user = conn.assigns.current_user

    case Gamification.update_gamification_preferences(user.id, %{off_days: off_days}) do
      {:ok, prefs} ->
        json(conn, %{off_days: prefs.off_days})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  def update(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "off_days must be an array"})
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
```

- [ ] **Step 2: Create `PRController`**

```elixir
# apps/api/lib/milos_training_web/controllers/pr_controller.ex
defmodule MilosTrainingWeb.PRController do
  use MilosTrainingWeb, :controller

  alias MilosTraining.{Messaging, Pantheon}
  alias MilosTraining.Infrastructure.Search.MeilisearchPRIndex

  def index(conn, params) do
    user = conn.assigns.current_user
    query = params["q"]

    prs =
      if query && String.trim(query) != "" do
        case MeilisearchPRIndex.search(user.id, query) do
          {:ok, hits} ->
            # Fetch full records for matching IDs
            ids = MapSet.new(Enum.map(hits, & &1.id))
            {:ok, all} = Pantheon.list_user_prs(user.id)
            Enum.filter(all, &MapSet.member?(ids, &1.id))

          {:error, _} ->
            {:ok, prs} = Pantheon.list_user_prs(user.id)
            prs
        end
      else
        {:ok, prs} = Pantheon.list_user_prs(user.id)
        prs
      end

    json(conn, %{prs: prs})
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    pr_params = %{
      name: params["name"],
      current_score: params["current_score"],
      unit: params["unit"],
      higher_is_better: Map.get(params, "higher_is_better", true),
      beaten_on: parse_date(params["beaten_on"])
    }

    case Pantheon.create_pr(user.id, pr_params) do
      {:ok, pr} ->
        Task.start(fn -> MeilisearchPRIndex.upsert_document(pr) end)
        conn |> put_status(:created) |> json(%{pr: pr})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    pr_params = %{
      name: params["name"],
      current_score: params["current_score"],
      unit: params["unit"],
      higher_is_better: Map.get(params, "higher_is_better", true),
      beaten_on: parse_date(params["beaten_on"])
    }

    case Pantheon.update_pr(id, user.id, pr_params) do
      {:ok, pr} ->
        Task.start(fn -> MeilisearchPRIndex.upsert_document(pr) end)
        json(conn, %{pr: pr})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "PR not found"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Pantheon.delete_pr(id, user.id) do
      :ok ->
        Task.start(fn -> MeilisearchPRIndex.delete_document(id) end)
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "PR not found"})
    end
  end

  def history(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Pantheon.get_pr_history(id, user.id) do
      {:ok, history} -> json(conn, %{history: history})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "PR not found"})
    end
  end

  def share(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Pantheon.share_pr(id, user.id) do
      {:ok, message} -> json(conn, %{message: message})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "PR not found"})
    end
  end

  defp parse_date(nil), do: Date.utc_today()
  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> Date.utc_today()
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end
end
```

- [ ] **Step 3: Create `ExecutionModificationsController`**

```elixir
# apps/api/lib/milos_training_web/controllers/execution_modifications_controller.ex
defmodule MilosTrainingWeb.ExecutionModificationsController do
  use MilosTrainingWeb, :controller

  alias MilosTraining.Application.AddExecutionModifications

  def create(conn, %{"execution_id" => execution_id, "modifications" => modifications}) do
    user = conn.assigns.current_user

    case AddExecutionModifications.call(execution_id, modifications, user) do
      {:ok, _execution} ->
        send_resp(conn, :no_content, "")

      {:error, :unauthorized} ->
        conn |> put_status(:forbidden) |> json(%{error: "Not authorized"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Execution not found"})
    end
  end
end
```

- [ ] **Step 4: Add routes to `router.ex`**

In `apps/api/lib/milos_training_web/router.ex`, inside the authenticated API scope, add:

```elixir
# Gamification preferences
get    "/gamification/preferences",     GamificationPreferencesController, :show
put    "/gamification/preferences",     GamificationPreferencesController, :update

# Pantheon (PR records)
get    "/prs",                           PRController, :index
post   "/prs",                           PRController, :create
patch  "/prs/:id",                       PRController, :update
delete "/prs/:id",                       PRController, :delete
get    "/prs/:id/history",               PRController, :history
post   "/prs/:id/share",                 PRController, :share

# Execution modifications (admin/coach only)
post   "/executions/:execution_id/modifications", ExecutionModificationsController, :create
```

- [ ] **Step 5: Compile and verify routes**

```bash
cd apps/api && mix compile --warnings-as-errors && mix phx.routes | grep -E "prs|gamification/pref|modifications"
```

Expected: All new routes listed, no compilation errors.

- [ ] **Step 6: Run full test suite**

```bash
cd apps/api && mix test
```

Expected: All tests pass. Fix any failures before committing.

- [ ] **Step 7: Run code quality checks**

```bash
cd apps/api && mix format && mix credo --strict
```

Expected: No credo warnings. Format produces no diffs.

- [ ] **Step 8: Commit**

```bash
git add apps/api/lib/milos_training_web/controllers/gamification_preferences_controller.ex \
        apps/api/lib/milos_training_web/controllers/pr_controller.ex \
        apps/api/lib/milos_training_web/controllers/execution_modifications_controller.ex \
        apps/api/lib/milos_training_web/router.ex
git commit -m "feat(api): add gamification preferences, Pantheon PR, and execution modifications endpoints"
```

---

## Task 13: Workout Notes — Backend Wire-Through

**Files:**
- Modify: `apps/api/lib/milos_training/application/create_draft_workout.ex`
- Modify: `apps/api/lib/milos_training/application/update_draft_workout.ex`
- Modify: `apps/api/lib/milos_training/application/get_materialized_workout.ex`

- [ ] **Step 1: Verify note fields flow through existing create/update workout pipeline**

```bash
cd apps/api && grep -n "note\|cast" apps/api/lib/milos_training/workouts/workout_section.ex apps/api/lib/milos_training/workouts/workout_exercise.ex
```

Expected: `:note` appears in `cast/2` lists (added in Task 2).

- [ ] **Step 2: Check that `get_materialized_workout` serializes sections with notes**

In `apps/api/lib/milos_training/application/get_materialized_workout.ex`, verify that section and exercise serialization maps include `:note`. If not, add `note: section.note` to section maps and `note: exercise.note` to exercise maps.

- [ ] **Step 3: Run existing workout tests**

```bash
cd apps/api && mix test test/milos_training/workouts/ test/milos_training/application/
```

Expected: All pass. If any test creates sections/exercises and breaks on the new field, update the test fixture to include `note: nil`.

- [ ] **Step 4: Commit**

```bash
git add apps/api/lib/milos_training/application/
git commit -m "feat(workouts): wire note fields through workout materialization"
```

---

## Final Backend Verification

- [ ] **Run full test suite**

```bash
cd apps/api && mix test
```

Expected: All tests pass.

- [ ] **Run format + credo**

```bash
cd apps/api && mix format --check-formatted && mix credo --strict
```

Expected: No issues.

- [ ] **Smoke test key routes with curl (dev server)**

```bash
# Start server
cd apps/api && mix phx.server &

# GET preferences (replace TOKEN with a valid JWT)
curl -H "Authorization: Bearer TOKEN" http://localhost:4000/api/gamification/preferences

# GET PRs
curl -H "Authorization: Bearer TOKEN" http://localhost:4000/api/prs
```

Expected: 200 responses with correct JSON shapes.
