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
      :workout_exercise_id,
      :scale_level_id,
      :exercise_name_override,
      :sets,
      :prescription_value,
      :prescription_unit,
      :load_value,
      :load_mode,
      :excluded
    ])
    |> update_change(:exercise_name_override, &normalize_string/1)
    |> validate_required([:scale_level_id])
    |> validate_optional_number(:sets)
    |> validate_optional_number(:prescription_value)
    |> validate_optional_number(:load_value)
    |> validate_override_or_excluded()
    |> foreign_key_constraint(:workout_exercise_id)
    |> foreign_key_constraint(:scale_level_id)
    |> unique_constraint([:workout_exercise_id, :scale_level_id])
  end

  defp validate_optional_number(changeset, field) do
    validate_number(changeset, field, greater_than_or_equal_to: 1)
  end

  defp validate_override_or_excluded(changeset) do
    if get_field(changeset, :excluded) do
      changeset
    else
      validate_at_least_one_override(changeset)
    end
  end

  defp validate_at_least_one_override(changeset) do
    fields = [:exercise_name_override, :sets, :prescription_value, :load_value]

    if Enum.all?(fields, &(get_field(changeset, &1) |> blank?())) do
      add_error(
        changeset,
        :scale_level_id,
        "variation must override at least one field or be excluded"
      )
    else
      changeset
    end
  end

  defp normalize_string(nil), do: nil
  defp normalize_string(value), do: String.trim(value)

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
