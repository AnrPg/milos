defmodule MilosTraining.Application.RecordNotificationDelivered do
  @moduledoc """
  Records `notification_in_app_delivered` (ADR-105) for every newly created
  in-app notification.

  The Notifications context emits `[:milos, :notification, :delivered]`
  telemetry when it persists a new notification; `attach/0` (called once at
  application start) subscribes `handle_event/4`, which runs synchronously in
  the delivering process and delegates to `call/1`. Notifications without
  tenant provenance are skipped (they cannot be tenant-scoped). The handler
  never raises, so telemetry never detaches it.
  """

  alias MilosTraining.Application.TrackAnalyticsEvent

  @event [:milos, :notification, :delivered]
  @handler_id "milos-analytics-notification-delivered"

  def attach do
    :telemetry.detach(@handler_id)
    :telemetry.attach(@handler_id, @event, &__MODULE__.handle_event/4, nil)
  end

  def handle_event(@event, _measurements, metadata, _config), do: call(metadata)

  def call(%{organization_id: organization_id, notification_id: notification_id} = metadata)
      when is_binary(organization_id) and is_binary(notification_id) do
    TrackAnalyticsEvent.call(
      "notification_in_app_delivered",
      nil,
      %{id: notification_id, type: metadata[:type]},
      %{organization_id: organization_id, user_id: metadata[:user_id]}
    )
  end

  def call(_metadata), do: :ok
end
