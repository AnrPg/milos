defmodule Palee.Payments.Account do
  @moduledoc """
  A business's own account at its payment provider (ADR-246). Palee never
  holds the money: payments go straight to this account. `credentials` is a
  JSON object of the provider's secrets, encrypted at rest and never
  returned by the API.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(provider environment status settings credentials last_error checked_at updated_by_id)a

  schema "payment_accounts" do
    field :organization_id, :binary_id, read_after_writes: true
    field :provider, :string
    field :environment, :string
    field :status, :string, default: "active"
    field :settings, :map, default: %{}
    field :credentials, EncryptedBinary, redact: true
    field :last_error, :string
    field :checked_at, :utc_datetime_usec
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, @fields)
    |> validate_required([:provider, :environment, :status])
    |> unique_constraint(:organization_id)
    |> check_constraint(:provider, name: :payment_accounts_check)
  end
end
