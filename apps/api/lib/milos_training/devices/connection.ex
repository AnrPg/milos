defmodule MilosTraining.Devices.Connection do
  @moduledoc """
  A person's link to a device provider (ADR-161). Tokens and the PKCE
  verifier are encrypted at rest; the OAuth `state` is kept only as a hash.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Devices.Domain.Catalog
  alias MilosTraining.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "device_connections" do
    field :user_id, :binary_id
    field :provider, :string
    field :status, :string, default: "pending"
    field :provider_user_id, :string
    field :access_token, EncryptedBinary, redact: true
    field :refresh_token, EncryptedBinary, redact: true
    field :token_expires_at, :utc_datetime_usec
    field :refresh_token_expires_at, :utc_datetime_usec
    field :scopes, {:array, :string}, default: []
    field :sync_prefs, :map, default: Catalog.default_prefs()
    field :backfill_days, :integer, default: 30
    field :backfill_status, :string, default: "none"
    field :backfill_windows_total, :integer, default: 0
    field :backfill_windows_done, :integer, default: 0
    field :oauth_state_hash, :string, redact: true
    field :pkce_verifier, EncryptedBinary, redact: true
    field :oauth_started_at, :utc_datetime_usec
    field :connected_at, :utc_datetime_usec
    field :last_synced_at, :utc_datetime_usec
    field :last_sync_requested_at, :utc_datetime_usec
    field :last_error, :string
    field :consecutive_failures, :integer, default: 0
    field :error_notified_at, :utc_datetime_usec
    field :imports_seen_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(status provider_user_id access_token refresh_token token_expires_at
             refresh_token_expires_at scopes sync_prefs backfill_days backfill_status
             backfill_windows_total backfill_windows_done oauth_state_hash pkce_verifier
             oauth_started_at connected_at last_synced_at last_sync_requested_at last_error
             consecutive_failures error_notified_at imports_seen_at revoked_at)a

  def changeset(connection \\ %__MODULE__{}, attrs) do
    connection
    |> cast(attrs, [:user_id, :provider | @fields])
    |> validate_required([:user_id, :provider, :status])
    |> validate_inclusion(:provider, Catalog.providers())
    |> validate_inclusion(:status, Catalog.statuses())
    |> validate_inclusion(:backfill_days, Catalog.backfill_days())
    |> validate_inclusion(:backfill_status, Catalog.backfill_statuses())
    |> unique_constraint([:user_id, :provider])
    |> unique_constraint([:provider, :provider_user_id],
      name: :device_connections_provider_user_index,
      message: "is linked to another account"
    )
    |> check_constraint(:backfill_days, name: :device_connections_backfill_check)
  end
end
