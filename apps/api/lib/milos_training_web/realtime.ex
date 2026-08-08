defmodule MilosTrainingWeb.Realtime do
  require Logger

  alias MilosTrainingWeb.Endpoint

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

  def broadcast_execution_note(execution_id, note) do
    Endpoint.broadcast("execution:#{execution_id}", "execution:note_submitted", %{
      execution_id: execution_id,
      note: note
    })
  end

  def broadcast_execution_completed(execution_id, payload) do
    Endpoint.broadcast("execution:#{execution_id}", "execution:completed", payload)
  end
end
