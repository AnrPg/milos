defmodule Palee.Wellbeing.InjuryAccessEntry do
  @moduledoc "Staff of a gym read a member's injury reports (ADR-286, ADR-158 pattern)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "injury_access_log" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :reader_user_id, :binary_id
    field :surface, :string
    field :injury_ids, {:array, :binary_id}, default: []
    field :read_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
