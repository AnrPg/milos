defmodule Palee.Notifications.Commands.SavePushSubscription do
  alias Palee.Notifications.PushSubscriptionStore

  def call(params), do: PushSubscriptionStore.save_push_subscription(params)
end
