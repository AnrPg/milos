defmodule MilosTraining.Journal.EntryAudience do
  @moduledoc "One coach an entry's own audience names (ADR-162)."

  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id

  schema "journal_entry_audiences" do
    field(:entry_kind, :string, primary_key: true)
    field(:entry_id, :binary_id, primary_key: true)
    field(:organization_id, :binary_id, primary_key: true)
    field(:coach_user_id, :binary_id, primary_key: true)
    field(:user_id, :binary_id)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
