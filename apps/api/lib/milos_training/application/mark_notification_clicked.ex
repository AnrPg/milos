defmodule MilosTraining.Application.MarkNotificationClicked do
  alias MilosTraining.{Analytics, Notifications}
  alias MilosTraining.Application.RecordAnalyticsEvent

  def call(user_id, notification_id, params \\ %{}) do
    with :ok <- Notifications.mark_read(user_id, notification_id),
         {:ok, click_event} <- record_click(user_id, notification_id, params) do
      RecordAnalyticsEvent.call_unsafe("notification_clicked", %{
        user_id: user_id,
        context_type: "notification",
        context_id: notification_id,
        metadata: %{
          notification_click_event_id: click_event.id,
          url: click_event.url
        }
      })

      {:ok, click_event}
    end
  end

  defp record_click(user_id, notification_id, params) do
    Analytics.record_notification_click(%{
      notification_id: notification_id,
      user_id: user_id,
      url: params["url"] || params[:url],
      metadata: params["metadata"] || params[:metadata] || %{}
    })
  end
end
