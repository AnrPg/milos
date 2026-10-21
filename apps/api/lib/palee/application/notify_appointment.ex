defmodule Palee.Application.NotifyAppointment do
  @moduledoc false
  # Appointment notifications (ADR-098).

  alias Palee.Notifications

  def booked(slot, client) do
    Notifications.process_event("appointment_booked", %{
      user_id: slot.coach_id,
      slot_id: slot.id,
      kind: slot.kind,
      starts_at: slot.starts_at,
      client_nickname: Map.get(client, :nickname)
    })
  end

  def cancelled(recipient_id, slot) do
    # The coach manages appointments in the admin screen; clients in their own.
    url = if recipient_id == slot.coach_id, do: "/admin/appointments", else: "/appointments"

    Notifications.process_event("appointment_cancelled", %{
      user_id: recipient_id,
      url: url,
      slot_id: slot.id,
      kind: slot.kind,
      starts_at: slot.starts_at
    })
  end
end
