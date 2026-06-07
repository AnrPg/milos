# Workout Creation Canvas — Backend Tasks (1–7)

Part of: [Main plan](./2026-06-07-workout-creation-ux.md)

---

## Task 1: Migration — Extend Workout Schema

**Files:**
- Create: `apps/api/priv/repo/migrations/20260607000000_extend_workout_model_for_canvas_ux.exs`

- [ ] **Step 1: Write the migration**

```elixir
defmodule MilosTraining.Repo.Migrations.ExtendWorkoutModelForCanvasUx do
  use Ecto.Migration

  def up do
    # master_workouts: add status and draft autosave blob
    alter table(:master_workouts) do
      add :status, :string, null: false, default: "draft"
      add :draft_data, :map
    end

    # workout_exercises: replace old prescription model with new one
    alter table(:workout_exercises) do
      remove :base_sets
      remove :base_reps
      remove :base_duration_seconds
      remove :description
      add :sets, :integer
      add :prescription_value, :integer
      add :prescription_unit, :string
      add :load_value, :integer
      add :load_mode, :string
      add :superset_group_id, :binary_id
      add :hr_zone, :integer
      add :tempo, :string
      add :rest_seconds, :integer
      add :cluster_rest_seconds, :integer
      add :rest_pause_seconds, :integer
      add :pacing, :integer
      add :interval_assignment, :integer
    end

    # exercise_variations: replace old fields with new prescription model
    alter table(:exercise_variations) do
      remove :description
      remove :reps
      remove :duration_seconds
      add :exercise_name_override, :string
      add :prescription_value, :integer
      add :prescription_unit, :string
      add :load_value, :integer
      add :load_mode, :string
      add :excluded, :boolean, null: false, default: false
    end
  end

  def down do
    alter table(:exercise_variations) do
      remove :excluded
      remove :load_mode
      remove :load_value
      remove :prescription_unit
      remove :prescription_value
      remove :exercise_name_override
      add :duration_seconds, :integer
      add :reps, :integer
      add :description, :string
    end

    alter table(:workout_exercises) do
      remove :interval_assignment
      remove :pacing
      remove :rest_pause_seconds
      remove :cluster_rest_seconds
      remove :rest_seconds
      remove :tempo
      remove :hr_zone
      remove :superset_group_id
      remove :load_mode
      remove :load_value
      remove :prescription_unit
      remove :prescription_value
      remove :sets
      add :description, :string
      add :base_duration_seconds, :integer
      add :base_reps, :integer
      add :base_sets, :integer
    end

    alter table(:master_workouts) do
      remove :draft_data
      remove :status
    end
  end
end
```

- [ ] **Step 2: Run migration**

```bash
cd apps/api && mix ecto.migrate
```

Expected: migration runs without errors.

- [ ] **Step 3: Update existing test payload to new schema**

In `test/milos_training_web/controllers/workout_controller_test.exs`, replace the exercise payload:

Old (remove):
```elixir
%{
  name: "Wall Balls",
  description: "Move smoothly",
  base_reps: 20,
  order: 1,
  variations: [
    %{scale_level_slug: "scaled", reps: 16, description: "Lighter target"},
    %{scale_level_slug: "competition", reps: 24, description: "Heavier ball"}
  ]
},
%{
  name: "Burpees",
  base_reps: 15,
  order: 2,
  variations: [%{scale_level_slug: "competition", reps: 18}]
}
```

New (add):
```elixir
%{
  name: "Wall Balls",
  sets: 1,
  prescription_value: 20,
  prescription_unit: "reps",
  order: 1,
  variations: [
    %{scale_level_slug: "scaled", prescription_value: 16},
    %{scale_level_slug: "competition", prescription_value: 24}
  ]
},
%{
  name: "Burpees",
  sets: 1,
  prescription_value: 15,
  prescription_unit: "reps",
  order: 2,
  variations: [%{scale_level_slug: "competition", prescription_value: 18}]
}
```

Also update any assertions that reference old field names in the response JSON.

- [ ] **Step 4: Run tests to verify existing suite still passes**

```bash
cd apps/api && mix test
```

Expected: all tests pass. (Some will fail until schemas are updated in Task 3 — fix schemas first, return here.)

- [ ] **Step 5: Commit**

```bash
git add apps/api/priv/repo/migrations/20260607000000_extend_workout_model_for_canvas_ux.exs \
        apps/api/test/milos_training_web/controllers/workout_controller_test.exs
git commit -m "feat(db): extend workout schema for canvas UX — new prescription model, status, draft_data"
```

---

## Task 2: Extend TimerConfig for All 18 Formats

**Files:**
- Modify: `apps/api/lib/milos_training/workouts/domain/timer_config.ex`

- [ ] **Step 1: Write the failing test**

In `test/milos_training/workouts/domain/timer_config_test.exs` (create if missing):

