defmodule Palee.Payments.Intent do
  @moduledoc """
  One attempt to take money online (ADR-246): a checkout the payer
  completes on the provider's page (`initiation: "payer"`) or a charge of a
  saved card (`"merchant"`). Also the outbox row for settling, retrying and
  fulfilling the payment.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(account_id provider environment user_id initiation purpose_type purpose_id
             amount_cents currency description status idempotency_key provider_ref
             provider_transaction_id redirect_url return_url save_method consent payment_method_id
             attempts next_attempt_at claimed_at expires_at succeeded_at failure_code
             failure_message card_brand card_last4 refunded_cents fulfilment_status
             fulfilment_attempts fulfilment_error fulfilled_at finance_payment_id
             fiscal_document_id created_by_id metadata attention_resolved_at
             attention_resolved_by_id attention_resolution tip_cents surcharge_cents)a

  schema "payment_intents" do
    field :organization_id, :binary_id, read_after_writes: true
    field :account_id, :binary_id
    field :provider, :string
    field :environment, :string
    field :user_id, :binary_id
    field :initiation, :string
    field :purpose_type, :string
    field :purpose_id, :binary_id
    field :amount_cents, :integer
    field :currency, :string
    field :description, :string
    field :status, :string
    field :idempotency_key, :string
    field :provider_ref, :string
    field :provider_transaction_id, :string
    field :redirect_url, :string
    field :return_url, :string
    field :save_method, :boolean, default: false
    field :consent, :map
    # ADR-248: what else the payment is for (e.g. the class to book after it).
    field :metadata, :map, default: %{}
    field :attention_resolved_at, :utc_datetime_usec
    field :attention_resolved_by_id, :binary_id
    field :attention_resolution, :string
    field :payment_method_id, :binary_id
    field :attempts, :integer, default: 0
    field :next_attempt_at, :utc_datetime_usec
    field :claimed_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :succeeded_at, :utc_datetime_usec
    field :failure_code, :string
    field :failure_message, :string
    field :card_brand, :string
    field :card_last4, :string
    field :refunded_cents, :integer, default: 0
    field :fulfilment_status, :string, default: "none"
    field :fulfilment_attempts, :integer, default: 0
    field :fulfilment_error, :string
    field :fulfilled_at, :utc_datetime_usec
    field :finance_payment_id, :binary_id
    field :fiscal_document_id, :binary_id
    field :created_by_id, :binary_id
    # ADR-264: confirmed by the provider on top of `amount_cents` (a terminal sale).
    field :tip_cents, :integer, default: 0
    field :surcharge_cents, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(intent, attrs) do
    intent
    |> cast(attrs, @fields)
    |> validate_required(~w(account_id provider environment initiation purpose_type purpose_id
                            amount_cents currency description status idempotency_key)a)
    |> unique_constraint([:organization_id, :idempotency_key])
    |> unique_constraint([:provider, :provider_ref], name: :payment_intents_provider_ref_index)
    |> check_constraint(:status, name: :payment_intents_check)
  end
end
