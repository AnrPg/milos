defmodule MilosTraining.Notifications.Queries.GetPushSubscriptionStatus do
  alias MilosTraining.Notifications.Queries.GetPushSubscription

  def call(user_id, endpoint) do
    case GetPushSubscription.call(user_id, endpoint) do
      nil ->
        %{registered: false, subscription: nil}

      subscription ->
        %{registered: true, subscription: subscription}
    end
  end
end
