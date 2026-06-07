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
      :workout_section_id,
      :name,
      :sets,
      :prescription_value,
      :prescription_unit,
      :load_value,
      :load_mode,
      :order,
      :superset_group_id,
      :hr_zone,
      :tempo,
      :rest_seconds,
      :cluster_rest_seconds,
      :rest_pause_seconds,
      :pacing,
      :interval_assignment
    ])
    |> update_change(:name, &normalize_name/1)
    |> validate_required([:name, :order])
    |> validate_number(:order, greater_than_or_equal_to: 1)
    |> validate_optional_number(:sets)
    |> validate_optional_number(:prescription_value)
    |> validate_optional_number(:load_value)
    |> validate_optional_number(:hr_zone)
    |> validate_optional_number(:rest_seconds)
    |> validate_optional_number(:cluster_rest_seconds)
    |> validate_optional_number(:rest_pause_seconds)
    |> validate_optional_number(:pacing)
    |> validate_optional_number(:interval_assignment)
    |> foreign_key_constraint(:workout_section_id)
    |> cast_assoc(:variations, with: &ExerciseVariation.changeset/2)
  end

  defp validate_optional_number(changeset, field) do
    validate_number(changeset, field, greater_than_or_equal_to: 1)
  end

  defp normalize_name(nil), do: nil
  defp normalize_name(name), do: String.trim(name)
end
