defmodule MilosTraining.Workouts.MasterWorkout do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Workouts.WorkoutSection
  alias MilosTraining.Workouts.Domain.WorkoutAuthoringMetadata

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @types MilosTraining.Workouts.Domain.WorkoutType.values()
  @statuses [:draft, :published]

  schema "master_workouts" do
    field :title, :string
    field :type, Ecto.Enum, values: @types
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :draft_data, :map
    field :created_by_id, :binary_id
    field :is_team_workout, :boolean, default: false
    field :subtitle, :string
    field :description, :string
    field :difficulty, :string
    field :estimated_duration_seconds, :integer
    field :equipment, {:array, :string}, default: []
    field :tags, {:array, :string}, default: []
    field :notes, {:array, :map}, default: []
    field :workout_metadata, :map, default: %{}

    has_many :sections, WorkoutSection, preload_order: [asc: :order]

    timestamps()
  end

  def draft_changeset(workout \\ %__MODULE__{}, params) do
    workout
    |> cast(params, authoring_fields() ++ [:created_by_id, :draft_data, :status])
    |> validate_required([:created_by_id])
    |> foreign_key_constraint(:created_by_id)
  end

  def update_draft_changeset(workout, params) do
    workout
    |> cast(params, authoring_fields() ++ [:draft_data])
  end

  def publish_changeset(workout, params) do
    workout
    |> cast(params, authoring_fields() ++ [:status])
    |> validate_required([:title, :type])
    |> validate_authoring_fields()
    |> put_change(:status, :published)
    |> put_change(:draft_data, nil)
  end

  def create_changeset(workout \\ %__MODULE__{}, params) do
    workout
    |> cast(params, authoring_fields() ++ [:created_by_id])
    |> validate_required([:title, :type, :created_by_id])
    |> validate_authoring_fields()
    |> put_change(:status, :published)
    |> foreign_key_constraint(:created_by_id)
    |> cast_assoc(:sections, required: true, with: &WorkoutSection.changeset/2)
  end

  def types, do: @types
  def statuses, do: @statuses

  defp authoring_fields do
    [
      :title,
      :type,
      :is_team_workout,
      :subtitle,
      :description,
      :difficulty,
      :estimated_duration_seconds,
      :equipment,
      :tags,
      :notes,
      :workout_metadata
    ]
  end

  defp validate_authoring_fields(changeset) do
    changeset
    |> validate_length(:title, min: 3, max: 160)
    |> validate_length(:subtitle, max: 240)
    |> validate_length(:description, max: 10_000)
    |> validate_inclusion(:difficulty, ["beginner", "intermediate", "advanced", "all-levels"])
    |> validate_number(:estimated_duration_seconds,
      greater_than: 0,
      less_than_or_equal_to: 86_400
    )
    |> validate_bounded_map(:workout_metadata, :workout)
    |> validate_typed_notes()
  end

  defp validate_bounded_map(changeset, field, scope) do
    validate_change(changeset, field, fn ^field, value ->
      case WorkoutAuthoringMetadata.validate(scope, value) do
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
