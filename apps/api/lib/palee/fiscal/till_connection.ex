defmodule Palee.Fiscal.TillConnection do
  @moduledoc """
  An organization's cash-register security device (ADR-251): the
  provider, environment, the cloud unit (TSS / signature creation unit)
  and register (client / cash register), and outside the sandbox the
  credentials. API key, secret and admin PIN are encrypted at rest and
  never returned, journaled or logged.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(device provider environment api_key api_secret admin_pin unit_id register_id
             unit_serial register_serial public_key provisioned_at status last_error
             updated_by_id)a

  schema "fiscal_till_connections" do
    field :organization_id, :binary_id, read_after_writes: true
    field :device, :string
    field :provider, :string
    field :environment, :string
    field :api_key, EncryptedBinary, redact: true
    field :api_secret, EncryptedBinary, redact: true
    field :admin_pin, EncryptedBinary, redact: true
    field :unit_id, :binary_id
    field :register_id, :binary_id
    field :unit_serial, :string
    field :register_serial, :string
    field :public_key, :string
    field :provisioned_at, :utc_datetime_usec
    field :status, :string, default: "provisioning"
    field :last_error, :string
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, @fields)
    |> validate_required([:device, :provider, :environment, :unit_id, :register_id, :status])
    |> unique_constraint([:organization_id, :device])
    |> check_constraint(:environment, name: :fiscal_till_connections_check)
  end
end
