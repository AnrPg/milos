defmodule Palee.Workouts.AssignedWorkout do
  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Workouts.{AssignedWorkoutAthlete, MasterWorkout}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "assigned_workouts" do
    field :organization_id, :binary_id
    field :scheduled_for, :date
    field :instructions, :string
    # ADR-125: set when the assignment is a per-member variant of a class
    # occurrence (loose reference to a Scheduling-owned scheduled class).
    field :source_scheduled_class_id, :binary_id
    # ADR-167: set when the assignment is part of a season's programme (loose
    # reference to a Seasons-owned offering); members see the season's name.
    field :season_offering_id, :binary_id

    belongs_to :master_workout, MasterWorkout
    has_many :athlete_links, AssignedWorkoutAthlete

    timestamps(updated_at: false)
  end

  def changeset(assignment \\ %__MODULE__{}, params) do
    assignment
    |> cast(params, [
      :organization_id,
      :master_workout_id,
      :scheduled_for,
      :instructions,
      :source_scheduled_class_id,
      :season_offering_id
    ])
    |> update_change(:instructions, &normalize_instructions/1)
    |> validate_required([:organization_id, :master_workout_id, :scheduled_for])
    |> foreign_key_constraint(:master_workout_id)
    |> unique_constraint([:master_workout_id, :scheduled_for, :instructions],
      name: :assigned_workouts_workout_date_notes_index
    )
  end

  def update_changeset(assignment, params) do
    assignment
    |> cast(params, [:scheduled_for, :instructions])
    |> update_change(:instructions, &normalize_instructions/1)
    |> validate_required([:scheduled_for])
    |> unique_constraint([:master_workout_id, :scheduled_for, :instructions],
      name: :assigned_workouts_workout_date_notes_index
    )
  end

  defp normalize_instructions(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_instructions(value), do: value
end
