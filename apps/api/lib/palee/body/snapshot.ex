defmodule Palee.Body.Snapshot do
  @moduledoc "A body measurement snapshot (ADR-158); `metrics` in SI units."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Body.Domain.SnapshotPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "body_snapshots" do
    field :user_id, :binary_id
    field :taken_at, :utc_datetime_usec
    field :taken_tz, :string, default: "UTC"
    field :metrics, :map, default: %{}
    field :notes, :string
    field :visibility, :string, default: "private"
    field :source, :string, default: "manual"

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(taken_at taken_tz metrics notes visibility source)a

  def changeset(snapshot \\ %__MODULE__{}, attrs) do
    snapshot
    |> cast(attrs, [:id, :user_id | @fields])
    |> validate_required([:user_id, :taken_at, :taken_tz, :visibility])
    |> validate_inclusion(:visibility, SnapshotPolicy.visibilities())
    |> validate_length(:notes, max: SnapshotPolicy.max_notes())
    |> validate_inclusion(:source, SnapshotPolicy.sources())
    |> check_constraint(:visibility, name: :body_snapshots_visibility_check)
  end
end