```elixir
defmodule MilosTraining.Workouts.Domain.TimerConfigTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.TimerConfig

  test "amrap requires duration_seconds" do
    assert {:error, _} = TimerConfig.normalize(%{"type" => "amrap"})
    assert {:ok, %{type: "amrap", duration_seconds: 720}} =
             TimerConfig.normalize(%{"type" => "amrap", "duration_seconds" => 720})
  end

  test "tabata requires work_seconds, rest_seconds, rounds" do
    assert {:error, _} = TimerConfig.normalize(%{"type" => "tabata", "work_seconds" => 20})
    assert {:ok, %{type: "tabata"}} =
             TimerConfig.normalize(%{
               "type" => "tabata",
               "work_seconds" => 20,
               "rest_seconds" => 10,
               "rounds" => 8
             })
  end

  test "accepts all 18 format types" do
    types_with_params = [
      {"untimed", %{}},
      {"for_time", %{}},
      {"train_to_exhaustion", %{}},
      {"kcal_target", %{"kcal_target" => 100}},
      {"emom", %{"duration_seconds" => 600, "interval_seconds" => 60}},
      {"complex_emom", %{"duration_seconds" => 600, "interval_seconds" => 60}},
      {"even_odd", %{"duration_seconds" => 600}},
      {"billat", %{"work_seconds" => 30, "rest_seconds" => 30, "cycles" => 8}},
      {"amrap", %{"duration_seconds" => 720}},
      {"edt", %{"duration_seconds" => 900}},
      {"death_by", %{"start_reps" => 1, "step_reps" => 1}},
      {"tabata", %{"work_seconds" => 20, "rest_seconds" => 10, "rounds" => 8}},
      {"custom_hiit", %{"work_seconds" => 40, "rest_seconds" => 20, "rounds" => 10}},
      {"cluster", %{"intra_rest_seconds" => 15, "sets" => 5}},
      {"hrr", %{"effort_seconds" => 30}},
      {"ladder_ascending", %{"start_reps" => 1, "step_reps" => 1}},
      {"ladder_descending", %{"start_reps" => 10, "step_reps" => 1, "min_reps" => 1}},
      {"pyramid", %{"peak_reps" => 10, "step_reps" => 2}},
      {"rest", %{"duration_seconds" => 60}}
    ]

    for {type, params} <- types_with_params do
      assert {:ok, _} = TimerConfig.normalize(Map.put(params, "type", type)),
             "expected #{type} to be valid"
    end
  end

  test "rejects unknown format type" do
    assert {:error, "has unsupported timer type"} =
             TimerConfig.normalize(%{"type" => "foobar"})
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd apps/api && mix test test/milos_training/workouts/domain/timer_config_test.exs
```

Expected: FAIL — many format types not accepted yet.

- [ ] **Step 3: Extend `timer_config.ex`**

```elixir
defmodule MilosTraining.Workouts.Domain.TimerConfig do
  @types ~w(
    untimed for_time train_to_exhaustion kcal_target
    emom complex_emom even_odd billat
    amrap edt death_by
    tabata custom_hiit cluster hrr
    ladder_ascending ladder_descending pyramid
    rest
  )

  def normalize(nil), do: {:ok, %{type: "untimed"}}

  def normalize(config) when is_map(config) do
    type = config |> get_value(:type) |> normalize_type()

    with :ok <- validate_type(type),
         :ok <- validate_required_fields(type, config) do
      {:ok, build_config(type, config)}
    end
  end

  def normalize(_config), do: {:error, "must be an object"}

  defp validate_type(type) do
    if type in @types, do: :ok, else: {:error, "has unsupported timer type"}
  end

  # Required fields per format
  defp validate_required_fields(type, config) do
    required = required_fields(type)

    missing =
      Enum.filter(required, fn field ->
        config |> get_value(field) |> blank?()
      end)

    case missing do
      [] -> :ok
      fields ->
        labels = fields |> Enum.map(&Atom.to_string/1) |> Enum.join(", ")
        {:error, "is missing required fields for this timer type: #{labels}"}
    end
  end

  defp required_fields("untimed"), do: []
  defp required_fields("for_time"), do: []
  defp required_fields("train_to_exhaustion"), do: []
  defp required_fields("kcal_target"), do: []
  defp required_fields("emom"), do: [:duration_seconds, :interval_seconds]
  defp required_fields("complex_emom"), do: [:duration_seconds, :interval_seconds]
  defp required_fields("even_odd"), do: [:duration_seconds]
  defp required_fields("billat"), do: [:work_seconds, :rest_seconds, :cycles]
  defp required_fields("amrap"), do: [:duration_seconds]
  defp required_fields("edt"), do: [:duration_seconds]
  defp required_fields("death_by"), do: [:start_reps, :step_reps]
  defp required_fields("tabata"), do: [:work_seconds, :rest_seconds, :rounds]
  defp required_fields("custom_hiit"), do: [:work_seconds, :rest_seconds, :rounds]
  defp required_fields("cluster"), do: [:intra_rest_seconds, :sets]
  defp required_fields("hrr"), do: [:effort_seconds]
  defp required_fields("ladder_ascending"), do: [:start_reps, :step_reps]
  defp required_fields("ladder_descending"), do: [:start_reps, :step_reps, :min_reps]
  defp required_fields("pyramid"), do: [:peak_reps, :step_reps]
  defp required_fields("rest"), do: [:duration_seconds]

  # Optional fields per format (stored if present)
  defp optional_fields("for_time"), do: [:time_cap_seconds]
  defp optional_fields("train_to_exhaustion"), do: [:rest_seconds]
  defp optional_fields("kcal_target"), do: [:kcal_target, :time_cap_seconds]
  defp optional_fields("edt"), do: [:pr_zone_rounds]
  defp optional_fields("death_by"), do: [:ladder_cap]
  defp optional_fields("ladder_ascending"), do: [:ladder_cap]
  defp optional_fields("hrr"), do: [:hr_zone]
  defp optional_fields(_), do: []

  defp build_config(type, config) do
    all_fields = required_fields(type) ++ optional_fields(type)

    Enum.reduce(all_fields, %{type: type}, fn key, acc ->
      case get_value(config, key) do
        nil -> acc
        "" -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp get_value(config, key),
    do: Map.get(config, key) || Map.get(config, Atom.to_string(key))

  defp normalize_type(nil), do: "untimed"
  defp normalize_type(type) when is_atom(type), do: type |> Atom.to_string() |> String.trim()
  defp normalize_type(type), do: type |> to_string() |> String.trim()

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
```

