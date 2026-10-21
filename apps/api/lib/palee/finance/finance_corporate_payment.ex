defmodule Palee.Finance.FinanceCorporatePayment do
  @moduledoc "A payment a corporate client made against one of its invoices (ADR-098)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @payment_methods ["cash", "bank_transfer", "card_manual", "other"]

  schema "finance_corporate_payments" do
    field :organization_id, :binary_id, read_after_writes: true
    field :corporate_invoice_id, :binary_id
    field :amount_cents, :integer
    field :payment_method, :string
    field :paid_on, :date
    field :reference, :string
    field :notes, :string
    field :recorded_by_id, :binary_id
    field :reversed_at, :utc_datetime_usec
    field :reversed_by_id, :binary_id
    field :reversal_reason, :string

    timestamps(type: :utc_datetime_usec)
  end

  def payment_methods, do: @payment_methods

  def changeset(params) do
    %__MODULE__{}
    |> cast(params, [
      :corporate_invoice_id,
      :amount_cents,
      :payment_method,
      :paid_on,
      :reference,
      :notes,
      :recorded_by_id
    ])
    |> validate_required([:corporate_invoice_id, :amount_cents, :payment_method, :paid_on])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_inclusion(:payment_method, @payment_methods)
    |> validate_length(:reference, max: 120)
    |> validate_length(:notes, max: 1_000)
  end

  def reverse_changeset(payment, admin_id, reason, at) do
    payment
    |> change(reversed_at: at, reversed_by_id: admin_id, reversal_reason: reason)
    |> validate_length(:reversal_reason, max: 500)
  end
end
