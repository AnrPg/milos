defmodule Palee.Scheduling.DayWorkout do
  @moduledoc """
  A WOD for a whole gym day (ADR-224): every class of that day inherits it,
  or only the classes of one type and/or one branch. `nil` scope fields mean
  «all». The workout is the copy filed in the day's Classes folder.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "day_workouts" do
    field :organization_id, :binary_id
    field :local_date, :date
    field :class_type_id, :binary_id
    field :location_id, :binary_id
    field :master_workout_id, :binary_id
    field :set_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(rule \\ %__MODULE__{}, params) do
    rule
    |> cast(params, [
      :organization_id,
      :local_date,
      :class_type_id,
      :location_id,
      :master_workout_id,
      :set_by_id
    ])
    |> validate_required([:organization_id, :local_date, :master_workout_id])
    |> foreign_key_constraint(:master_workout_id)
    |> foreign_key_constraint(:class_type_id, name: :day_workouts_class_type_fkey)
    |> foreign_key_constraint(:location_id, name: :day_workouts_location_fkey)
    |> unique_constraint([:local_date, :class_type_id, :location_id],
      name: :day_workouts_scope_index
    )
  end
end
