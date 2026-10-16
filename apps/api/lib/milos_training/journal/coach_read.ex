defmodule MilosTraining.Journal.CoachRead do
  @moduledoc "A coach was shown one of a member's journal entries (ADR-139, ADR-101 pattern)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "journal_coach_reads" do
    field(:organization_id, :binary_id, read_after_writes: true)
    field(:reader_user_id, :binary_id)
    field(:owner_user_id, :binary_id)
    field(:entry_kind, :string)
    field(:entry_id, :binary_id)
    field(:read_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
