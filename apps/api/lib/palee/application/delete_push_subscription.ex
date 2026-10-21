defmodule Palee.Application.DeletePushSubscription do
  alias Palee.Notifications

  def call(user_id, endpoint) when is_binary(endpoint) do
    Notifications.delete_push_subscription(user_id, endpoint)
  end
end
