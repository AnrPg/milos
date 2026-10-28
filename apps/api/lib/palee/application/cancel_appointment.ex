defmodule Palee.Application.CancelAppointment do
  @moduledoc """
  Cancels a booked appointment (ADR-098). A client cancelling inside the
  cancellation cutoff uses the session; staff cancellations always give it
  back. The other party is notified.
  """

  alias Palee.Application.{AppointmentLedger, NotifyAppointment}
  alias Palee.{Appointments, Finance, Organizations}
  alias Palee.Appointments.Domain.AppointmentPolicy

  def call(context, %{id: actor_id}, booking_id) do
    staff? =
      Organizations.can?(context, :manage_appointments) or
        Organizations.can?(context, :book_for_clients)

    with %{} = booking <- Appointments.get_booking(context, booking_id) || {:error, :not_found},
         :ok <- owner_or_staff(booking, actor_id, staff?),
         :ok <- AppointmentPolicy.can_cancel?(booking),
         late? = late?(context, booking, staff? and booking.user_id != actor_id),
         {:ok, cancelled} <- Appointments.cancel_booking(context, booking.id, late?) do
      if late?,
        do: AppointmentLedger.finalize(context, booking, "Late appointment cancellation"),
        else: AppointmentLedger.release(context, booking, "Appointment cancelled")

      recipient = if booking.user_id == actor_id, do: booking.slot.coach_id, else: booking.user_id

      NotifyAppointment.cancelled(
        recipient,
        Map.put_new(booking.slot, :organization_id, context.organization_id)
      )

      {:ok, cancelled}
    end
  end

  defp owner_or_staff(%{user_id: user_id}, user_id, _staff?), do: :ok
  defp owner_or_staff(_booking, _actor_id, true), do: :ok
  defp owner_or_staff(_booking, _actor_id, false), do: {:error, :forbidden}

  defp late?(_context, _booking, true = _by_staff), do: false

  defp late?(context, booking, false) do
    slot = booking.slot
    allowance = String.to_existing_atom(booking.allowance)

    terms =
      Finance.allowance_terms(
        context,
        booking.user_id,
        allowance,
        Organizations.local_date(context, slot.starts_at)
      )

    AppointmentPolicy.late_cancellation?(
      slot.starts_at,
      DateTime.utc_now(),
      AppointmentLedger.cutoff_minutes(context, terms)
    )
  end
end
