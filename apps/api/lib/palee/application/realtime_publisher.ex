defmodule Palee.Application.RealtimePublisher do
  @behaviour Palee.Application.Ports.RealtimePublisher

  @impl true
  def broadcast(topic, event, payload), do: impl().broadcast(topic, event, payload)

  defp impl, do: Application.fetch_env!(:palee, :realtime_publisher)
end
