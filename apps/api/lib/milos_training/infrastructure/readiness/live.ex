defmodule MilosTraining.Infrastructure.Readiness.Live do
  @moduledoc false
  @behaviour MilosTraining.Application.Ports.Readiness

  alias Ecto.Adapters.SQL
  alias MilosTraining.Repo

  def status do
    checks = %{
      database: database_status(),
      redis: redis_status(),
      jobs: jobs_status(),
      search: search_status(),
      object_storage: object_storage_status()
    }

    if Enum.all?(checks, fn {_name, status} -> status == :ok end) do
      {:ok, checks}
    else
      {:error, checks}
    end
  end

  defp database_status do
    case SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} -> :ok
      {:error, _reason} -> :error
    end
  end

  defp redis_status do
    if Application.get_env(:milos_training, :start_redix, true) do
      case Redix.command(:redix, ["PING"]) do
        {:ok, "PONG"} -> :ok
        {:error, _reason} -> :error
      end
    else
      :ok
    end
  end

  defp jobs_status do
    if Application.get_env(:milos_training, :start_oban, true) do
      case Oban.Registry.whereis(Oban) do
        nil -> :error
        _pid -> :ok
      end
    else
      :ok
    end
  end

  defp search_status do
    config = Application.get_env(:milos_training, :meilisearch, [])
    url = String.trim_trailing(config[:url] || "http://localhost:7700", "/") <> "/health"

    case Req.get(url, receive_timeout: 1_000, retry: false) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      _other -> :error
    end
  end

  defp object_storage_status do
    case MilosTraining.Infrastructure.Storage.MinioStorage.health_status() do
      :ok -> :ok
      _other -> :error
    end
  end
end
