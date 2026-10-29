defmodule Palee.Fiscal.DocumentLine do
  @moduledoc "A line of a fiscal document (ADR-241). Insert-only."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @fields ~w(document_id position description quantity unit_price_cents discount_cents
             amount_cents tax_category rate_bp exemption_reason net_cents tax_cents gross_cents
             corrects_position source_type source_id)a

  schema "fiscal_document_lines" do
    field :organization_id, :binary_id, read_after_writes: true
    field :document_id, :binary_id
    field :position, :integer
    field :description, :string
    field :quantity, :integer
    field :unit_price_cents, :integer
    field :discount_cents, :integer, default: 0
    field :amount_cents, :integer
    field :tax_category, :string
    field :rate_bp, :integer
    field :exemption_reason, :string
    field :net_cents, :integer
    field :tax_cents, :integer
    field :gross_cents, :integer
    field :corrects_position, :integer
    field :source_type, :string
    field :source_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def insert_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(
      ~w(document_id position description quantity unit_price_cents amount_cents tax_category
         rate_bp net_cents tax_cents gross_cents)a
    )
    |> check_constraint(:amount_cents, name: :fiscal_document_lines_amounts_check)
    |> check_constraint(:exemption_reason, name: :fiscal_document_lines_exempt_check)
  end
end
