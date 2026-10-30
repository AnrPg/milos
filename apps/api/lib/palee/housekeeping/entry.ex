defmodule Palee.Housekeeping.Entry do
  @moduledoc "One cleaning of an area by one person (ADR-102)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "housekeeping_entries" do
    field :organization_id, :binary_id, read_after_writes: true
    field :area_id, :binary_id
    field :user_id, :binary_id
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :tasks_done, {:array, :string}, default: []
    field :note, :string
    # ADR-290: what was answered for each point of the room's visual
    # checklist: point_id, instruction and media_id (as they were), status
    # ("cleaned" | "not_cleaned"), note, after_media_id. A jsonb array.
    field :point_results, {:array, :map}, default: []

    timestamps(type: :utc_datetime_usec)
  end

  def start_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :area_id, :user_id, :started_at])
    |> validate_required([:area_id, :user_id, :started_at])
  end

  def finish_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:finished_at, :tasks_done, :note, :point_results])
    |> validate_required([:finished_at])
    |> validate_length(:note, max: 1_000)
  end
end
