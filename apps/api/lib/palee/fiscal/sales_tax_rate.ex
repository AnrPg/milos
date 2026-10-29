defmodule Palee.Fiscal.SalesTaxRate do
  @moduledoc "A US sales tax rate the gym keeps for a state or a ZIP code (ADR-244)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fiscal_sales_tax_rates" do
    field :organization_id, :binary_id, read_after_writes: true
    field :state, :string
    field :zip, :string
    field :rate_bp, :integer
    field :label, :string
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:state, :zip, :rate_bp, :label, :updated_by_id])
    |> validate_required([:state, :rate_bp])
    |> check_constraint(:rate_bp, name: :fiscal_sales_tax_rates_check)
    |> unique_constraint([:state, :zip], name: :fiscal_sales_tax_rates_place_index)
  end
end
