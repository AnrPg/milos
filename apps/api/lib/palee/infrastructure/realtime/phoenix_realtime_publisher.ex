defmodule Palee.Infrastructure.Realtime.PhoenixRealtimePublisher do
  @behaviour Palee.Application.Ports.RealtimePublisher

  @impl true
  def broadcast(topic, event, payload) do
    PaleeWeb.Endpoint.broadcast(topic, event, payload)
  end
end
