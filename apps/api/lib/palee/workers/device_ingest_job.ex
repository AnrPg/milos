defmodule Palee.Workers.DeviceIngestJob do
  @moduledoc "Imports one Garmin push batch or callback URL (ADR-161)."

  use Oban.Worker, queue: :default, max_attempts: 5

  alias Palee.Application.ImportDeviceSummaries

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case ImportDeviceSummaries.run(args) do
      {:ok, _result} -> :ok
      {:error, :invalid_callback_url} -> {:cancel, :invalid_callback_url}
      {:error, :device_reconnect_required} -> {:cancel, :device_reconnect_required}
      {:error, reason} -> {:error, reason}
    end
  end
end
