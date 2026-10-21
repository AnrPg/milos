defmodule Palee.Body.AccessLogEntry do
  @moduledoc "A coach read a member's shared body snapshots (ADR-158, ADR-101 pattern)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "body_access_log" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :reader_user_id, :binary_id
    field :subject, :string
    field :snapshot_ids, {:array, :binary_id}, default: []
    field :photos_shown, :boolean, default: false
    field :read_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
