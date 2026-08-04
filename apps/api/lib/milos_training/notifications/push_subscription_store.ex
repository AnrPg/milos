defmodule MilosTraining.Notifications.PushSubscriptionStore do
  @behaviour MilosTraining.Notifications.Ports.PushSubscriptionStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  def with_user_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  defp adapter do
    Application.fetch_env!(:milos_training, :push_subscription_store)
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
