defmodule MilosTraining.Notifications.Queries.GetPushSubscription do
  alias MilosTraining.Notifications.PushSubscriptionStore

  def call(user_id, endpoint), do: PushSubscriptionStore.get_push_subscription(user_id, endpoint)
end
