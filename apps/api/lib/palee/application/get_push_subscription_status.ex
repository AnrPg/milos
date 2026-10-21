defmodule Palee.Application.GetPushSubscriptionStatus do
  alias Palee.Notifications

  def call(user_id, endpoint) when is_binary(endpoint) do
    Notifications.get_push_subscription_status(user_id, endpoint)
  end
end