- [ ] **Step 4: Run tests to verify pass**

```bash
cd apps/api && mix test test/milos_training/workouts/domain/timer_config_test.exs
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add apps/api/lib/milos_training/workouts/domain/timer_config.ex \
        apps/api/test/milos_training/workouts/domain/timer_config_test.exs
git commit -m "feat(domain): extend TimerConfig to support all 18 workout format types"
```

---

## Task 3: Update Ecto Schemas

**Files:**
- Modify: `apps/api/lib/milos_training/workouts/master_workout.ex`
- Modify: `apps/api/lib/milos_training/workouts/workout_exercise.ex`
- Modify: `apps/api/lib/milos_training/workouts/exercise_variation.ex`

- [ ] **Step 1: Update `master_workout.ex`**

```elixir
defmodule MilosTraining.Workouts.MasterWorkout do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Workouts.WorkoutSection

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @types [:crossfit, :strength, :gymnastics, :aerobics, :flexibility, :recovery]
  @statuses [:draft, :published]

  schema "master_workouts" do
    field :title, :string
    field :type, Ecto.Enum, values: @types
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :draft_data, :map
    field :created_by_id, :binary_id

    has_many :sections, WorkoutSection, preload_order: [asc: :order]

    timestamps()
  end

  # Creates an empty draft — only requires the author
  def draft_changeset(workout \\ %__MODULE__{}, params) do
    workout
    |> cast(params, [:title, :type, :created_by_id, :draft_data, :status])
    |> validate_required([:created_by_id])
    |> foreign_key_constraint(:created_by_id)
  end

  # Updates draft_data and top-level fields without full validation
  def update_draft_changeset(workout, params) do
    workout
    |> cast(params, [:title, :type, :draft_data])
  end

  # Full validation used during publish
  def publish_changeset(workout, params) do
    workout
    |> cast(params, [:title, :type, :status])
    |> validate_required([:title, :type])
    |> validate_length(:title, min: 3, max: 160)
    |> put_change(:status, :published)
  end

  # Kept for backward-compat with existing test — delegates to draft_changeset
  def create_changeset(workout \\ %__MODULE__{}, params) do
    workout
    |> cast(params, [:title, :type, :created_by_id])
    |> validate_required([:title, :type, :created_by_id])
    |> validate_length(:title, min: 3, max: 160)
    |> foreign_key_constraint(:created_by_id)
    |> cast_assoc(:sections, required: true, with: &WorkoutSection.changeset/2)
  end

  def types, do: @types
  def statuses, do: @statuses
end
```

- [ ] **Step 2: Update `workout_exercise.ex`**

```elixir
defmodule MilosTraining.Workouts.WorkoutExercise do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Workouts.{ExerciseVariation, WorkoutSection}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @prescription_units [:reps, :secs, :kcal]
  @load_modes [:absolute, :pct_1rm]

  schema "workout_exercises" do
    field :name, :string
    field :sets, :integer
    field :prescription_value, :integer
    field :prescription_unit, Ecto.Enum, values: @prescription_units
    field :load_value, :integer
    field :load_mode, Ecto.Enum, values: @load_modes
    field :order, :integer

    # Advanced settings
    field :superset_group_id, :binary_id
    field :hr_zone, :integer
    field :tempo, :string
    field :rest_seconds, :integer
    field :cluster_rest_seconds, :integer
    field :rest_pause_seconds, :integer
    field :pacing, :integer
    field :interval_assignment, :integer

    belongs_to :workout_section, WorkoutSection
    has_many :variations, ExerciseVariation
  end

  def changeset(exercise \\ %__MODULE__{}, params) do
    exercise
    |> cast(params, [
      :name, :sets, :prescription_value, :prescription_unit,
      :load_value, :load_mode, :order,
      :superset_group_id, :hr_zone, :tempo, :rest_seconds,
      :cluster_rest_seconds, :rest_pause_seconds, :pacing, :interval_assignment
    ])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :order])
    |> validate_number(:order, greater_than_or_equal_to: 1)
    |> validate_positive_if_present(:sets)
    |> validate_positive_if_present(:prescription_value)
    |> validate_positive_if_present(:load_value)
    |> cast_assoc(:variations, with: &ExerciseVariation.changeset/2)
  end

  defp validate_positive_if_present(changeset, field) do
    validate_number(changeset, field, greater_than_or_equal_to: 1)
  end
end
```

- [ ] **Step 3: Update `exercise_variation.ex`**

