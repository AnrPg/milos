defmodule MilosTraining.Devices.Ports.SyncQueue do
  @moduledoc """
  Background work of device sync (ADR-161): one ingest per push batch or
  callback URL, and the history import one window at a time. Adapters run
  the work later (Oban) or right away when background jobs are off.
  """

  @callback enqueue_ingest(map()) :: :ok | {:error, term()}
  @callback enqueue_backfill(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: :ok | {:error, term()}
end
