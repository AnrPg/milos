defmodule MilosTraining.Workers.BookingTimeoutJob do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MilosTraining.Application.ResolveJobTenantContext
  alias MilosTraining.Finance
  alias MilosTraining.Scheduling
  alias MilosTrainingWeb.Realtime

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"organization_id" => organization_id, "booking_id" => booking_id}
      }) do
    with {:ok, context} <-
           ResolveJobTenantContext.call(organization_id, __MODULE__ |> Atom.to_string()),
         booking when not is_nil(booking) <- Scheduling.get_booking(context, booking_id) do
      case booking do
        %{status: :pending} ->
          with {:ok, _entry} <-
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
                 ),
               :ok <- MilosTraining.Notifications.dispatch_event(:booking_timed_out, booking) do
            Realtime.broadcast_schedule_refresh("booking_timed_out", booking)
            :ok
          end

        _booking ->
          :ok
      end
    else
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{}), do: {:error, :missing_organization_scope}
end