```elixir
defmodule MilosTraining.Workouts.ExerciseVariation do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.{ScaleLevel, Workouts.WorkoutExercise}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @prescription_units [:reps, :secs, :kcal]
  @load_modes [:absolute, :pct_1rm]

  schema "exercise_variations" do
    field :exercise_name_override, :string
    field :sets, :integer
    field :prescription_value, :integer
    field :prescription_unit, Ecto.Enum, values: @prescription_units
    field :load_value, :integer
    field :load_mode, Ecto.Enum, values: @load_modes
    field :excluded, :boolean, default: false

    belongs_to :workout_exercise, WorkoutExercise
    belongs_to :scale_level, ScaleLevel

    timestamps(updated_at: false)
  end

  def changeset(variation \\ %__MODULE__{}, params) do
    variation
    |> cast(params, [
      :scale_level_id, :exercise_name_override,
      :sets, :prescription_value, :prescription_unit,
      :load_value, :load_mode, :excluded
    ])
    |> update_change(:exercise_name_override, &normalize_string/1)
    |> validate_required([:scale_level_id])
    |> validate_positive_if_present(:sets)
    |> validate_positive_if_present(:prescription_value)
    |> validate_positive_if_present(:load_value)
    |> validate_override_or_excluded()
    |> foreign_key_constraint(:scale_level_id)
    |> unique_constraint([:workout_exercise_id, :scale_level_id])
  end

  defp validate_override_or_excluded(changeset) do
    excluded = get_field(changeset, :excluded)
    if excluded, do: changeset, else: validate_at_least_one_override(changeset)
  end

  defp validate_at_least_one_override(changeset) do
    fields = [:exercise_name_override, :sets, :prescription_value, :load_value]
    all_blank = Enum.all?(fields, &(get_field(changeset, &1) |> blank?()))

    if all_blank do
      add_error(changeset, :scale_level_id, "variation must override at least one field or be excluded")
    else
      changeset
    end
  end

  defp validate_positive_if_present(changeset, field) do
    validate_number(changeset, field, greater_than_or_equal_to: 1)
  end

  defp normalize_string(nil), do: nil
  defp normalize_string(s), do: String.trim(s)

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
```

- [ ] **Step 4: Update `WorkoutMaterializer.apply_variation/2` for new field names**

In `apps/api/lib/milos_training/workouts/domain/workout_materializer.ex`, replace `apply_variation`:

```elixir
defp apply_variation(exercise, scale_slug) do
  case Enum.find(exercise.variations, &(&1.scale_level.slug == scale_slug)) do
    nil ->
      Map.put(exercise, :applied_variation, nil)

    %{excluded: true} = variation ->
      exercise
      |> Map.put(:excluded, true)
      |> Map.put(:applied_variation, variation)

    variation ->
      exercise
      |> maybe_put(:name, Map.get(variation, :exercise_name_override))
      |> maybe_put(:sets, Map.get(variation, :sets))
      |> maybe_put(:prescription_value, Map.get(variation, :prescription_value))
      |> maybe_put(:prescription_unit, Map.get(variation, :prescription_unit))
      |> maybe_put(:load_value, Map.get(variation, :load_value))
      |> maybe_put(:load_mode, Map.get(variation, :load_mode))
      |> Map.put(:applied_variation, variation)
      |> Map.put(:excluded, false)
  end
end
```

- [ ] **Step 5: Run tests**

```bash
cd apps/api && mix test
```

Expected: all tests pass. Fix any compilation errors before proceeding.

- [ ] **Step 6: Commit**

```bash
git add apps/api/lib/milos_training/workouts/master_workout.ex \
        apps/api/lib/milos_training/workouts/workout_exercise.ex \
        apps/api/lib/milos_training/workouts/exercise_variation.ex \
        apps/api/lib/milos_training/workouts/domain/workout_materializer.ex
git commit -m "feat(schema): update exercise and variation schemas to new prescription model"
```

---

## Task 4: Update EctoWorkoutStore + Port

**Files:**
- Modify: `apps/api/lib/milos_training/workouts/ports/workout_store.ex`
- Modify: `apps/api/lib/milos_training/infrastructure/workouts/ecto_workout_store.ex`

- [ ] **Step 1: Add new callbacks to the port**

In `workout_store.ex`, add:

```elixir
defmodule MilosTraining.Workouts.Ports.WorkoutStore do
  @callback create_workout(binary(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback create_draft(binary()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_draft(binary(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback publish_workout(binary(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback get_workout(binary()) :: map() | nil
  @callback get_workout_for_admin(binary()) :: map() | nil
  @callback list_workouts() :: [map()]
  @callback list_scale_levels() :: [map()]
  @callback replace_scale_levels([map()]) :: {:ok, [map()]} | {:error, Ecto.Changeset.t()}
end
```

- [ ] **Step 2: Add `create_draft` implementation to `EctoWorkoutStore`**

Add after the existing `create_workout` function:

```elixir
@impl true
def create_draft(admin_id) do
  %MasterWorkout{}
  |> MasterWorkout.draft_changeset(%{created_by_id: admin_id, status: :draft})
  |> Repo.insert()
  |> case do
    {:ok, workout} -> {:ok, %{id: workout.id, status: "draft"}}
    {:error, changeset} -> {:error, changeset}
  end
end

@impl true
def update_draft(id, params) do
  case Repo.get(MasterWorkout, id) do
    nil ->
      {:error, :not_found}

    workout ->
      workout
      |> MasterWorkout.update_draft_changeset(params)
      |> Repo.update()
      |> case do
        {:ok, updated} -> {:ok, %{id: updated.id, status: to_string(updated.status)}}
        {:error, changeset} -> {:error, changeset}
      end
  end
end

@impl true
def publish_workout(id, params) do
  case Repo.get(MasterWorkout, id) do
    nil ->
      {:error, :not_found}

    workout ->
      draft_data = workout.draft_data || %{}

      sections_params =
        (Map.get(draft_data, "sections") || Map.get(draft_data, :sections) || [])
        |> Enum.with_index(1)
        |> Enum.map(fn {s, i} -> Map.put(s, "order", i) end)

      merged_params =
        draft_data
        |> Map.merge(params)
        |> Map.put("sections", sections_params)

      with {:ok, params_with_levels} <- attach_scale_level_ids(merged_params) do
        Multi.new()
        |> Multi.update(:workout, MasterWorkout.publish_changeset(workout, merged_params))
        |> Multi.delete_all(:old_sections, Ecto.assoc(workout, :sections))
        |> Multi.run(:new_sections, fn _repo, %{workout: updated_workout} ->
          insert_sections(updated_workout.id, params_with_levels)
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{workout: published}} ->
            result =
              published
              |> Repo.preload(@workout_preloads)
              |> normalize_workout()
            {:ok, result}

          {:error, _step, %Ecto.Changeset{} = cs, _} ->
            {:error, cs}
        end
      end
  end
end

@impl true
def get_workout_for_admin(id) do
  case Repo.get(MasterWorkout, id) do
    nil ->
      nil

    workout ->
      base = %{
        id: workout.id,
        title: workout.title,
        type: workout.type && to_string(workout.type),
        status: to_string(workout.status),
        draft_data: workout.draft_data
      }

      if workout.status == :published do
        workout = Repo.preload(workout, @workout_preloads)
        base |> Map.put(:sections, Enum.map(workout.sections, &normalize_section/1))
      else
        base
      end
  end
end
```

