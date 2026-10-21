defmodule Palee.Finance.FinanceDocumentCounter do
  @moduledoc """
  Per-tenant, per-document-type sequence (ADR-126). The row is locked
  `FOR UPDATE` in the transaction that issues the numbered document, so a
  rollback also rolls the counter back and numbers have no gaps.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @document_types ["refund_receipt"]

  schema "finance_document_counters" do
    field :organization_id, :binary_id, read_after_writes: true
    field :document_type, :string
    field :last_value, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def document_types, do: @document_types

  def changeset(counter \\ %__MODULE__{}, params) do
    counter
    |> cast(params, [:document_type, :last_value])
    |> validate_required([:document_type, :last_value])
    |> validate_inclusion(:document_type, @document_types)
    |> validate_number(:last_value, greater_than_or_equal_to: 0)
    |> unique_constraint([:organization_id, :document_type],
      name: :finance_document_counters_organization_type_index
    )
  end
end
