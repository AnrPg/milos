defmodule MilosTraining.Application.MarkNotificationClicked do
  alias MilosTraining.{Analytics, Notifications}
  alias MilosTraining.Analytics.AnalyticsStore
  alias MilosTraining.Notifications.NotificationStore
  alias MilosTraining.Application.RecordAnalyticsEvent

  # The notification lookup is owner-only under RLS, so the whole click runs in
  # the caller's user scope (TD-046).
  def call(context_or_user_id, notification_id, params \\ %{})

  def call(%{user_id: user_id} = context, notification_id, params)
      when is_binary(user_id) do
    NotificationStore.with_user_context(context, fn -> call(user_id, notification_id, params) end)
  end

  def call(user_id, notification_id, params) do
    # This route is deliberately not tenant-scoped (F-28 - the inbox spans
    # every organization a member belongs to), so there is no session GUC to
    # fall back on here. The notification's own organization_id is the only
    # correct source - it's read explicitly rather than relying on
    # EctoAnalyticsStore's session-derived default, which would silently
    # record every click as organization-less on this path.
    organization_id = Notifications.get_notification_organization_id(user_id, notification_id)

    with :ok <- Notifications.mark_read(user_id, notification_id),
         {:ok, click_event} <- record_click(user_id, notification_id, organization_id, params) do
      record_click_analytics(user_id, notification_id, organization_id, click_event)
      {:ok, click_event}
    end
  end

  # Click facts are tenant-owned rows (RLS admits only the session's
  # organization), so they are written inside the notification's own
  # organization scope (TD-046). Organization-less notifications have no tenant
  # to attribute a click to; they are only marked read.
  defp record_click(user_id, notification_id, organization_id, params)
       when is_binary(organization_id) do
    AnalyticsStore.with_tenant_context(
      %{organization_id: organization_id, user_id: user_id},
      fn ->
        Analytics.record_notification_click(%{
          organization_id: organization_id,
          notification_id: notification_id,
          user_id: user_id,
          url: params["url"] || params[:url],
          metadata: params["metadata"] || params[:metadata] || %{}
        })
      end
    )
  end

  defp record_click(_user_id, _notification_id, nil, params),
    do: {:ok, %{id: nil, url: params["url"] || params[:url]}}

  defp record_click_analytics(_user_id, _notification_id, nil, _click_event), do: :ok

  defp record_click_analytics(user_id, notification_id, organization_id, click_event) do
    AnalyticsStore.with_tenant_context(
      %{organization_id: organization_id, user_id: user_id},
      fn ->
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
      end
    )
  end
end
