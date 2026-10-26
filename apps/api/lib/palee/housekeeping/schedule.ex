defmodule Palee.Housekeeping.Schedule do
  @moduledoc "When a space should be cleaned: weekdays, times of day and a comment (ADR-202)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "housekeeping_schedules" do
    field :organization_id, :binary_id, read_after_writes: true
    field :space_id, :binary_id
    field :weekdays, {:array, :integer}, default: []
    field :times, {:array, :time}, default: []
    field :comment, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(schedule \\ %__MODULE__{}, attrs) do
    schedule
    |> cast(attrs, [:organization_id, :space_id, :weekdays, :times, :comment])
    |> validate_required([:space_id, :weekdays])
    |> unique_constraint(:space_id)
    |> foreign_key_constraint(:space_id, name: :housekeeping_schedules_space_fkey)
  end
end
