defmodule Palee.Notifications.Queries.GetPushSubscription do
  alias Palee.Notifications.PushSubscriptionStore

  def call(user_id, endpoint), do: PushSubscriptionStore.get_push_subscription(user_id, endpoint)
end
