defmodule PaleeWeb.Realtime do
  require Logger

  alias PaleeWeb.Endpoint

  def broadcast_schedule_refresh(event, payload \\ %{}) do
    case Map.get(payload, :organization_id) || Map.get(payload, "organization_id") do
      organization_id when is_binary(organization_id) ->
        Endpoint.broadcast("schedule:#{organization_id}", "schedule:refresh", %{
          event: event,
          payload: payload
        })

      _missing ->
        Logger.error(
          "Realtime.broadcast_schedule_refresh: payload for event=#{event} omitted organization_id"
        )

        {:error, :organization_context_required}
    end
  end

  def broadcast_notification_changed(user_id) do
    Endpoint.broadcast("notifications:#{user_id}", "notifications:changed", %{
      user_id: user_id
    })
  end

  def broadcast_user_sync(user_id, scopes, reason, payload \\ %{}) do
    Endpoint.broadcast("sync:#{user_id}", "sync:refresh", %{
      user_id: user_id,
      scopes: scopes,
      reason: reason,
      payload: payload
    })
  end

  def broadcast_execution_progress(execution) do
    execution_id = execution.id

    Endpoint.broadcast("execution:#{execution_id}", "execution:progress_updated", %{
      execution_id: execution_id,
      execution: execution
    })
  end

  def broadcast_class_timer(scheduled_class_id, payload) do
    Endpoint.broadcast("class_timer:#{scheduled_class_id}", "class_timer:updated", payload)
  end

  @doc "ADR-253: a hint for every screen of a box (`%{kind, slot_id}`, never who)."
  def broadcast_box_screen_refresh(organization_id, kind, slot_id) do
    Endpoint.broadcast("box_screen:#{organization_id}", "box_screen:refresh", %{
      kind: kind,
      slot_id: slot_id
    })
  end

  @doc "ADR-253: a screen's override; only that screen's channel pushes it."
  def broadcast_box_screen_override(organization_id, screen_id, override) do
    Endpoint.broadcast("box_screen:#{organization_id}", "box_screen:override", %{
      screen_id: screen_id,
      override: override
    })
  end

  @doc "ADR-253: closes a removed or re-paired screen's socket."
  def disconnect_box_screen(screen_id),
    do: Endpoint.broadcast(PaleeWeb.BoxScreenSocket.socket_id(screen_id), "disconnect", %{})

  def broadcast_execution_completed(execution_id, payload) do
    Endpoint.broadcast("execution:#{execution_id}", "execution:completed", payload)
  end
end
