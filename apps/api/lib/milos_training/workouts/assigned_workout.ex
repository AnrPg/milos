defmodule MilosTraining.Workouts.AssignedWorkout do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Workouts.{AssignedWorkoutAthlete, MasterWorkout}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "assigned_workouts" do
    field :scheduled_for, :date
    field :admin_notes, :string

    belongs_to :master_workout, MasterWorkout
    has_many :athlete_links, AssignedWorkoutAthlete

    timestamps(updated_at: false)
  end

  def changeset(assignment \\ %__MODULE__{}, params) do
    assignment
    |> cast(params, [:master_workout_id, :scheduled_for, :admin_notes])
    |> update_change(:admin_notes, &normalize_admin_notes/1)
    |> validate_required([:master_workout_id, :scheduled_for])
    |> foreign_key_constraint(:master_workout_id)
    |> unique_constraint([:master_workout_id, :scheduled_for, :admin_notes],
      name: :assigned_workouts_workout_date_notes_index
    )
  end

  def update_changeset(assignment, params) do
    assignment
    |> cast(params, [:scheduled_for, :admin_notes])
    |> update_change(:admin_notes, &normalize_admin_notes/1)
    |> validate_required([:scheduled_for])
    |> unique_constraint([:master_workout_id, :scheduled_for, :admin_notes],
      name: :assigned_workouts_workout_date_notes_index
    )
  end

  defp normalize_admin_notes(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_admin_notes(value), do: value
end
