defmodule MilosTraining.Application.TimeoutBooking do
  require Logger

  alias MilosTraining.Application.{BroadcastUserSync, ResolveJobTenantContext, ScheduleRealtime}
  alias MilosTraining.{Finance, Notifications, Scheduling}

  def call(organization_id, booking_id) do
    with {:ok, context} <-
           ResolveJobTenantContext.call(organization_id, __MODULE__ |> Atom.to_string()),
         {:ok, timed_out_booking} <- Scheduling.timeout_booking(context, booking_id) do
      reconcile_entitlement(context, timed_out_booking)
      dispatch_timeout_notification(timed_out_booking)
      broadcast_timeout(timed_out_booking)
      {:ok, timed_out_booking}
    else
      {:error, :not_found} -> :ok
      {:error, :booking_not_pending} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp reconcile_entitlement(context, booking) do
    _result =
      Finance.release_entitlement_source(
        context,
        booking.user_id,
        "scheduling",
        booking.scheduled_class_id,
        :class_visits,
        %{
          reason: "Booking request timed out",
          idempotency_key: "booking-timeout-release:#{booking.id}"
        }
      )

    BroadcastUserSync.for_user(booking.user_id, ["finance_entitlement"],
      reason: "class_visit_timeout_released"
    )

    :ok
  end

  defp dispatch_timeout_notification(booking) do
    case Notifications.dispatch_event(:booking_timed_out, booking) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "booking_timeout_notification_dispatch_failed booking_id=#{booking.id} reason=#{inspect(reason)}"
        )
    end
  rescue
    error ->
      Logger.warning(
        "booking_timeout_notification_dispatch_failed booking_id=#{booking.id} reason=#{Exception.message(error)}"
      )
  end

  defp broadcast_timeout(booking) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "booking:timeout",
      {:booking_timed_out, booking}
    )

    ScheduleRealtime.broadcast("booking_timed_out", booking)
  end
end
