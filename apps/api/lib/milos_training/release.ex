defmodule MilosTraining.Release do
  @moduledoc false

  @app :milos_training

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

    with_migration_url(MilosTraining.Repo, fn ->
      {:ok, result, _started_apps} =
        Ecto.Migrator.with_repo(MilosTraining.Repo, fn _repo ->
          MilosTraining.Infrastructure.Maintenance.CleanSlatePurge.run_from_env()
        end)

      case result do
        {:ok, summary} -> IO.puts("Clean slate purge complete: #{inspect(summary)}")
        {:error, reason} -> raise "Clean slate purge refused: #{inspect(reason)}"
      end
    end)
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
