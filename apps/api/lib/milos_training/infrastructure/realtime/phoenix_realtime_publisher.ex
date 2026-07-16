defmodule MilosTraining.Infrastructure.Realtime.PhoenixRealtimePublisher do
  @behaviour MilosTraining.Application.Ports.RealtimePublisher

  @impl true
  def broadcast(topic, event, payload) do
    MilosTrainingWeb.Endpoint.broadcast(topic, event, payload)
  end
end
