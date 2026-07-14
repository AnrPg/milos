defmodule MilosTraining.Workers.BookingTimeoutJob do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MilosTraining.Scheduling

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"booking_id" => booking_id}}) do
    case Scheduling.get_booking(booking_id) do
      %{status: :pending} = booking ->
        with :ok <- MilosTraining.Notifications.dispatch_event(:booking_timed_out, booking) do
          Phoenix.PubSub.broadcast(
            MilosTraining.PubSub,
            "booking:timeout",
            {:booking_timed_out, booking}
          )

          :ok
        end

      _ ->
        :ok
    end
  end
end
