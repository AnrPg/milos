defmodule MilosTraining.Application.GetPushSubscriptionStatus do
  alias MilosTraining.Notifications

  def call(user_id, endpoint) when is_binary(endpoint) do
    Notifications.get_push_subscription_status(user_id, endpoint)
  end
end
