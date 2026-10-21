defmodule Palee.Infrastructure.Devices.ObanSyncQueue do
  @moduledoc """
  Oban adapter of the device sync queue (ADR-161). With background jobs off
  (tests, one-off scripts) the work runs inline, as media processing does.
  """

  @behaviour Palee.Devices.Ports.SyncQueue

  require Logger

  alias Palee.Application.{DeviceBackfill, ImportDeviceSummaries}
  alias Palee.Workers.{DeviceBackfillJob, DeviceIngestJob}

  @impl true
  def enqueue_ingest(args) do
    if background?() do
      args |> stringify() |> DeviceIngestJob.new() |> insert()
    else
      _result = ImportDeviceSummaries.run(stringify(args))
      :ok
    end
  end

  @impl true
  def enqueue_backfill(connection_id, user_id, opts) do
    args = %{"connection_id" => connection_id, "user_id" => user_id}

    if background?() do
      args |> DeviceBackfillJob.new(Keyword.take(opts, [:schedule_in])) |> insert()
    else
      _result = DeviceBackfill.run_all(connection_id, user_id)
      :ok
    end
  end

  defp insert(changeset) do
    case Oban.insert(changeset) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("device sync enqueue failed #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp background?, do: Application.get_env(:palee, :start_oban, true)

  defp stringify(args), do: Map.new(args, fn {key, value} -> {to_string(key), value} end)
end
