defmodule MilosTraining.Workers.BookingNotificationJob do
  use Oban.Worker, queue: :notifications, max_attempts: 10

  alias MilosTraining.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"user_id" => user_id, "type" => type, "booking" => booking_payload}
      }) do
    Notifications.create_booking_notification_once(
      user_id,
      String.to_existing_atom(type),
      normalize_booking(booking_payload)
    )
  rescue
    ArgumentError -> {:error, :unknown_notification_type}
  end

  defp normalize_booking(%{} = booking) do
    %{
      id: booking["booking_id"] || booking[:booking_id],
      scheduled_class_id: booking["scheduled_class_id"] || booking[:scheduled_class_id],
      user_id: booking["user_id"] || booking[:user_id],
      status: String.to_existing_atom(booking["status"] || booking[:status]),
      admin_message: booking["admin_message"] || booking[:admin_message]
    }
  end
end
