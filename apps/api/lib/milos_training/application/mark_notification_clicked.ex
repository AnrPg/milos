defmodule MilosTraining.Application.MarkNotificationClicked do
  alias MilosTraining.{Analytics, Notifications}
  alias MilosTraining.Application.RecordAnalyticsEvent

  def call(user_id, notification_id, params \\ %{}) do
    # This route is deliberately not tenant-scoped (F-28 - the inbox spans
    # every organization a member belongs to), so there is no session GUC to
    # fall back on here. The notification's own organization_id is the only
    # correct source - it's read explicitly rather than relying on
    # EctoAnalyticsStore's session-derived default, which would silently
    # record every click as organization-less on this path.
    organization_id = Notifications.get_notification_organization_id(user_id, notification_id)

    with :ok <- Notifications.mark_read(user_id, notification_id),
         {:ok, click_event} <- record_click(user_id, notification_id, organization_id, params) do
      RecordAnalyticsEvent.call_unsafe("notification_clicked", %{
        organization_id: organization_id,
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

  defp record_click(user_id, notification_id, organization_id, params) do
    Analytics.record_notification_click(%{
      organization_id: organization_id,
      notification_id: notification_id,
      user_id: user_id,
      url: params["url"] || params[:url],
      metadata: params["metadata"] || params[:metadata] || %{}
    })
  end
end
