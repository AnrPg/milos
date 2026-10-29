defmodule Palee.Fiscal.JournalEntry do
  @moduledoc "An entry of the hash-chained fiscal journal (ADR-242). Insert-only."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(position event_type subject_type subject_id actor_id occurred_at payload
             previous_hash hash signature signature_key_id)a

  schema "fiscal_journal_entries" do
    field :organization_id, :binary_id, read_after_writes: true
    field :position, :integer
    field :event_type, :string
    field :subject_type, :string
    field :subject_id, :binary_id
    field :actor_id, :binary_id
    field :occurred_at, :utc_datetime_usec
    field :payload, :map
    field :previous_hash, :string
    field :hash, :string
    field :signature, :string
    field :signature_key_id, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def insert_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(~w(position event_type occurred_at payload previous_hash hash signature
                            signature_key_id)a)
    |> unique_constraint([:organization_id, :position])
  end
end
