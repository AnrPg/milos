defmodule Palee.Execution.ClassTimer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @statuses ~w(ready running paused finished)

  schema "class_timers" do
    field(:organization_id, :binary_id)
    field(:scheduled_class_id, :binary_id)
    field(:status, :string, default: "ready")
    field(:current_segment_index, :integer, default: 0)
    field(:segment_started_at_utc, :utc_datetime_usec)
    field(:paused_elapsed_ms, :integer, default: 0)
    field(:duration_adjustments, :map, default: %{})
    field(:timer_preset, :map)
    field(:controlled_by_id, :binary_id)
    field(:lock_version, :integer, default: 1)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(timer \\ %__MODULE__{}, params) do
    timer
    |> cast(params, [
      :organization_id,
      :scheduled_class_id,
      :status,
      :current_segment_index,
      :segment_started_at_utc,
      :paused_elapsed_ms,
      :duration_adjustments,
      :timer_preset,
      :controlled_by_id
    ])
    |> validate_required([:organization_id, :scheduled_class_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:current_segment_index, greater_than_or_equal_to: 0)
    |> validate_number(:paused_elapsed_ms, greater_than_or_equal_to: 0)
    |> unique_constraint(:scheduled_class_id)
    |> optimistic_lock(:lock_version)
  end
end
