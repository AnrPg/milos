defmodule Palee.Devices.SyncQueue do
  @moduledoc "Dispatches the device sync queue port to the configured adapter (ADR-161)."

  @behaviour Palee.Devices.Ports.SyncQueue

  @impl true
  def enqueue_ingest(args), do: adapter().enqueue_ingest(args)

  @impl true
  def enqueue_backfill(connection_id, user_id, opts \\ []),
    do: adapter().enqueue_backfill(connection_id, user_id, opts)

  defp adapter do
    Application.get_env(
      :palee,
      :device_sync_queue,
      Palee.Infrastructure.Devices.ObanSyncQueue
    )
  end
end
