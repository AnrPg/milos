defmodule Palee.Fiscal.PeriodClosingRecord do
  @moduledoc "A daily, monthly or yearly closing (ADR-242). Insert-only."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(period_kind period_start period_end totals journal_position closed_at)a

  schema "fiscal_period_closings" do
    field :organization_id, :binary_id, read_after_writes: true
    field :period_kind, :string
    field :period_start, :date
    field :period_end, :date
    field :totals, :map
    field :journal_position, :integer
    field :closed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def insert_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> unique_constraint([:organization_id, :period_kind, :period_start])
  end
end
