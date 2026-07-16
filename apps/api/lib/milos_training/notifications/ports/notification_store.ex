defmodule MilosTraining.Notifications.Ports.NotificationStore do
  @callback create_notification(map()) :: {:ok, map() | :duplicate} | {:error, Ecto.Changeset.t()}
  @callback list_for_user(Ecto.UUID.t()) :: [map()]
  @callback list_inbox_page(Ecto.UUID.t(), keyword()) :: %{
              notifications: [map()],
              next_cursor: String.t() | nil
            }
  @callback count_unread_inbox(Ecto.UUID.t()) :: non_neg_integer()
  @callback mark_all_read(Ecto.UUID.t()) :: non_neg_integer()
  @callback mark_read(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  @callback delete_booking_pending_for_booking(Ecto.UUID.t()) :: :ok
  @callback propagate_nickname_change(String.t(), String.t()) :: :ok
  @callback get_push_settings() :: map()
  @callback get_push_delivery_config() :: map()
  @callback update_push_settings(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
end
