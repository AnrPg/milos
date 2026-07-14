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
    field :is_team_workout, :boolean, default: false

    has_many :sections, WorkoutSection, preload_order: [asc: :order]

    timestamps()
  end

  def draft_changeset(workout \\ %__MODULE__{}, params) do
    workout
    |> cast(params, [:title, :type, :created_by_id, :draft_data, :status, :is_team_workout])
    |> validate_required([:created_by_id])
    |> foreign_key_constraint(:created_by_id)
  end

  def update_draft_changeset(workout, params) do
    workout
    |> cast(params, [:title, :type, :draft_data, :is_team_workout])
  end

  def publish_changeset(workout, params) do
    workout
    |> cast(params, [:title, :type, :status, :is_team_workout])
    |> validate_required([:title, :type])
    |> validate_length(:title, min: 3, max: 160)
    |> put_change(:status, :published)
    |> put_change(:draft_data, nil)
  end

  def create_changeset(workout \\ %__MODULE__{}, params) do
    workout
    |> cast(params, [:title, :type, :created_by_id, :is_team_workout])
    |> validate_required([:title, :type, :created_by_id])
    |> validate_length(:title, min: 3, max: 160)
    |> put_change(:status, :published)
    |> foreign_key_constraint(:created_by_id)
    |> cast_assoc(:sections, required: true, with: &WorkoutSection.changeset/2)
  end

  def types, do: @types
  def statuses, do: @statuses
end
