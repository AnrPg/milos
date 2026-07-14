defmodule MilosTraining.Application.MarkNotificationsRead do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Notifications

  def call(user_id) do
    marked_count = Notifications.mark_all_read(user_id)

    if marked_count > 0 do
      RecordAnalyticsEvent.call_unsafe("notification_read", %{
        user_id: user_id,
        context_type: "notification_bulk_read",
        metadata: %{marked_count: marked_count}
      })
    end

    marked_count
  end
end
