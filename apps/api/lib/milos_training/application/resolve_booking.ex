defmodule MilosTraining.Application.ResolveBooking do
  alias MilosTraining.Scheduling

  def call(booking_id, params) do
    action = Map.get(params, :action) || Map.get(params, "action")
    admin_message = Map.get(params, :admin_message) || Map.get(params, "admin_message")

    with booking when not is_nil(booking) <- Scheduling.get_booking(booking_id),
         {:ok, updated_booking} <- run_resolution(action, booking_id, admin_message) do
      maybe_cancel_timeout(booking.timeout_job_id)
      MilosTraining.Notifications.dispatch_event(:booking_resolved, updated_booking)
      broadcast_resolution(updated_booking)
      {:ok, updated_booking}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :bad_request}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_resolution(:approve, booking_id, admin_message),
    do: Scheduling.approve_booking(booking_id, admin_message)

  defp run_resolution("approve", booking_id, admin_message),
    do: run_resolution(:approve, booking_id, admin_message)

  defp run_resolution(:reject, booking_id, admin_message),
    do: Scheduling.reject_booking(booking_id, admin_message)

  defp run_resolution("reject", booking_id, admin_message),
    do: run_resolution(:reject, booking_id, admin_message)

  defp run_resolution(_, _booking_id, _admin_message), do: :error

  defp maybe_cancel_timeout(nil), do: :ok

  defp maybe_cancel_timeout(job_id) do
    case Oban.cancel_job(job_id) do
      {:ok, _job} -> :ok
      _ -> :ok
    end
  end

  defp broadcast_resolution(booking) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "booking:resolved",
      {:booking_resolved, booking}
    )
  end
end
