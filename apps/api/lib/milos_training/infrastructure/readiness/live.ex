defmodule MilosTraining.Infrastructure.Readiness.Live do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias MilosTraining.Repo

  def status do
    checks = %{
      database: database_status(),
      redis: redis_status()
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
end
