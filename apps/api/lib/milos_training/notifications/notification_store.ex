defmodule MilosTraining.Notifications.NotificationStore do
  @behaviour MilosTraining.Notifications.Ports.NotificationStore

  defp adapter do
    Application.fetch_env!(:milos_training, :notification_store)
  end

  @impl true
  def create_notification(params), do: adapter().create_notification(params)

  @impl true
  def list_for_user(user_id), do: adapter().list_for_user(user_id)

  @impl true
  def list_inbox_page(user_id, opts), do: adapter().list_inbox_page(user_id, opts)

  @impl true
  def count_unread_inbox(user_id), do: adapter().count_unread_inbox(user_id)

  @impl true
  def mark_all_read(user_id), do: adapter().mark_all_read(user_id)

  @impl true
  def mark_read(user_id, notification_id), do: adapter().mark_read(user_id, notification_id)

  @impl true
  def delete_booking_pending_for_booking(booking_id),
    do: adapter().delete_booking_pending_for_booking(booking_id)

  @impl true
  def propagate_nickname_change(old_nickname, new_nickname),
    do: adapter().propagate_nickname_change(old_nickname, new_nickname)

  @impl true
  def get_push_settings, do: adapter().get_push_settings()

  @impl true
  def get_push_delivery_config, do: adapter().get_push_delivery_config()

  @impl true
  def update_push_settings(params), do: adapter().update_push_settings(params)
end
