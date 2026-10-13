defmodule MilosTraining.Coaching.NoteRead do
  @moduledoc "Someone other than its author read a coach note (ADR-101)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "coaching_note_reads" do
    field :organization_id, :binary_id, read_after_writes: true
    field :note_id, :binary_id
    field :reader_user_id, :binary_id
    field :read_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :note_id, :reader_user_id, :read_at])
    |> validate_required([:note_id, :reader_user_id, :read_at])
  end
end
