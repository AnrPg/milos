defmodule MilosTrainingWeb.RealtimeEventHandler do
  use GenServer

  alias MilosTrainingWeb.Realtime

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "booking:submitted")
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "booking:resolved")
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "booking:timeout")
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "schedule:slot_created")
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "schedule:slot_updated")
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "schedule:slot_deleted")
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "schedule:workout_updated")
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "notifications:changed")
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "user:sync")
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "execution:progress_updated")
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "workout:note_submitted")
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "workout:completed")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:booking_submitted, booking}, state) do
    Realtime.broadcast_schedule_refresh("booking_submitted", %{
      slot_id: booking.scheduled_class_id,
      booking_id: booking.id
    })

    {:noreply, state}
  end

  def handle_info({:booking_resolved, booking}, state) do
    Realtime.broadcast_schedule_refresh("booking_resolved", %{
      slot_id: booking.scheduled_class_id,
      booking_id: booking.id,
      status: booking.status
    })

    {:noreply, state}
  end

  def handle_info({:booking_timed_out, booking}, state) do
    Realtime.broadcast_schedule_refresh("booking_timed_out", %{
      slot_id: booking.scheduled_class_id,
      booking_id: booking.id
    })

    {:noreply, state}
  end

  def handle_info({:schedule_slot_created, slot}, state) do
    Realtime.broadcast_schedule_refresh("slot_created", %{slot_id: slot.id})
    {:noreply, state}
  end

  def handle_info({:schedule_slot_updated, slot}, state) do
    Realtime.broadcast_schedule_refresh("slot_updated", %{slot_id: slot.id})
    {:noreply, state}
  end

  def handle_info({:schedule_slot_deleted, %{slot_id: slot_id}}, state) do
    Realtime.broadcast_schedule_refresh("slot_deleted", %{slot_id: slot_id})
    {:noreply, state}
  end

  def handle_info({:schedule_workout_updated, payload}, state) do
    Realtime.broadcast_schedule_refresh("workout_updated", payload)
    {:noreply, state}
  end

  def handle_info({:notifications_changed, %{user_id: user_id}}, state) do
    Realtime.broadcast_notification_changed(user_id)
    {:noreply, state}
  end

  def handle_info(
        {:user_sync, %{user_id: user_id, scopes: scopes, reason: reason, payload: payload}},
        state
      ) do
    Realtime.broadcast_user_sync(user_id, scopes, reason, payload)
    {:noreply, state}
  end

  def handle_info({:execution_progress_updated, execution}, state) do
    Realtime.broadcast_execution_progress(execution)
    {:noreply, state}
  end

  def handle_info({:workout_note_submitted, note_payload}, state) do
    Realtime.broadcast_execution_note(note_payload.execution_id, note_payload)
    {:noreply, state}
  end

  def handle_info({:workout_completed, execution}, state) do
    Realtime.broadcast_execution_completed(execution.id, %{execution: execution})
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
