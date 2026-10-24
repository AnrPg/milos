defmodule Palee.Notifications.Queries.DeliversNotification do
  @moduledoc """
  ADR-199: whether a notification of `type` reaches `user_id` on `channel`,
  by their notification choices. Asked at the two delivery chokepoints:
  `CreateNotification` (the bell) and `DispatchNotification` (push). When the
  choices cannot be read the notification goes out, as before preferences.
  """

  alias Palee.Notifications.Domain.NotificationCategories
  alias Palee.Notifications.NotificationPreferenceStore

  def call(user_id, type, channel) when is_binary(user_id) do
    choices =
      case NotificationPreferenceStore.list(%{user_id: user_id}) do
        choices when is_list(choices) -> choices
        _error -> []
      end

    NotificationCategories.delivers?(choices, type, channel)
  end

  def call(_user_id, _type, _channel), do: true
end
