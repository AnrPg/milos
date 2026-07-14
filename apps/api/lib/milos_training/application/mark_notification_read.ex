defmodule MilosTraining.Application.MarkNotificationRead do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Notifications

  def call(user_id, notification_id) do
    with :ok <- Notifications.mark_read(user_id, notification_id) do
      RecordAnalyticsEvent.call_unsafe("notification_read", %{
        user_id: user_id,
        context_type: "notification",
        context_id: notification_id
      })

      :ok
    end
  end
end
