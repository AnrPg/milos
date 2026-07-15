defmodule MilosTraining.Application.AdminRecordAttendance do
  alias MilosTraining.Scheduling.Domain.AttendancePolicy
  alias MilosTraining.{Finance, Scheduling}

  def call(slot_id, user_id, admin_id, params \\ %{}) do
    with {:ok, approved_booking} <- approved_booking(slot_id, user_id),
         :ok <- AttendancePolicy.can_record_admin_attendance?(approved_booking) do
      attendance_params =
        params
        |> string_key_map()
        |> Map.merge(%{
          "scheduled_class_id" => slot_id,
          "booking_id" => approved_booking.id,
          "user_id" => user_id,
          "marked_by_id" => admin_id,
          "status" => params["status"] || params[:status] || "attended"
        })

      with {:ok, attendance} <- Scheduling.record_attendance(attendance_params),
           {:ok, _transition} <- reconcile_visit(attendance) do
        {:ok, attendance}
      end
    end
  end

  defp reconcile_visit(%{status: "cancelled"} = attendance) do
    Finance.release_entitlement_source(
      attendance.user_id,
      "scheduling",
      attendance.scheduled_class_id,
      :class_visits,
      %{
        reason: "Attendance cancelled",
        idempotency_key: "attendance-cancelled:#{attendance.id}"
      }
    )
  end

  defp reconcile_visit(attendance) do
    Finance.finalize_entitlement_source(
      attendance.user_id,
      "scheduling",
      attendance.scheduled_class_id,
      :class_visits,
      %{
        reason: "Attendance recorded as #{attendance.status}",
        idempotency_key: "attendance-finalized:#{attendance.id}"
      }
    )
  end

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp approved_booking(slot_id, user_id) do
    case Scheduling.get_approved_booking_for_class(user_id, slot_id) do
      nil -> {:error, :attendance_requires_approved_booking}
      booking -> {:ok, booking}
    end
  end
end
