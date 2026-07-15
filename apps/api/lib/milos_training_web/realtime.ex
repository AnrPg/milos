defmodule MilosTrainingWeb.Realtime do
  alias MilosTrainingWeb.Endpoint

  def broadcast_schedule_refresh(event, payload \\ %{}) do
    Endpoint.broadcast("schedule:lobby", "schedule:refresh", %{
      event: event,
      payload: payload
    })
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
