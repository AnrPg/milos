defmodule MilosTraining.Workouts.WorkoutExercise do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Workouts.Domain.WorkoutAuthoringMetadata
  alias MilosTraining.Workouts.{ExerciseVariation, WorkoutSection}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @prescription_units [:reps, :secs, :kcal, :meters]
  @load_modes [:absolute, :pct_1rm, :bw]
  @item_types [:exercise, :header]

  schema "workout_exercises" do
    field :organization_id, :binary_id
    field :name, :string
    field :item_type, Ecto.Enum, values: @item_types, default: :exercise
    field :sets, :integer
    field :set_prescriptions, {:array, :map}, default: []
    field :prescription_value, :integer
    field :prescription_unit, Ecto.Enum, values: @prescription_units
    field :load_value, :integer
    field :load_mode, Ecto.Enum, values: @load_modes
    field :load_progression, :map
    field :order, :integer
    field :superset_group_id, :binary_id
    field :alternating_group_id, :binary_id
    field :hr_zone, :integer
    field :tempo, :string
    field :rest_seconds, :integer
    field :cluster_rest_seconds, :integer
    field :rest_pause_seconds, :integer
    field :pacing, :integer
    field :interval_assignment, :integer
    field :note, :string
    field :subtitle, :string
    field :exercise_ref, :string
    field :notes, {:array, :map}, default: []
    field :prescription_metadata, :map, default: %{}
    field :group_config, :map

    belongs_to :workout_section, WorkoutSection
    has_many :variations, ExerciseVariation

    timestamps()
  end

  def changeset(exercise \\ %__MODULE__{}, params) do
    exercise
    |> cast(params, [
      :workout_section_id,
      :name,
      :item_type,
      :sets,
      :set_prescriptions,
      :prescription_value,
      :prescription_unit,
      :load_value,
      :load_mode,
      :load_progression,
      :order,
      :superset_group_id,
      :alternating_group_id,
      :hr_zone,
      :tempo,
      :rest_seconds,
      :cluster_rest_seconds,
      :rest_pause_seconds,
      :pacing,
      :interval_assignment,
      :note,
      :subtitle,
      :exercise_ref,
      :notes,
      :prescription_metadata,
      :group_config
    ])
    |> update_change(:name, &normalize_name/1)
    |> validate_required([:name, :order])
    |> validate_number(:order, greater_than_or_equal_to: 1)
    |> validate_length(:subtitle, max: 240)
    |> validate_length(:exercise_ref, max: 120)
    |> validate_optional_number(:sets, 1)
    |> validate_optional_number(:prescription_value, 1)
    |> validate_optional_number(:load_value, 0)
    |> validate_optional_number(:hr_zone, 1)
    |> validate_optional_number(:rest_seconds, 0)
    |> validate_optional_number(:cluster_rest_seconds, 0)
    |> validate_optional_number(:rest_pause_seconds, 0)
    |> validate_optional_number(:pacing, 0)
    |> validate_optional_number(:interval_assignment, 0)
    |> validate_bounded_metadata(:prescription_metadata, :exercise)
    |> validate_optional_bounded_metadata(:group_config, :group)
    |> validate_typed_notes()
    |> validate_item_groups()
    |> foreign_key_constraint(:workout_section_id)
    |> cast_assoc(:variations, with: &ExerciseVariation.changeset/2)
  end

  defp validate_optional_number(changeset, field, min) do
    validate_number(changeset, field, greater_than_or_equal_to: min)
  end

  defp normalize_name(nil), do: nil
  defp normalize_name(name), do: String.trim(name)

  defp validate_item_groups(changeset) do
    item_type = get_field(changeset, :item_type)
    superset_group_id = get_field(changeset, :superset_group_id)
    alternating_group_id = get_field(changeset, :alternating_group_id)

    cond do
      item_type == :header and (superset_group_id || alternating_group_id) ->
        add_error(changeset, :item_type, "headers cannot belong to a set group")

      superset_group_id && alternating_group_id ->
        add_error(
          changeset,
          :alternating_group_id,
          "cannot combine superset and alternating groups"
        )

      true ->
        changeset
    end
  end

  defp validate_bounded_metadata(changeset, field, scope) do
    validate_change(changeset, field, fn ^field, metadata ->
      case WorkoutAuthoringMetadata.validate(scope, metadata) do
        :ok -> []
        {:error, reason} -> [{field, "is invalid: #{inspect(reason)}"}]
      end
    end)
  end

  defp validate_optional_bounded_metadata(changeset, field, scope) do
    validate_change(changeset, field, fn
      ^field, nil ->
        []

      ^field, metadata ->
        case WorkoutAuthoringMetadata.validate(scope, metadata) do
          :ok -> []
          {:error, reason} -> [{field, "is invalid: #{inspect(reason)}"}]
        end
    end)
  end

  defp validate_typed_notes(changeset) do
    validate_change(changeset, :notes, fn :notes, notes ->
      case WorkoutAuthoringMetadata.validate_notes(notes) do
        :ok -> []
        {:error, reason} -> [notes: "are invalid: #{inspect(reason)}"]
      end
    end)
  end
end
