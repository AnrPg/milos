defmodule MilosTraining.Notifications.Queries.ListPushSubscriptions do
  alias MilosTraining.Notifications.PushSubscriptionStore

  def call(user_id), do: PushSubscriptionStore.list_push_subscriptions(user_id)
end
