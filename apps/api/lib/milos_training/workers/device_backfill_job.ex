defmodule MilosTraining.Workers.DeviceBackfillJob do
  @moduledoc "Asks Garmin for the next window of history, then queues the next (ADR-161)."

  use Oban.Worker, queue: :default, max_attempts: 5

  alias MilosTraining.Application.DeviceBackfill

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"connection_id" => connection_id, "user_id" => user_id}}) do
    case DeviceBackfill.perform(connection_id, user_id) do
      :ok -> :ok
      {:error, :device_reconnect_required} -> {:cancel, :device_reconnect_required}
      {:error, reason} -> {:error, reason}
    end
  end
end
