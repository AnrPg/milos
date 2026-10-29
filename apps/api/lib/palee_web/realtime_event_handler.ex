defmodule PaleeWeb.RealtimeEventHandler do
  use GenServer

  alias Palee.Application.BoxScreens.BoxScreenSignals
  alias PaleeWeb.Realtime

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    Phoenix.PubSub.subscribe(Palee.PubSub, "booking:submitted")
    Phoenix.PubSub.subscribe(Palee.PubSub, "booking:resolved")
    Phoenix.PubSub.subscribe(Palee.PubSub, "booking:timeout")
    Phoenix.PubSub.subscribe(Palee.PubSub, "schedule:slot_created")
    Phoenix.PubSub.subscribe(Palee.PubSub, "schedule:slot_updated")
    Phoenix.PubSub.subscribe(Palee.PubSub, "schedule:slot_deleted")
    Phoenix.PubSub.subscribe(Palee.PubSub, "schedule:workout_updated")
    Phoenix.PubSub.subscribe(Palee.PubSub, "notifications:changed")
    Phoenix.PubSub.subscribe(Palee.PubSub, "user:sync")
    Phoenix.PubSub.subscribe(Palee.PubSub, "execution:progress_updated")
    Phoenix.PubSub.subscribe(Palee.PubSub, "workout:completed")
    Phoenix.PubSub.subscribe(Palee.PubSub, "class_timer:updated")
    Phoenix.PubSub.subscribe(Palee.PubSub, BoxScreenSignals.topic())
    {:ok, %{}}
  end

  # ADR-253: box screens.
  @impl true
  def handle_info({:box_screen_hint, %{organization_id: id, kind: kind, slot_id: slot}}, state) do
    Realtime.broadcast_box_screen_refresh(id, kind, slot)
    {:noreply, state}
  end

  def handle_info({:box_screen_override, %{organization_id: id} = message}, state) do
    Realtime.broadcast_box_screen_override(id, message.screen_id, message.override)
    {:noreply, state}
  end

  def handle_info({:box_screen_disconnect, %{screen_id: screen_id}}, state) do
    Realtime.disconnect_box_screen(screen_id)
    {:noreply, state}
  end

  def handle_info(
        {:class_timer_updated, %{scheduled_class_id: scheduled_class_id, payload: payload}},
        state
      ) do
    Realtime.broadcast_class_timer(scheduled_class_id, payload)
    {:noreply, state}
  end

  def handle_info({:booking_submitted, booking}, state) do
    Realtime.broadcast_schedule_refresh("booking_submitted", %{
      slot_id: booking.scheduled_class_id,
      booking_id: booking.id,
      organization_id: booking.organization_id
    })

    {:noreply, state}
  end

  def handle_info({:booking_resolved, booking}, state) do
    Realtime.broadcast_schedule_refresh("booking_resolved", %{
      slot_id: booking.scheduled_class_id,
      booking_id: booking.id,
      status: booking.status,
      organization_id: booking.organization_id
    })

    {:noreply, state}
  end

  def handle_info({:booking_timed_out, booking}, state) do
    Realtime.broadcast_schedule_refresh("booking_timed_out", %{
      slot_id: booking.scheduled_class_id,
      booking_id: booking.id,
      organization_id: booking.organization_id
    })

    {:noreply, state}
  end

  def handle_info({:schedule_slot_created, slot}, state) do
    Realtime.broadcast_schedule_refresh("slot_created", %{
      slot_id: slot.id,
      organization_id: slot.organization_id
    })

    box_screen_schedule_hint(slot.organization_id, slot.id)

    {:noreply, state}
  end

  def handle_info({:schedule_slot_updated, slot}, state) do
    Realtime.broadcast_schedule_refresh("slot_updated", %{
      slot_id: slot.id,
      organization_id: slot.organization_id
    })

    box_screen_schedule_hint(slot.organization_id, slot.id)

    {:noreply, state}
  end

  def handle_info(
        {:schedule_slot_deleted, %{slot_id: slot_id, organization_id: organization_id}},
        state
      ) do
    Realtime.broadcast_schedule_refresh("slot_deleted", %{
      slot_id: slot_id,
      organization_id: organization_id
    })

    box_screen_schedule_hint(organization_id, slot_id)

    {:noreply, state}
  end

  def handle_info({:schedule_workout_updated, payload}, state) do
    Realtime.broadcast_schedule_refresh("workout_updated", payload)

    box_screen_schedule_hint(
      Map.get(payload, :organization_id) || Map.get(payload, "organization_id"),
      Map.get(payload, :slot_id) || Map.get(payload, "slot_id")
    )
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

  def handle_info({:workout_completed, execution}, state) do
    Realtime.broadcast_execution_completed(execution.id, %{execution: execution})
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp box_screen_schedule_hint(organization_id, slot_id) when is_binary(organization_id),
    do: Realtime.broadcast_box_screen_refresh(organization_id, "schedule", slot_id)

  defp box_screen_schedule_hint(_organization_id, _slot_id), do: :ok
end
