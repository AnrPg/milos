defmodule MilosTraining.Identity.SavedFilter do
  @moduledoc "A remembered or named filter of one list surface (ADR-151)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "saved_filters" do
    field :user_id, :binary_id
    field :surface, :string
    field :kind, :string
    field :name, :string
    field :params, :map, default: %{}
    field :last_used_at, :utc_datetime_usec
    # ADR-154: an opt-in daily alert of a named Γύρω μου filter.
    field :alert_enabled, :boolean, default: false
    field :alert_checked_on, :date
    field :alert_checked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
