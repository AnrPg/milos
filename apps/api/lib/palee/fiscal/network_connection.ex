defmodule Palee.Fiscal.NetworkConnection do
  @moduledoc """
  An organization's connection to an e-invoicing network (ADR-250): the
  access point provider, environment, the business's Peppol identifier
  and, outside the sandbox, its credentials. The API key is encrypted at
  rest and never returned, journaled or logged; the webhook token is kept
  only as a SHA-256 hash.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(network provider environment peppol_scheme peppol_identifier legal_entity_id api_key
             webhook_token_hash status last_error updated_by_id)a

  schema "fiscal_network_connections" do
    field :organization_id, :binary_id, read_after_writes: true
    field :network, :string
    field :provider, :string
    field :environment, :string
    field :peppol_scheme, :string
    field :peppol_identifier, :string
    field :legal_entity_id, :string
    field :api_key, EncryptedBinary, redact: true
    field :webhook_token_hash, :string, redact: true
    field :status, :string, default: "active"
    field :last_error, :string
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, @fields)
    |> validate_required([:network, :provider, :environment, :peppol_scheme, :peppol_identifier])
    |> unique_constraint([:organization_id, :network])
    |> check_constraint(:environment, name: :fiscal_network_connections_check)
  end
end
