defmodule Palee.Application.MarkNotificationsRead do
  alias Palee.Application.RecordAnalyticsEvent
  alias Palee.Notifications

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
