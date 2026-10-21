defmodule Palee.Application.RecordAppointmentAttendance do
  @moduledoc """
  Staff mark an appointment attended or missed (ADR-098). Attended uses the
  session; a no-show uses it unless the paying package waives no-shows.
  """

  alias Palee.Application.AppointmentLedger
  alias Palee.{Appointments, Finance}
  alias Palee.Appointments.Domain.AppointmentPolicy

  def call(context, _staff, booking_id, status) when status in ["attended", "no_show"] do
    with %{} = booking <- Appointments.get_booking(context, booking_id) || {:error, :not_found},
         :ok <- AppointmentPolicy.can_record_attendance?(booking),
         {:ok, recorded} <- Appointments.record_attendance(context, booking.id, status) do
      if status == "no_show" and waived?(context, booking),
        do: AppointmentLedger.release(context, booking, "No-show waived by package"),
        else: AppointmentLedger.finalize(context, booking, "Appointment #{status}")

      {:ok, recorded}
    end
  end

  def call(_context, _staff, _booking_id, _status), do: {:error, :invalid_attendance_status}

  defp waived?(context, booking) do
    allowance = String.to_existing_atom(booking.allowance)
    date = DateTime.to_date(booking.slot.starts_at)

    case Finance.allowance_terms(context, booking.user_id, allowance, date) do
      %{no_show_penalty_waived: true} -> true
      _terms -> false
    end
  end
end
