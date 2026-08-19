defmodule MilosTraining.Infrastructure.Maintenance.CleanSlatePurge do
  @moduledoc """
  One-shot operator purge for resetting production tenant data.

  This module is intentionally release-callable and heavily guarded because it
  performs broad database deletion for deployment recovery, not normal product
  behavior.
  """

  import Ecto.Query

  alias Ecto.Adapters.SQL
  alias MilosTraining.Identity.{RegistrationPolicy, User}
  alias MilosTraining.Organizations.Vendor
  alias MilosTraining.Repo

  @confirmation "PURGE_ALL_TENANT_DATA_KEEP_SAAS_OWNER"
  @preserved_tables ~w(schema_migrations users vendors scale_levels training_quotes)

  def run_from_env do
    with :ok <- require_confirmation(),
         {:ok, owner_nickname} <- fetch_required_env("MILOS_SAAS_OWNER_NICKNAME"),
         {:ok, postgres_summary} <- purge_postgres_except_saas_owner(owner_nickname),
         {:ok, redis_summary} <- purge_redis(),
         {:ok, meilisearch_summary} <- purge_meilisearch() do
      {:ok,
       postgres_summary
       |> Map.put(:purged_redis, redis_summary)
       |> Map.put(:purged_meilisearch, meilisearch_summary)}
    end
  end

  def purge_postgres_except_saas_owner(owner_nickname) when is_binary(owner_nickname) do
    normalized_nickname = RegistrationPolicy.normalize_nickname(owner_nickname)

    Repo.transaction(fn ->
      owner =
        User
        |> join(:inner, [user], vendor in Vendor,
          on: vendor.user_id == user.id and vendor.status == :active
        )
        |> where([user, _vendor], user.nickname == ^normalized_nickname)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(owner) do
        Repo.rollback({:saas_owner_not_found_or_not_active_vendor, normalized_nickname})
      end

      purged_tables = purge_runtime_tables()
      purged_vendors = purge_non_owner_vendors(owner.id)
      purged_users = purge_non_owner_users(owner.id)

      %{
        preserved_owner_id: owner.id,
        preserved_owner_nickname: owner.nickname,
        purged_runtime_tables: purged_tables,
        purged_non_owner_vendors: purged_vendors,
        purged_non_owner_users: purged_users
      }
    end)
  end

  defp require_confirmation do
    case System.get_env("MILOS_CONFIRM_PROD_PURGE") do
      @confirmation ->
        :ok

      _other ->
        {:error, {:missing_confirmation, "Set MILOS_CONFIRM_PROD_PURGE=#{@confirmation}"}}
    end
  end

  defp fetch_required_env(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:missing_env, name}}
    end
  end

  defp purge_runtime_tables do
    tables =
      SQL.query!(
        Repo,
        """
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename <> ALL($1::text[])
        ORDER BY tablename
        """,
        [@preserved_tables]
      )
      |> Map.fetch!(:rows)
      |> List.flatten()

    if tables != [] do
      SQL.query!(
        Repo,
        "TRUNCATE TABLE #{qualified_table_list(tables)} RESTART IDENTITY CASCADE",
        []
      )
    end

    tables
  end

  defp purge_non_owner_vendors(owner_id) do
    SQL.query!(Repo, "DELETE FROM vendors WHERE user_id <> $1 OR status <> 'active'", [
      Ecto.UUID.dump!(owner_id)
    ]).num_rows
  end

  defp purge_non_owner_users(owner_id) do
    SQL.query!(Repo, "DELETE FROM users WHERE id <> $1", [Ecto.UUID.dump!(owner_id)]).num_rows
  end

  defp purge_redis do
    case Application.get_env(:milos_training, :redis_url) do
      nil ->
        {:ok, :skipped}

      redis_url ->
        case Redix.start_link(redis_url) do
          {:ok, connection} ->
            try do
              case Redix.command(connection, ["FLUSHDB"]) do
                {:ok, "OK"} -> {:ok, :flushed_current_database}
                {:error, reason} -> {:error, {:redis_purge_failed, reason}}
              end
            after
              GenServer.stop(connection)
            end

          {:error, reason} ->
            {:error, {:redis_purge_failed, reason}}
        end
    end
  end

  defp purge_meilisearch do
    indexes = meilisearch_indexes()

    results =
      Enum.map(indexes, fn index ->
        case Req.delete(meilisearch_url("/indexes/#{index}"),
               headers: meilisearch_headers(),
               retry: false,
               receive_timeout: 5_000
             ) do
          {:ok, %{status: status}} when status in 200..299 or status == 404 ->
            {:ok, index}

          {:ok, %{status: status, body: body}} ->
            {:error, {index, status, body}}

          {:error, reason} ->
            {:error, {index, reason}}
        end
      end)

    case Enum.find(results, &match?({:error, _reason}, &1)) do
      nil -> {:ok, indexes}
      {:error, reason} -> {:error, {:meilisearch_purge_failed, reason}}
    end
  end

  defp meilisearch_indexes do
    config = Application.get_env(:milos_training, :meilisearch, [])
    admin_member_index = Keyword.get(config, :admin_member_index, "admin_members")

    [admin_member_index, "user_pr_records"]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp meilisearch_url(path) do
    :milos_training
    |> Application.get_env(:meilisearch, [])
    |> Keyword.get(:url, "http://localhost:7700")
    |> String.trim_trailing("/")
    |> Kernel.<>(path)
  end

  defp meilisearch_headers do
    :milos_training
    |> Application.get_env(:meilisearch, [])
    |> Keyword.get(:api_key)
    |> case do
      nil -> []
      "" -> []
      api_key -> [{"authorization", "Bearer #{api_key}"}]
    end
  end

  defp qualified_table_list(tables) do
    tables
    |> Enum.map(&~s(public.#{quote_identifier(&1)}))
    |> Enum.join(", ")
  end

  defp quote_identifier(identifier) do
    ~s("#{String.replace(identifier, "\"", "\"\"")}")
  end
end
