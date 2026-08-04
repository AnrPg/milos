defmodule MilosTraining.Application.ScheduleRealtime do
  alias MilosTraining.Application.RealtimePublisher
  alias MilosTraining.Organizations

  def broadcast(event, payload \\ %{}) when is_binary(event) and is_map(payload) do
    organization_id =
      Map.get(payload, :organization_id) ||
        Map.get(payload, "organization_id") ||
        legacy_organization_id()

    RealtimePublisher.broadcast("schedule:#{organization_id}", "schedule:refresh", %{
      event: event,
      payload: payload
    })
  end

  defp legacy_organization_id do
    Organizations.get_by_slug(Organizations.legacy_organization_slug()).id
  end
end
