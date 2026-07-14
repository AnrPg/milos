defmodule MilosTraining.Workouts.AssignedWorkoutAthlete do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Workouts.AssignedWorkout

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @athlete_statuses [:accepted, :rejected, :archived]

  schema "assigned_workout_athletes" do
    field :athlete_id, :binary_id
    field :athlete_status, Ecto.Enum, values: @athlete_statuses
    field :scheduled_for, :date

    belongs_to :assigned_workout, AssignedWorkout

    timestamps(updated_at: false)
  end

  def changeset(link \\ %__MODULE__{}, params) do
    link
    |> cast(params, [:assigned_workout_id, :athlete_id, :scheduled_for])
    |> validate_required([:assigned_workout_id, :athlete_id, :scheduled_for])
    |> foreign_key_constraint(:assigned_workout_id)
    |> foreign_key_constraint(:athlete_id)
    |> unique_constraint([:assigned_workout_id, :athlete_id])
  end

  def reject_changeset(link) do
    change(link, athlete_status: :rejected)
  end

  def archive_changeset(link) do
    change(link, athlete_status: :archived)
  end

  def reschedule_changeset(link, scheduled_for) do
    link
    |> change(scheduled_for: scheduled_for)
    |> validate_required([:scheduled_for])
  end

  def athlete_statuses, do: @athlete_statuses
end
