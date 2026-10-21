defmodule Palee.Infrastructure.Notifications.EctoNativePushTokenStore do
  @moduledoc """
  Ecto adapter of the native push token port (ADR-171). Runs inside the
  person's session (owner RLS). Registering a token another account held on
  the same install first moves it through `palee_claim_native_push_token`.
  """

  @behaviour Palee.Notifications.Ports.NativePushTokenStore

  import Ecto.Query

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Notifications.NativePushToken
  alias Palee.Repo

  @impl true
  def save_native_push_token(params) do
    changeset = NativePushToken.changeset(params)

    if changeset.valid? do
      provider = Ecto.Changeset.get_field(changeset, :provider)
      token = Ecto.Changeset.get_field(changeset, :token)

      Repo.query!("SELECT palee_claim_native_push_token($1, $2)", [provider, token])

      existing =
        NativePushToken
        |> scoped_to_user()
        |> where([row], row.provider == ^provider and row.token == ^token)
        |> Repo.one()

      upsert(existing, changeset, params)
    else
      {:error, changeset}
    end
  end

  defp upsert(nil, changeset, _params) do
    case Repo.insert(changeset) do
      {:ok, row} -> {:ok, normalize(row), :created}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp upsert(%NativePushToken{} = existing, _changeset, params) do
    case existing |> NativePushToken.changeset(params) |> Repo.update() do
      {:ok, row} -> {:ok, normalize(row), :updated}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def list_native_push_tokens(user_id) do
    NativePushToken
    |> scoped_to_user()
    |> where([row], row.user_id == ^user_id)
    |> order_by([row], desc: row.last_registered_at)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def get_native_push_token(user_id, id) do
    NativePushToken
    |> scoped_to_user()
    |> where([row], row.user_id == ^user_id and row.id == ^id)
    |> Repo.one()
    |> case do
      %NativePushToken{} = row -> normalize(row)
      nil -> nil
    end
  end

  @impl true
  def delete_native_push_token(user_id, token) do
    NativePushToken
    |> scoped_to_user()
    |> where([row], row.user_id == ^user_id and row.token == ^token)
    |> Repo.delete_all()
    |> elem(0)
    |> Kernel.>(0)
  end

  @impl true
  def delete_native_push_token_by_id(user_id, id) do
    NativePushToken
    |> scoped_to_user()
    |> where([row], row.user_id == ^user_id and row.id == ^id)
    |> Repo.delete_all()
    |> elem(0)
    |> Kernel.>(0)
  end

  defp normalize(%NativePushToken{} = row) do
    %{
      id: row.id,
      user_id: row.user_id,
      provider: row.provider,
      platform: row.platform,
      token: row.token,
      app_id: row.app_id,
      app_version: row.app_version,
      apns_environment: row.apns_environment,
      last_registered_at: row.last_registered_at,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    }
  end

  defp scoped_to_user(query) do
    case RepoContext.current_setting("app.user_id") do
      user_id when is_binary(user_id) -> where(query, [row], row.user_id == ^user_id)
      _missing_scope -> where(query, [row], false)
    end
  end
end
