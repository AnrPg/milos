defmodule MilosTraining.Notifications.NotificationStore do
  @behaviour MilosTraining.Notifications.Ports.NotificationStore

  defp adapter do
    Application.get_env(
      :milos_training,
      :notification_store,
      MilosTraining.Infrastructure.Notifications.EctoNotificationStore
    )
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
end
