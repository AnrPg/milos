defmodule Palee.Fiscal.Sequence do
  @moduledoc "Gapless sequence of a document series (ADR-241), locked `FOR UPDATE` when used."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "fiscal_sequences" do
    field :organization_id, :binary_id, read_after_writes: true
    field :series, :string
    field :last_value, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end
end