- [ ] **Step 3: Add `insert_sections/2` helper to `EctoWorkoutStore`**

This is used by `publish_workout` to atomically create sections and exercises:

```elixir
defp insert_sections(workout_id, params) do
  sections = Map.get(params, :sections) || Map.get(params, "sections") || []

  Enum.reduce_while(sections, {:ok, []}, fn section_params, {:ok, acc} ->
    exercises = Map.get(section_params, :exercises) || Map.get(section_params, "exercises") || []

    section_changeset =
      %WorkoutSection{}
      |> WorkoutSection.changeset(Map.put(section_params, :master_workout_id, workout_id))

    case Repo.insert(section_changeset) do
      {:ok, section} ->
        case insert_exercises(section.id, exercises) do
          {:ok, _} -> {:cont, {:ok, [section | acc]}}
          error -> {:halt, error}
        end
      {:error, cs} -> {:halt, {:error, cs}}
    end
  end)
  |> case do
    {:ok, sections} -> {:ok, Enum.reverse(sections)}
    error -> error
  end
end

defp insert_exercises(section_id, exercises) do
  exercises
  |> Enum.with_index(1)
  |> Enum.reduce_while({:ok, []}, fn {ex_params, order}, {:ok, acc} ->
    variations = Map.get(ex_params, :variations) || Map.get(ex_params, "variations") || []

    ex_changeset =
      %WorkoutExercise{}
      |> WorkoutExercise.changeset(
        ex_params
        |> Map.put(:order, order)
        |> Map.put(:workout_section_id, section_id)
      )

    case Repo.insert(ex_changeset) do
      {:ok, exercise} ->
        case insert_variations(exercise.id, variations) do
          {:ok, _} -> {:cont, {:ok, [exercise | acc]}}
          error -> {:halt, error}
        end
      {:error, cs} -> {:halt, {:error, cs}}
    end
  end)
  |> case do
    {:ok, exercises} -> {:ok, Enum.reverse(exercises)}
    error -> error
  end
end

defp insert_variations(exercise_id, variations) do
  Enum.reduce_while(variations, {:ok, []}, fn var_params, {:ok, acc} ->
    changeset =
      %ExerciseVariation{}
      |> ExerciseVariation.changeset(Map.put(var_params, :workout_exercise_id, exercise_id))

    case Repo.insert(changeset) do
      {:ok, v} -> {:cont, {:ok, [v | acc]}}
      {:error, cs} -> {:halt, {:error, cs}}
    end
  end)
end
```

- [ ] **Step 4: Update `normalize_exercise` and `normalize_variation` for new schema**

Replace `normalize_exercise/1` and `normalize_variation/1`:

```elixir
defp normalize_exercise(%WorkoutExercise{} = exercise) do
  %{
    id: exercise.id,
    name: exercise.name,
    sets: exercise.sets,
    prescription_value: exercise.prescription_value,
    prescription_unit: exercise.prescription_unit && to_string(exercise.prescription_unit),
    load_value: exercise.load_value,
    load_mode: exercise.load_mode && to_string(exercise.load_mode),
    superset_group_id: exercise.superset_group_id,
    hr_zone: exercise.hr_zone,
    tempo: exercise.tempo,
    rest_seconds: exercise.rest_seconds,
    cluster_rest_seconds: exercise.cluster_rest_seconds,
    rest_pause_seconds: exercise.rest_pause_seconds,
    pacing: exercise.pacing,
    interval_assignment: exercise.interval_assignment,
    order: exercise.order,
    variations:
      exercise.variations
      |> Enum.sort_by(& &1.scale_level.sort_order)
      |> Enum.map(&normalize_variation/1)
  }
end

defp normalize_variation(%ExerciseVariation{} = variation) do
  %{
    id: variation.id,
    exercise_name_override: variation.exercise_name_override,
    sets: variation.sets,
    prescription_value: variation.prescription_value,
    prescription_unit: variation.prescription_unit && to_string(variation.prescription_unit),
    load_value: variation.load_value,
    load_mode: variation.load_mode && to_string(variation.load_mode),
    excluded: variation.excluded,
    scale_level: normalize_scale_level(variation.scale_level)
  }
end
```

Also update `normalize_workout/1` to include `status`:

```elixir
defp normalize_workout(%MasterWorkout{} = workout) do
  # ...existing code...
  normalized = %{
    id: workout.id,
    title: workout.title,
    type: workout.type |> to_string(),
    status: workout.status |> to_string(),   # ADD THIS
    created_by_id: workout.created_by_id,
    inserted_at: workout.inserted_at,
    updated_at: workout.updated_at,
    sections: sections
  }
  Map.put(normalized, :available_scale_levels, WorkoutMaterializer.available_scales(normalized))
end
```

- [ ] **Step 5: Update `workouts.ex` context to expose new functions**

