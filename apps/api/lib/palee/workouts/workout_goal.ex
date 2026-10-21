defmodule Palee.Workouts.WorkoutGoal do
  @moduledoc """
  The coach's goals for one master workout (ADR-163): target muscles with
  roles, fitness qualities, a stimulus line and whether members see them.
  Values arrive already normalised by `Anatomy.Domain.GoalSet`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @sources ~w(suggested edited)

  schema "workout_goals" do
    field(:organization_id, :binary_id)
    field(:master_workout_id, :binary_id)
    field(:muscles, {:array, :map}, default: [])
    field(:qualities, {:array, :string}, default: [])
    field(:stimulus, :string)
    field(:visible_to_members, :boolean, default: false)
    field(:source, :string, default: "suggested")
    field(:taxonomy_version, :integer)
    field(:updated_by_id, :binary_id)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(muscles qualities stimulus visible_to_members source taxonomy_version updated_by_id)a

  def changeset(%__MODULE__{} = goal, attrs) do
    goal
    |> cast(attrs, [:master_workout_id | @fields])
    |> validate_required([:master_workout_id, :source, :taxonomy_version])
    |> validate_inclusion(:source, @sources)
    |> validate_length(:stimulus, max: 280)
    |> foreign_key_constraint(:master_workout_id)
    |> unique_constraint(:master_workout_id)
  end
end
