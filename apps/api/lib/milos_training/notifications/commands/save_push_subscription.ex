defmodule MilosTraining.Notifications.Commands.SavePushSubscription do
  alias MilosTraining.Notifications.PushSubscriptionStore

  def call(params), do: PushSubscriptionStore.save_push_subscription(params)
end