```elixir
defmodule MilosTraining.Workouts do
  alias MilosTraining.Workouts.Commands.{
    CreateWorkout,
    CreateDraftWorkout,
    UpdateDraftWorkout,
    PublishWorkout,
    ReplaceScaleLevels
  }

  alias MilosTraining.Workouts.Queries.{
    GetWorkout,
    ListScaleLevels,
    ListWorkouts,
    MaterializeWorkout
  }

  def create_workout(admin, params), do: CreateWorkout.call(admin.id, params)
  def create_draft(admin), do: CreateDraftWorkout.call(admin.id)
  def update_draft(id, params), do: UpdateDraftWorkout.call(id, params)
  def publish_workout(id, params), do: PublishWorkout.call(id, params)
  defdelegate get_workout(id), to: GetWorkout, as: :by_id
  def get_workout_for_admin(id), do: WorkoutStore.get_workout_for_admin(id)
  defdelegate list_workouts, to: ListWorkouts, as: :all
  defdelegate list_scale_levels, to: ListScaleLevels, as: :all
  defdelegate replace_scale_levels(levels), to: ReplaceScaleLevels, as: :call
  defdelegate materialize_workout(id), to: MaterializeWorkout, as: :by_id
end
```

- [ ] **Step 6: Run tests**

```bash
cd apps/api && mix test
```

- [ ] **Step 7: Commit**

```bash
git add apps/api/lib/milos_training/workouts/ports/workout_store.ex \
        apps/api/lib/milos_training/infrastructure/workouts/ecto_workout_store.ex \
        apps/api/lib/milos_training/workouts.ex
git commit -m "feat(infra): add create_draft, update_draft, publish_workout to EctoWorkoutStore"
```

---

## Task 5: Create Command Modules

**Files:**
- Create: `apps/api/lib/milos_training/workouts/commands/create_draft_workout.ex`
- Create: `apps/api/lib/milos_training/workouts/commands/update_draft_workout.ex`
- Create: `apps/api/lib/milos_training/workouts/commands/publish_workout.ex`

- [ ] **Step 1: Write `create_draft_workout.ex`**

```elixir
defmodule MilosTraining.Workouts.Commands.CreateDraftWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def call(admin_id), do: WorkoutStore.create_draft(admin_id)
end
```

- [ ] **Step 2: Write `update_draft_workout.ex`**

```elixir
defmodule MilosTraining.Workouts.Commands.UpdateDraftWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def call(id, params), do: WorkoutStore.update_draft(id, params)
end
```

- [ ] **Step 3: Write `publish_workout.ex` (command)**

```elixir
defmodule MilosTraining.Workouts.Commands.PublishWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def call(id, params \\ %{}), do: WorkoutStore.publish_workout(id, params)
end
```

- [ ] **Step 4: Write application service `apps/api/lib/milos_training/application/publish_workout.ex`**

```elixir
defmodule MilosTraining.Application.PublishWorkout do
  alias MilosTraining.Workouts

  def call(admin, id) do
    case Workouts.get_workout_for_admin(id) do
      nil ->
        {:error, :not_found}

      %{status: "published"} ->
        {:error, :already_published}

      workout ->
        if workout_owned_by?(workout, admin.id) do
          Workouts.publish_workout(id, %{})
        else
          {:error, :forbidden}
        end
    end
  end

  defp workout_owned_by?(workout, admin_id) do
    Map.get(workout, :created_by_id) == admin_id ||
      Map.get(workout, "created_by_id") == admin_id
  end
end
```

- [ ] **Step 5: Run tests**

```bash
cd apps/api && mix test
```

- [ ] **Step 6: Commit**

```bash
git add apps/api/lib/milos_training/workouts/commands/ \
        apps/api/lib/milos_training/application/publish_workout.ex
git commit -m "feat(app): add CreateDraftWorkout, UpdateDraftWorkout, PublishWorkout commands"
```

---

## Task 6: Router + Controller — New Admin Endpoints

**Files:**
- Modify: `apps/api/lib/milos_training_web/router.ex`
- Modify: `apps/api/lib/milos_training_web/controllers/admin_workout_controller.ex`

- [ ] **Step 1: Add routes to `router.ex`**

In the `/api/admin` scope, replace the workout routes:

```elixir
scope "/api/admin", MilosTrainingWeb do
  pipe_through [:api, :authenticated, :admin_only]

  patch "/users/:id/role", AdminUserController, :update_role
  get "/scale-levels", AdminScaleLevelController, :index
  put "/scale-levels", AdminScaleLevelController, :update

  # Workout CRUD
  get "/workouts", AdminWorkoutController, :index
  post "/workouts", AdminWorkoutController, :create_draft
  get "/workouts/:id", AdminWorkoutController, :show
  patch "/workouts/:id/draft", AdminWorkoutController, :update_draft
  post "/workouts/:id/publish", AdminWorkoutController, :publish
end
```

- [ ] **Step 2: Update `admin_workout_controller.ex`**

Add the new action specs and implementations. Append to the existing controller:

