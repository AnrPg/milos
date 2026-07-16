defmodule MilosTraining.Application.RealtimePublisher do
  @behaviour MilosTraining.Application.Ports.RealtimePublisher

  @impl true
  def broadcast(topic, event, payload), do: impl().broadcast(topic, event, payload)

  defp impl, do: Application.fetch_env!(:milos_training, :realtime_publisher)
end
