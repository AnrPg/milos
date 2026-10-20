defmodule MilosTraining.Application.CheckInToClass do
  @moduledoc """
  A member checks themselves in to a class they booked (Box › next booking,
  TD-105): records `attended` attendance, marked by the member, inside the
  class's check-in window. Idempotent: a second check-in returns the first.
  """

  alias MilosTraining.Application.AdminRecordAttendance
  alias MilosTraining.Scheduling

  def call(%{organization_id: _} = context, %{id: user_id}, booking_id, now \\ DateTime.utc_now()) do
    with %{user_id: ^user_id, guest_name: nil} = booking <-
           Scheduling.get_booking(context, booking_id) || {:error, :not_found},
         %{} = slot <-
           Scheduling.get_slot(context, booking.scheduled_class_id) || {:error, :not_found},
         existing = Scheduling.get_attendance_for_user_class(context, user_id, slot.id) do
      case Scheduling.self_check_in(booking, slot, existing, now) do
        :already ->
          {:ok, existing}

        :ok ->
          context
          |> Scheduling.record_attendance(%{
            scheduled_class_id: slot.id,
            booking_id: booking.id,
            user_id: user_id,
            status: "attended",
            marked_by_id: user_id,
            marked_at: now,
            params: %{"source" => "self"}
          })
          |> tap(fn
            {:ok, attendance} -> AdminRecordAttendance.announce_attendance(attendance)
            _error -> :ok
          end)

        error ->
          error
      end
    else
      %{} -> {:error, :not_found}
      error -> error
    end
  end
end
