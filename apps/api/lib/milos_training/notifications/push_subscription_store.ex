defmodule MilosTraining.Notifications.PushSubscriptionStore do
  @behaviour MilosTraining.Notifications.Ports.PushSubscriptionStore

  defp adapter do
    Application.get_env(
      :milos_training,
      :push_subscription_store,
      MilosTraining.Infrastructure.Notifications.EctoPushSubscriptionStore
    )
  end

  @impl true
  def save_push_subscription(params), do: adapter().save_push_subscription(params)

  @impl true
  def list_push_subscriptions(user_id), do: adapter().list_push_subscriptions(user_id)

  @impl true
  def get_push_subscription(user_id, endpoint),
    do: adapter().get_push_subscription(user_id, endpoint)

  @impl true
  def delete_push_subscription(user_id, endpoint),
    do: adapter().delete_push_subscription(user_id, endpoint)
end
