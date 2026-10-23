defmodule Palee.Interests.AccountInterests do
  @moduledoc "One account's disciplines and level (ADR-183); one row per account."

  use Ecto.Schema

  @primary_key {:user_id, :binary_id, autogenerate: false}

  @type t :: %__MODULE__{}

  schema "account_interests" do
    field :disciplines, {:array, :string}, default: []
    field :level, :string

    timestamps(type: :utc_datetime_usec)
  end
end
