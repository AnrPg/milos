defmodule MilosTraining.Workouts.MasterWorkout do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Workouts.WorkoutSection
  alias MilosTraining.Workouts.WorkoutFolder
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
    field :source_workout_id, :binary_id
    field :is_team_workout, :boolean, default: false
    field :subtitle, :string
    field :description, :string
    field :difficulty, :string
    field :estimated_duration_seconds, :integer
    field :equipment, {:array, :string}, default: []
    field :tags, {:array, :string}, default: []
    field :notes, {:array, :map}, default: []
    field :workout_metadata, :map, default: %{}
    field :authoring_mode, :string, default: "structured"
    field :dsl_version, :integer
    field :dsl_source, :string
    field :dsl_document, :map
    field :dsl_source_revision, :integer, default: 0
    field :last_dsl_diagnostics, {:array, :map}, default: []
    field :free_text_body, :string
    field :free_text_document, :map

    has_many :sections, WorkoutSection, preload_order: [asc: :order]
    belongs_to :folder, WorkoutFolder

    timestamps()
  end

  def draft_changeset(workout \\ %__MODULE__{}, params) do
    workout
    |> cast(
      params,
      authoring_fields() ++ [:created_by_id, :folder_id, :source_workout_id, :draft_data, :status]
    )
    |> validate_required([:created_by_id])
    |> validate_authoring_fields()
    |> foreign_key_constraint(:created_by_id)
  end

  def update_draft_changeset(workout, params) do
    workout
    |> cast(params, authoring_fields() ++ [:draft_data])
    |> validate_authoring_fields()
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
    |> cast(params, authoring_fields() ++ [:created_by_id, :folder_id, :source_workout_id])
    |> validate_required([:title, :type, :created_by_id])
    |> validate_authoring_fields()
    |> put_change(:status, :published)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:folder_id)
    |> foreign_key_constraint(:source_workout_id)
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
      :workout_metadata,
      :authoring_mode,
      :dsl_version,
      :dsl_source,
      :dsl_document,
      :last_dsl_diagnostics,
      :free_text_body,
      :free_text_document
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
    |> validate_inclusion(:authoring_mode, ["structured", "quick_text", "free_text"])
    |> validate_inclusion(:dsl_version, [1])
    |> validate_length(:dsl_source, max: 200_000)
    |> validate_length(:free_text_body, max: 200_000)
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
