defmodule MilosTraining.Application.CancelAppointmentSlot do
  @moduledoc "Staff cancel a slot; booked clients get their session back and are told (ADR-098)."

  alias MilosTraining.Application.{AppointmentLedger, NotifyAppointment}
  alias MilosTraining.Appointments

  def call(context, _staff, slot_id) do
    with {:ok, slot} <- Appointments.cancel_slot(context, slot_id) do
      Enum.each(slot.bookings, fn booking ->
        {:ok, cancelled} = Appointments.cancel_booking(context, booking.id, false)

        AppointmentLedger.release(
          context,
          Map.put(cancelled, :reservation_id, booking.reservation_id),
          "Appointment slot cancelled"
        )

        NotifyAppointment.cancelled(booking.user_id, slot)
      end)

      {:ok, %{slot | bookings: []}}
    end
  end
end