```elixir
  # Existing :index and :create remain — :create is now :create_draft
  # Rename the existing `create` action to `create_draft`:

  operation(:create_draft,
    summary: "Create an empty draft workout",
    responses: [
      created: {"Draft ID", "application/json",
        %Schema{type: :object, properties: %{workout: %Schema{type: :object,
          properties: %{id: %Schema{type: :string}}, required: [:id]}},
        required: [:workout]}}
    ]
  )

  def create_draft(conn, _params) do
    admin = GuardianPlug.current_resource(conn)

    case MilosTraining.Workouts.create_draft(admin) do
      {:ok, draft} ->
        conn |> put_status(:created) |> json(%{workout: draft})
      error -> error
    end
  end

  operation(:show,
    summary: "Get a workout for admin editing",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Workout", "application/json",
        %Schema{type: :object, properties: %{workout: %Schema{type: :object,
          additionalProperties: true}}, required: [:workout]}},
      not_found: {"Not found", "application/json",
        %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  def show(conn, %{"id" => id}) do
    case MilosTraining.Workouts.get_workout_for_admin(id) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "workout not found"})
      workout -> json(conn, %{workout: workout})
    end
  end

  operation(:update_draft,
    summary: "Autosave draft workout (no validation)",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Draft", "application/json",
        %Schema{type: :object, properties: %{workout: %Schema{type: :object,
          additionalProperties: true}}}},
      not_found: {"Not found", "application/json",
        %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  def update_draft(conn, %{"id" => id}) do
    params = %{
      title: conn.body_params[:title],
      type: conn.body_params[:type],
      draft_data: conn.body_params
    }

    case MilosTraining.Workouts.update_draft(id, params) do
      {:ok, draft} -> json(conn, %{workout: draft})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "workout not found"})
      {:error, cs} -> {:error, cs}
    end
  end

  operation(:publish,
    summary: "Publish a draft workout",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Published workout", "application/json",
        %Schema{type: :object, properties: %{workout: %Schema{type: :object,
          additionalProperties: true}}}},
      unprocessable_entity: {"Validation errors", "application/json",
        %Schema{type: :object, properties: %{errors: %Schema{type: :object,
          additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}}},
        required: [:errors]}}
    ]
  )

  def publish(conn, %{"id" => id}) do
    admin = GuardianPlug.current_resource(conn)

    case MilosTraining.Application.PublishWorkout.call(admin, id) do
      {:ok, workout} -> json(conn, %{workout: workout})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "workout not found"})
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
      {:error, :already_published} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "already published"})
      error -> error
    end
  end
```

Note: also add `CastAndValidate` plug to include the new actions.

- [ ] **Step 3: Ensure the `WorkoutStore` module alias resolves correctly**

In `ecto_workout_store.ex`, add `alias MilosTraining.Workouts.Ports.WorkoutStore` if missing, and add the module reference in `workouts.ex`:

```elixir
# In workouts.ex, add near top:
alias MilosTraining.Workouts.Ports.WorkoutStore
```

- [ ] **Step 4: Run tests**

```bash
cd apps/api && mix test && mix format && mix credo --strict
```

Fix any warnings or credo issues.

- [ ] **Step 5: Commit**

```bash
git add apps/api/lib/milos_training_web/router.ex \
        apps/api/lib/milos_training_web/controllers/admin_workout_controller.ex
git commit -m "feat(api): add admin workout show, update_draft, and publish endpoints"
```

---

## Task 7: New Controller Tests

**Files:**
- Create: `apps/api/test/milos_training_web/controllers/admin_workout_controller_test.exs`

- [ ] **Step 1: Write the tests**

```elixir
defmodule MilosTrainingWeb.AdminWorkoutControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  describe "POST /api/admin/workouts — create draft" do
    test "admin can create an empty draft", %{conn: conn} do
      admin_conn = authenticate_as_admin(conn, "draft_creator")

      resp =
        admin_conn
        |> post("/api/admin/workouts")
        |> json_response(201)

      assert %{"workout" => %{"id" => id}} = resp
      assert is_binary(id)
    end

    test "non-admin cannot create draft", %{conn: conn} do
      member_conn = authenticate_as_member(conn, "plain_member")

      member_conn
      |> post("/api/admin/workouts")
      |> json_response(403)
    end
  end

  describe "PATCH /api/admin/workouts/:id/draft — autosave" do
    test "admin can autosave draft data", %{conn: conn} do
      admin_conn = authenticate_as_admin(conn, "autosave_admin")
      %{"workout" => %{"id" => id}} = admin_conn |> post("/api/admin/workouts") |> json_response(201)

      payload = %{
        title: "My Draft",
        type: "crossfit",
        sections: [
          %{name: "Warmup", timer_config: %{type: "untimed"}, scoreable: false, exercises: []}
        ]
      }

      resp =
        admin_conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/admin/workouts/#{id}/draft", Jason.encode!(payload))
        |> json_response(200)

      assert %{"workout" => %{"id" => ^id}} = resp
    end

    test "returns 404 for unknown workout", %{conn: conn} do
      admin_conn = authenticate_as_admin(conn, "notfound_admin")
      fake_id = Ecto.UUID.generate()

      admin_conn
      |> put_req_header("content-type", "application/json")
      |> patch("/api/admin/workouts/#{fake_id}/draft", Jason.encode!(%{title: "x"}))
      |> json_response(404)
    end
  end

  describe "POST /api/admin/workouts/:id/publish" do
    test "admin can publish a valid draft", %{conn: conn} do
      admin_conn = authenticate_as_admin(conn, "publisher_admin")

      # Create scale levels first
      admin_conn
      |> put_req_header("content-type", "application/json")
      |> put("/api/admin/scale-levels", Jason.encode!(%{
        scale_levels: [%{slug: "rx", label: "Rx", sort_order: 1}]
      }))
      |> json_response(200)

      %{"workout" => %{"id" => id}} = admin_conn |> post("/api/admin/workouts") |> json_response(201)

      payload = %{
        title: "Published Workout",
        type: "strength",
        sections: [
          %{
            name: "Main",
            timer_config: %{type: "untimed"},
            scoreable: false,
            exercises: [
              %{
                name: "Deadlift",
                sets: 5,
                prescription_value: 5,
                prescription_unit: "reps",
                variations: []
              }
            ]
          }
        ]
      }

      # Autosave first
      admin_conn
      |> put_req_header("content-type", "application/json")
      |> patch("/api/admin/workouts/#{id}/draft", Jason.encode!(payload))
      |> json_response(200)

      # Publish
      resp =
        admin_conn
        |> post("/api/admin/workouts/#{id}/publish")
        |> json_response(200)

      assert get_in(resp, ["workout", "status"]) == "published"
      assert get_in(resp, ["workout", "title"]) == "Published Workout"
    end
  end

  describe "GET /api/admin/workouts/:id" do
    test "admin can fetch draft for editing", %{conn: conn} do
      admin_conn = authenticate_as_admin(conn, "fetch_admin")
      %{"workout" => %{"id" => id}} = admin_conn |> post("/api/admin/workouts") |> json_response(201)

      admin_conn
      |> put_req_header("content-type", "application/json")
      |> patch("/api/admin/workouts/#{id}/draft", Jason.encode!(%{title: "Fetched"}))
      |> json_response(200)

      resp = admin_conn |> get("/api/admin/workouts/#{id}") |> json_response(200)
      assert get_in(resp, ["workout", "id"]) == id
      assert get_in(resp, ["workout", "status"]) == "draft"
    end
  end

  # Test helpers — add these to ConnCase support if not already present:
  defp authenticate_as_admin(conn, username) do
    {:ok, user} = MilosTraining.Identity.create_user(%{
      username: username,
      email: "#{username}@test.com",
      password: "password123456",
      role: :admin
    })
    {:ok, token, _claims} =
      MilosTraining.Infrastructure.Auth.Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp authenticate_as_member(conn, username) do
    {:ok, user} = MilosTraining.Identity.create_user(%{
      username: username,
      email: "#{username}@test.com",
      password: "password123456",
      role: :member
    })
    {:ok, token, _claims} =
      MilosTraining.Infrastructure.Auth.Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
```

