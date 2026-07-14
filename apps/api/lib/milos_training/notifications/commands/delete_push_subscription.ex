defmodule MilosTraining.Notifications.Commands.DeletePushSubscription do
  alias MilosTraining.Notifications.PushSubscriptionStore

  def call(user_id, endpoint),
    do: PushSubscriptionStore.delete_push_subscription(user_id, endpoint)
end
