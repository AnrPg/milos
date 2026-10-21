defmodule Palee.Buddies.WellnessAccessEntry do
  @moduledoc "A coach read a member's weekly wellness summary (ADR-160 §4, ADR-158 pattern)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "wellness_access_log" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :reader_user_id, :binary_id
    field :week_start, :date
    field :shared, :boolean, default: false
    field :cravings_shown, :boolean, default: false
    field :read_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