- [ ] **Step 2: Run tests**

```bash
cd apps/api && mix test test/milos_training_web/controllers/admin_workout_controller_test.exs
```

Expected: all pass.

- [ ] **Step 3: Run full suite**

```bash
cd apps/api && mix test
```

Expected: all pass.

- [ ] **Step 4: Final backend quality checks**

```bash
cd apps/api && mix format && mix credo --strict
```

Fix any remaining issues.

- [ ] **Step 5: Commit**

```bash
git add apps/api/test/milos_training_web/controllers/admin_workout_controller_test.exs
git commit -m "test(api): add admin workout draft/publish endpoint tests"
```

---

## Fix: Add delegating functions to `WorkoutStore` concrete module

The `MilosTraining.Workouts.WorkoutStore` module (at `lib/milos_training/workouts/workout_store.ex`) is the concrete module commands use. It delegates to an adapter (default: `EctoWorkoutStore`). New callbacks added to the port and implementation must also be added here.

**Modify `lib/milos_training/workouts/workout_store.ex`** — add after the existing functions:

```elixir
defmodule MilosTraining.Workouts.WorkoutStore do
  @behaviour MilosTraining.Workouts.Ports.WorkoutStore

  defp adapter do
    Application.get_env(
      :milos_training,
      :workout_store,
      MilosTraining.Infrastructure.Workouts.EctoWorkoutStore
    )
  end

  @impl true
  def create_workout(admin_id, params), do: adapter().create_workout(admin_id, params)

  @impl true
  def create_draft(admin_id), do: adapter().create_draft(admin_id)

  @impl true
  def update_draft(id, params), do: adapter().update_draft(id, params)

  @impl true
  def publish_workout(id, params), do: adapter().publish_workout(id, params)

  @impl true
  def get_workout(id), do: adapter().get_workout(id)

  @impl true
  def get_workout_for_admin(id), do: adapter().get_workout_for_admin(id)

  @impl true
  def list_workouts, do: adapter().list_workouts()

  @impl true
  def list_scale_levels, do: adapter().list_scale_levels()

  @impl true
  def replace_scale_levels(levels), do: adapter().replace_scale_levels(levels)
end
```

This must be done as part of Task 4 (EctoWorkoutStore + Port), after Step 1.

---

## Known Gaps — Deferred to Follow-Up

The following spec requirements are not covered in this plan and should be addressed in a follow-up plan:

1. **Supersets** — "Add to superset" action in the advanced panel groups exercises with a border wrapper, `overflow: visible`, and a `SUPERSET` label. Requires: `supersetGroupId` field already added to DB and types; needs `SupersetWrapper.tsx` component and store logic to group exercises sharing a `supersetGroupId`.

2. **Format-specific exercise behavior** — `complex_emom` sections should show a minute-assignment indicator per exercise; `even_odd` sections should show an "Even / Odd" toggle per exercise. The `interval_assignment` field is already in the schema; the UI is deferred.

3. **Draft badge in admin workout list** — The `list_workouts` query currently returns all workouts. Published status should be visible. Update `normalize_workout` in `EctoWorkoutStore` to include `status`, update `WorkoutAdminConsole` list view to show `[Draft]` badge.

4. **Mobile: "Move to section →" action** — The spec says cross-section exercise moves on mobile go via an action in the advanced settings panel (not drag). Add a section selector in `AdvancedSettingsPanel` that calls `moveExercise` from the store.

5. **Unpublish (revert to draft)** — The spec says published workouts can be reverted to draft. Requires a `DELETE /api/admin/workouts/:id/publish` or `PATCH` endpoint.
