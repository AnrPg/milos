defmodule Palee.Fiscal.JournalHead do
  @moduledoc "The last entry of an organization's fiscal journal (ADR-242), locked to append."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "fiscal_journal_heads" do
    field :organization_id, :binary_id, read_after_writes: true
    field :position, :integer, default: 0
    field :hash, :string

    timestamps(type: :utc_datetime_usec)
  end
end
