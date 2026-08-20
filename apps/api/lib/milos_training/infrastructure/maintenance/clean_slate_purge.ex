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
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Vendor
  alias MilosTraining.Repo

  @confirmation "PURGE_ALL_TENANT_DATA_KEEP_SAAS_OWNER"
  @finch MilosTraining.MaintenanceFinch
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
        |> where([user], user.nickname == ^normalized_nickname)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(owner) do
        Repo.rollback({:saas_owner_not_found, normalized_nickname})
      end

      RepoContext.run(%{user_id: owner.id}, fn ->
        purged_tables = purge_runtime_tables()
        owner_vendor = ensure_owner_vendor(owner.id)
        purged_vendors = purge_non_owner_vendors(owner.id)
        purged_users = purge_non_owner_users(owner.id)

        %{
          preserved_owner_id: owner.id,
          preserved_owner_nickname: owner.nickname,
          preserved_owner_vendor_id: owner_vendor.id,
          purged_runtime_tables: purged_tables,
          purged_non_owner_vendors: purged_vendors,
          purged_non_owner_users: purged_users
        }
      end)
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
    SQL.query!(Repo, "DELETE FROM vendors WHERE user_id <> $1", [Ecto.UUID.dump!(owner_id)]).num_rows
  end

  defp ensure_owner_vendor(owner_id) do
    %Vendor{}
    |> Vendor.changeset(%{user_id: owner_id, status: :active})
    |> Repo.insert!(
      on_conflict: {:replace, [:status, :updated_at]},
      conflict_target: [:user_id],
      returning: true
    )
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
                {:ok, "OK"} ->
                  {:ok, :flushed_current_database}

                {:error, %Redix.Error{message: message}} when is_binary(message) ->
                  if String.contains?(message, "unknown command") do
                    purge_redis_by_scan(connection)
                  else
                    {:error, {:redis_purge_failed, message}}
                  end

                {:error, reason} ->
                  {:error, {:redis_purge_failed, reason}}
              end
            after
              GenServer.stop(connection)
            end

          {:error, reason} ->
            {:error, {:redis_purge_failed, reason}}
        end
    end
  end

  defp purge_redis_by_scan(connection) do
    with {:ok, deleted} <- scan_delete_redis_keys(connection, "0", 0) do
      {:ok, {:deleted_keys, deleted}}
    end
  end

  defp scan_delete_redis_keys(connection, cursor, deleted) do
    case Redix.command(connection, ["SCAN", cursor, "COUNT", "1000"]) do
      {:ok, [next_cursor, keys]} ->
        with {:ok, deleted_count} <- delete_redis_keys(connection, keys) do
          if next_cursor == "0" do
            {:ok, deleted + deleted_count}
          else
            scan_delete_redis_keys(connection, next_cursor, deleted + deleted_count)
          end
        end

      {:error, reason} ->
        {:error, {:redis_purge_failed, reason}}
    end
  end

  defp delete_redis_keys(_connection, []), do: {:ok, 0}

  defp delete_redis_keys(connection, keys) do
    case Redix.command(connection, ["DEL" | keys]) do
      {:ok, count} when is_integer(count) -> {:ok, count}
      {:error, reason} -> {:error, {:redis_purge_failed, reason}}
    end
  end

  defp purge_meilisearch do
    with {:ok, _started_apps} <- Application.ensure_all_started(:finch),
         {:ok, finch} <- start_meilisearch_finch() do
      try do
        purge_meilisearch_indexes()
      after
        stop_meilisearch_finch(finch)
      end
    else
      {:error, reason} -> {:error, {:meilisearch_purge_failed, reason}}
    end
  end

  defp start_meilisearch_finch do
    case apply(Finch, :start_link, [[name: @finch]]) do
      {:ok, finch} -> {:ok, finch}
      {:error, {:already_started, finch}} -> {:ok, finch}
      {:error, reason} -> {:error, {:finch_start_failed, reason}}
    end
  end

  defp stop_meilisearch_finch(finch) when is_pid(finch) do
    if Process.alive?(finch) do
      GenServer.stop(finch)
    end
  end

  defp purge_meilisearch_indexes do
    indexes = meilisearch_indexes()

    results =
      Enum.map(indexes, fn index ->
        case Req.delete(meilisearch_url("/indexes/#{index}"),
               headers: meilisearch_headers(),
               retry: false,
               receive_timeout: 5_000,
               finch: [name: @finch]
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
