defmodule MilosTraining.Application.ScheduleRealtime do
  require Logger

  alias MilosTraining.Application.RealtimePublisher

  def broadcast(event, payload \\ %{}) when is_binary(event) and is_map(payload) do
    case Map.get(payload, :organization_id) || Map.get(payload, "organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        RealtimePublisher.broadcast("schedule:#{organization_id}", "schedule:refresh", %{
          event: event,
          payload: payload
        })

      _missing ->
        Logger.error(
          "ScheduleRealtime.broadcast: payload for event=#{event} omitted organization_id"
        )

        {:error, :missing_organization_id}
    end
  end
end
