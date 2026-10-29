defmodule Palee.Fiscal.AuthorityConnection do
  @moduledoc """
  An organization's connection to its tax authority (ADR-243): the
  environment and, outside the sandbox, the business's own credentials.
  The subscription key is encrypted at rest and never returned by the API.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(authority environment user_id subscription_key status last_error updated_by_id
             error_code checked_at next_check_at check_failures updated_by_platform)a

  schema "fiscal_authority_connections" do
    field :organization_id, :binary_id, read_after_writes: true
    field :authority, :string
    field :environment, :string
    field :user_id, :string
    field :subscription_key, EncryptedBinary, redact: true
    field :status, :string, default: "active"
    field :last_error, :string
    field :updated_by_id, :binary_id
    # ADR-273: the last «Δοκιμή σύνδεσης».
    field :error_code, :string
    field :checked_at, :utc_datetime_usec
    field :next_check_at, :utc_datetime_usec
    field :check_failures, :integer, default: 0
    field :updated_by_platform, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, @fields)
    |> validate_required([:authority, :environment, :status])
    |> unique_constraint([:organization_id, :authority])
    |> check_constraint(:environment, name: :fiscal_authority_connections_check)
  end
end
