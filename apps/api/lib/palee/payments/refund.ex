defmodule Palee.Payments.Refund do
  @moduledoc "Money given back through the provider for a succeeded intent (ADR-247)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(intent_id amount_cents currency status reason idempotency_key provider_ref
             failure_message finance_reversal_id created_by_id completed_at)a

  schema "payment_refunds" do
    field :organization_id, :binary_id, read_after_writes: true
    field :intent_id, :binary_id
    field :amount_cents, :integer
    field :currency, :string
    field :status, :string, default: "pending"
    field :reason, :string
    field :idempotency_key, :string
    field :provider_ref, :string
    field :failure_message, :string
    field :finance_reversal_id, :binary_id
    field :created_by_id, :binary_id
    field :completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(refund, attrs) do
    refund
    |> cast(attrs, @fields)
    |> validate_required([:intent_id, :amount_cents, :currency, :status, :idempotency_key])
    |> unique_constraint([:organization_id, :idempotency_key])
    |> check_constraint(:status, name: :payment_refunds_check)
  end
end
