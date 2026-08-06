defmodule MilosTraining.Application.ScheduleRealtime do
  require Logger

  alias MilosTraining.Application.RealtimePublisher
  alias MilosTraining.Organizations

  def broadcast(event, payload \\ %{}) when is_binary(event) and is_map(payload) do
    organization_id =
      Map.get(payload, :organization_id) || Map.get(payload, "organization_id") ||
        fallback_to_legacy_organization_id(event)

    RealtimePublisher.broadcast("schedule:#{organization_id}", "schedule:refresh", %{
      event: event,
      payload: payload
    })
  end

  defp fallback_to_legacy_organization_id(event) do
    Logger.warning(
      "ScheduleRealtime.broadcast: payload for event=#{event} omitted organization_id, falling back to the legacy organization"
    )

    legacy_organization_id()
  end

  defp legacy_organization_id do
    Organizations.get_by_slug(Organizations.legacy_organization_slug()).id
  end
end
