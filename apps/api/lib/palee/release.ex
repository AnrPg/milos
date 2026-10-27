defmodule Palee.Release do
  @moduledoc false

  @app :palee

  def migrate do
    load_app()

    for repo <- repos() do
      with_migration_url(repo, fn ->
        {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
      end)
    end
  end

  def purge_tenant_data_except_saas_owner do
    load_app()

    with_migration_url(Palee.Repo, fn ->
      {:ok, result, _started_apps} =
        Ecto.Migrator.with_repo(Palee.Repo, fn _repo ->
          Palee.Infrastructure.Maintenance.CleanSlatePurge.run_from_env()
        end)

      case result do
        {:ok, summary} -> IO.puts("Clean slate purge complete: #{inspect(summary)}")
        {:error, reason} -> raise "Clean slate purge refused: #{inspect(reason)}"
      end
    end)
  end

  @doc "Rebuilds the search indexes; run on the live node (`bin/palee rpc`)."
  def reindex_search do
    {:ok, summary} = Palee.Application.ReindexSearch.call()
    IO.puts("Search reindexed: #{inspect(summary)}")
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp with_migration_url(repo, fun) do
    original = Application.get_env(@app, repo, [])
    migration_url = Application.fetch_env!(@app, :migration_database_url)
    Application.put_env(@app, repo, Keyword.put(original, :url, migration_url))

    try do
      fun.()
    after
      Application.put_env(@app, repo, original)
    end
  end
end
