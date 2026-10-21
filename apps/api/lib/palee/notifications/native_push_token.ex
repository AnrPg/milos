defmodule Palee.Notifications.NativePushToken do
  @moduledoc "A store app install's push token (ADR-171): FCM on Android, APNs on iOS."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @providers ~w(fcm apns)
  @platforms ~w(android ios)
  @apns_environments ~w(production sandbox)

  schema "native_push_tokens" do
    field :user_id, :binary_id
    field :provider, :string
    field :platform, :string
    field :token, :string
    field :app_id, :string
    field :app_version, :string
    field :apns_environment, :string
    field :last_registered_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def providers, do: @providers

  def changeset(token \\ %__MODULE__{}, params) do
    token
    |> cast(params, [
      :user_id,
      :provider,
      :platform,
      :token,
      :app_id,
      :app_version,
      :apns_environment,
      :last_registered_at
    ])
    |> validate_required([:user_id, :provider, :platform, :token, :last_registered_at])
    |> validate_inclusion(:provider, @providers)
    |> validate_inclusion(:platform, @platforms)
    |> validate_inclusion(:apns_environment, @apns_environments)
    |> validate_length(:token, min: 16, max: 4096)
    |> validate_length(:app_id, max: 255)
    |> validate_length(:app_version, max: 64)
    |> check_constraint(:provider, name: :native_push_tokens_provider_check)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:provider, :token], name: :native_push_tokens_provider_token_index)
  end
end
