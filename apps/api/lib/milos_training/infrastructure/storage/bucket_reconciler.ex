defmodule MilosTraining.Infrastructure.Storage.BucketReconciler do
  use GenServer

  require Logger

  alias MilosTraining.Infrastructure.Storage.MinioStorage

  @healthy_interval :timer.minutes(5)
  @max_retry_interval :timer.minutes(1)

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(_options) do
    send(self(), :reconcile)
    {:ok, %{retry_interval: 1_000}}
  end

  @impl true
  def handle_info(:reconcile, state) do
    case MinioStorage.ensure_buckets() do
      :ok ->
        Process.send_after(self(), :reconcile, @healthy_interval)
        {:noreply, %{state | retry_interval: 1_000}}

      {:error, reason} ->
        Logger.warning("object_storage_reconciliation_failed reason=#{inspect(reason)}")
        Process.send_after(self(), :reconcile, state.retry_interval)

        {:noreply, %{state | retry_interval: min(state.retry_interval * 2, @max_retry_interval)}}
    end
  end
end
