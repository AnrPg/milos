defmodule Palee.Application.AdminRecordAttendance do
  alias Palee.Application.{BookingEntitlement, BookingTerms, TrackAnalyticsEvent}
  alias Palee.Scheduling.Domain.AttendancePolicy
  alias Palee.Scheduling

  def call(context, slot_id, user_id, admin_id, params) do
    with {:ok, approved_booking} <- approved_booking(context, slot_id, user_id),
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

      allowance = BookingEntitlement.allowance(approved_booking)
      waived? = no_show_waived?(context, approved_booking)

      with {:ok, attendance} <- Scheduling.record_attendance(context, attendance_params),
           {:ok, _transition} <- reconcile_visit(context, attendance, allowance, waived?) do
        TrackAnalyticsEvent.call("class_attendance_recorded", context, attendance, %{
          metadata: %{member_id: user_id}
        })

        announce_attendance(attendance)

        {:ok, attendance}
      end
    end
  end

  def call(%{organization_id: _} = context, slot_id, user_id, admin_id),
    do: call(context, slot_id, user_id, admin_id, %{})

  def call(_slot_id, _user_id, _admin_id, _params),
    do: {:error, :organization_context_required}

  def call(_slot_id, _user_id, _admin_id), do: {:error, :organization_context_required}

  # TD-092: every ledger transition runs in the tenant's scope - unscoped, RLS
  # hid the reservation and the visit was silently never finalized/returned.
  defp reconcile_visit(context, %{status: "cancelled"} = attendance, allowance, _waived?) do
    BookingEntitlement.release(
      context,
      attendance.user_id,
      attendance.scheduled_class_id,
      allowance,
      %{
        reason: "Attendance cancelled",
        idempotency_key: "attendance-cancelled:#{attendance.id}"
      }
    )
  end

  # ADR-097: packages that waive the no-show penalty return the visit.
  defp reconcile_visit(context, %{status: "no_show"} = attendance, allowance, true) do
    BookingEntitlement.release(
      context,
      attendance.user_id,
      attendance.scheduled_class_id,
      allowance,
      %{
        reason: "No-show penalty waived by package",
        idempotency_key: "attendance-no-show-waived:#{attendance.id}"
      }
    )
  end

  defp reconcile_visit(context, attendance, allowance, _waived?) do
    BookingEntitlement.finalize(
      context,
      attendance.user_id,
      attendance.scheduled_class_id,
      allowance,
      %{
        reason: "Attendance recorded as #{attendance.status}",
        idempotency_key: "attendance-finalized:#{attendance.id}"
      }
    )
  end

  defp no_show_waived?(context, %{scheduled_class: %{scheduled_at: _} = slot, user_id: user_id}),
    do: BookingTerms.for_slot(context, user_id, slot).no_show_penalty_waived

  defp no_show_waived?(_context, _booking), do: false

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp approved_booking(nil, _slot_id, _user_id), do: {:error, :organization_context_required}

  defp approved_booking(context, slot_id, user_id) do
    case Scheduling.get_approved_booking_for_class(context, user_id, slot_id) do
      nil -> {:error, :attendance_requires_approved_booking}
      booking -> {:ok, booking}
    end
  end

  @doc false
  def announce_attendance(attendance) do
    Palee.DomainEvents.publish(:attendance_recorded, %{
      organization_id: attendance.organization_id,
      scheduled_class_id: attendance.scheduled_class_id,
      user_id: attendance.user_id,
      booking_id: Map.get(attendance, :booking_id),
      status: attendance.status,
      at: DateTime.utc_now()
    })
  end
end
