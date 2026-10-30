defmodule Palee.Payments.SavedMethod do
  @moduledoc """
  A card the payer saved for later charges (ADR-247): the provider's token
  (encrypted), what the provider tells us to show (brand, last 4, expiry)
  and the payer's consent. Never card data.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(account_id user_id provider token token_digest brand last4 exp_month exp_year status
             autopay consent_version consent_text_hash consented_at consent_ip consent_user_agent
             max_amount_cents currency revoked_at revoked_by_id)a

  schema "payment_methods" do
    field :organization_id, :binary_id, read_after_writes: true
    field :account_id, :binary_id
    field :user_id, :binary_id
    field :provider, :string
    field :token, EncryptedBinary, redact: true
    field :token_digest, :string
    field :brand, :string
    field :last4, :string
    field :exp_month, :integer
    field :exp_year, :integer
    field :status, :string, default: "active"
    field :autopay, :boolean, default: false
    field :consent_version, :string
    field :consent_text_hash, :string
    field :consented_at, :utc_datetime_usec
    field :consent_ip, :string
    field :consent_user_agent, :string
    field :max_amount_cents, :integer
    field :currency, :string
    field :revoked_at, :utc_datetime_usec
    field :revoked_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(method, attrs) do
    method
    |> cast(attrs, @fields)
    |> validate_required(~w(account_id user_id provider token token_digest status consent_version
                            consent_text_hash consented_at max_amount_cents currency)a)
    |> unique_constraint([:account_id, :token_digest])
    |> check_constraint(:status, name: :payment_methods_check)
  end
end
